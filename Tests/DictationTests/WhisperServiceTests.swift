import XCTest
import DictationCore
@testable import Dictation

final class WhisperServiceTests: XCTestCase {
    private func fixture(_ script: String) throws -> (URL, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DictationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("worker.py")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try Data().write(to: folder.appendingPathComponent("model.bin"))
        return (folder, url)
    }

    @MainActor
    func testChunkedUTF8ResultAndSingleActiveRequest() async throws {
        let (folder, url) = try fixture("""
        import json, sys, time
        print(json.dumps(dict(type='ready', device='cpu', compute_type='int8_float32')), flush=True)
        for line in sys.stdin:
            request = json.loads(line)
            data = (json.dumps(dict(type='result', id=request['id'], text='Привет 👋', seconds=0.1), ensure_ascii=False) + '\\n').encode()
            for byte in data:
                sys.stdout.buffer.write(bytes([byte]))
                sys.stdout.flush()
                time.sleep(0.001)
        """)
        defer { try? FileManager.default.removeItem(at: folder) }
        let ready = expectation(description: "ready")
        let result = expectation(description: "result")
        let service = WhisperService(scriptURL: url)
        defer { service.stop() }
        service.onError = { issue in XCTFail(issue.resolve(using: AppLocalization(language: .english))) }
        service.onReady = { device, _ in XCTAssertEqual(device, "cpu"); ready.fulfill() }
        var expectedID: String?
        service.onResult = { id, text, seconds in
            XCTAssertEqual(id, expectedID)
            XCTAssertEqual(text, "Привет 👋")
            XCTAssertEqual(seconds, 0.1)
            result.fulfill()
        }
        service.start(python: "/usr/bin/python3", model: folder.path, device: "cpu", beamSize: 1)
        await fulfillment(of: [ready], timeout: 10)
        expectedID = service.transcribe(url: folder.appendingPathComponent("audio.caf"), language: "ru")
        XCTAssertNotNil(expectedID)
        XCTAssertNil(service.transcribe(url: url, language: "ru"))
        await fulfillment(of: [result], timeout: 10)
        XCTAssertTrue(service.isReady)
    }

    @MainActor
    func testTimeoutStopsWorkerAndAllowsRestart() async throws {
        let (folder, url) = try fixture("import time\ntime.sleep(60)\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        let failed = expectation(description: "timeout")
        let service = WhisperService(scriptURL: url, startupTimeout: 0.15)
        defer { service.stop() }
        service.onError = { issue in
            XCTAssertTrue(issue.resolve(using: AppLocalization(language: .english)).contains("too long"))
            failed.fulfill()
        }
        service.start(python: "/usr/bin/python3", model: folder.path, device: "cpu", beamSize: 1)
        await fulfillment(of: [failed], timeout: 5)
        XCTAssertFalse(service.isReady)
        XCTAssertNil(service.transcribe(url: url, language: "ru"))
        try "import json, sys\nprint(json.dumps(dict(type='ready', device='cpu', compute_type='int8_float32')), flush=True)\nsys.stdin.read()\n".write(to: url, atomically: true, encoding: .utf8)
        let restarted = expectation(description: "restarted after timeout")
        service.onError = { issue in XCTFail(issue.resolve(using: AppLocalization(language: .english))) }
        service.onReady = { _, _ in restarted.fulfill() }
        service.start(python: "/usr/bin/python3", model: folder.path, device: "cpu", beamSize: 1)
        await fulfillment(of: [restarted], timeout: 5)
        XCTAssertTrue(service.isReady)
    }

    @MainActor
    func testMalformedWorkerResponseFailsInsteadOfWaitingForTimeout() async throws {
        let (folder, url) = try fixture("import time\nprint('not JSON', flush=True)\ntime.sleep(60)\n")
        defer { try? FileManager.default.removeItem(at: folder) }
        let failed = expectation(description: "invalid protocol")
        let service = WhisperService(scriptURL: url)
        defer { service.stop() }
        service.onError = { issue in
            XCTAssertTrue(issue.resolve(using: AppLocalization(language: .english)).contains("invalid response"))
            failed.fulfill()
        }
        service.start(python: "/usr/bin/python3", model: folder.path, device: "cpu", beamSize: 1)
        await fulfillment(of: [failed], timeout: 10)
        XCTAssertFalse(service.isReady)
    }
}

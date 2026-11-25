import AVFoundation
import XCTest
@testable import Dictation

final class AudioCaptureTests: XCTestCase {
    func testFileFinalizationStereoMixAndLateCallback() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DictationTests-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let capture = try AudioCaptureSession(url: url, format: format)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 9600)!
        buffer.frameLength = 9600
        for frame in 0..<9600 {
            buffer.floatChannelData![0][frame] = Float(0.3 * sin(2 * .pi * 700 * Double(frame) / 48000))
            buffer.floatChannelData![1][frame] = 0
        }
        capture.consume(buffer)
        XCTAssertFalse(capture.snapshot().failed)
        XCTAssertGreaterThan(capture.snapshot().bands.max()!, 0.5)
        XCTAssertEqual(capture.finish(), 0.2, accuracy: 1e-9)
        capture.consume(buffer)
        XCTAssertEqual(capture.finish(), 0.2, accuracy: 1e-9)
        let recording = try AVAudioFile(forReading: url)
        XCTAssertEqual(recording.length, 9600)
        XCTAssertEqual(recording.fileFormat.sampleRate, 48000)
        XCTAssertEqual(recording.fileFormat.channelCount, 2)
    }

    func testUnsupportedAndMismatchedFormatsFailSafely() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("DictationTests-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let integerFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 1, interleaved: false)!
        XCTAssertThrowsError(try AudioCaptureSession(url: url, format: integerFormat))
        let capture = try AudioCaptureSession(url: url, format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!)
        let buffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!, frameCapacity: 100)!
        buffer.frameLength = 100
        capture.consume(buffer)
        XCTAssertTrue(capture.snapshot().failed)
        XCTAssertEqual(capture.finish(), 0)
    }
}

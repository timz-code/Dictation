import Foundation
import DictationCore

final class WhisperService {
    var onReady: ((String, String) -> Void)?
    var onResult: ((String, String, Double) -> Void)?
    var onError: ((AppMessage) -> Void)?
    private let scriptURL: URL?
    private let startupTimeout: Double
    private let recognitionTimeout: Double
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var errors: Pipe?
    private var buffer = Data()
    private var deadline: DispatchWorkItem?
    private var activeID: String?
    private(set) var isReady = false

    init(scriptURL: URL? = nil, startupTimeout: Double = 120, recognitionTimeout: Double = 300) {
        self.scriptURL = scriptURL
        self.startupTimeout = startupTimeout
        self.recognitionTimeout = recognitionTimeout
    }

    func start(python: String, model: String, device: String, beamSize: Int) {
        stop()
        guard FileManager.default.isExecutableFile(atPath: python),
              FileManager.default.fileExists(atPath: model + "/model.bin") else {
            onError?(.key("error.pythonModel"))
            return
        }
        guard let script = scriptURL ?? Bundle.main.url(forResource: "whisper_worker", withExtension: "py") else {
            onError?(.key("error.workerMissing"))
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-I", "-u", script.path, "--model", model, "--device", device, "--beam-size", String(beamSize)]
        var environment = ProcessInfo.processInfo.environment
        environment["HF_HUB_OFFLINE"] = "1"
        environment["TRANSFORMERS_OFFLINE"] = "1"
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_DISABLE_TELEMETRY"] = "1"
        environment["DO_NOT_TRACK"] = "1"
        process.environment = environment
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        self.process = process
        self.input = input
        self.output = output
        self.errors = errors
        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self, let process, self.process === process else { return }
                self.receive(data)
            }
        }
        // Drain diagnostics so a full stderr pipe can never stall transcription.
        errors.fileHandleForReading.readabilityHandler = { handle in
            if handle.availableData.isEmpty { handle.readabilityHandler = nil }
        }
        process.terminationHandler = { [weak self] ended in
            DispatchQueue.main.async {
                guard let self, self.process === ended else { return }
                self.fail(.format("error.workerExited", [String(ended.terminationStatus)]))
            }
        }
        do {
            try process.run()
            armDeadline(seconds: startupTimeout, message: .key("error.workerStartupTimeout"))
        } catch { fail(.literal(error.localizedDescription)) }
    }

    func transcribe(url: URL, language: String) -> String? {
        guard isReady, activeID == nil, let input else { return nil }
        let id = UUID().uuidString
        do {
            var data = try JSONSerialization.data(withJSONObject: ["id": id, "audio": url.path, "language": language])
            data.append(0x0A)
            try input.fileHandleForWriting.write(contentsOf: data)
            activeID = id
            armDeadline(seconds: recognitionTimeout, message: .key("error.workerTimeout"))
            return id
        } catch { fail(.literal(error.localizedDescription)); return nil }
    }

    private func receive(_ data: Data) {
        guard buffer.count + data.count <= 8 * 1024 * 1024 else { fail(.key("error.protocol")); return }
        buffer.append(data)
        let sender = process
        while process === sender, let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = message["type"] as? String else { fail(.key("error.protocol")); return }
            switch type {
            case "ready":
                guard !isReady, let device = message["device"] as? String,
                      ["cpu", "mps"].contains(device), let precision = message["compute_type"] as? String else {
                    fail(.key("error.protocol")); return
                }
                deadline?.cancel()
                isReady = true
                onReady?(device, precision)
            case "result":
                guard let id = message["id"] as? String, id == activeID else { continue }
                deadline?.cancel()
                activeID = nil
                guard let text = message["text"] as? String, let seconds = message["seconds"] as? Double,
                      seconds.isFinite, seconds >= 0 else { fail(.key("error.protocol")); return }
                onResult?(id, text, seconds)
            case "error", "fatal":
                let code = message["code"] as? String ?? "workerFailure"
                let detail = message["error"] as? String ?? "Unknown error"
                let known = ["incomplete_model", "gpu_unavailable", "device_mismatch"]
                fail(.format("error." + (known.contains(code) ? code : "workerFailure"), [detail]))
                return
            default: break
            }
        }
    }

    private func armDeadline(seconds: Double, message: AppMessage) {
        deadline?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.fail(message) }
        deadline = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func fail(_ message: AppMessage) {
        stop()
        onError?(message)
    }

    func stop() {
        deadline?.cancel()
        deadline = nil
        output?.fileHandleForReading.readabilityHandler = nil
        errors?.fileHandleForReading.readabilityHandler = nil
        try? input?.fileHandleForWriting.close()
        let previous = process
        process = nil
        previous?.terminationHandler = nil
        if let previous, previous.isRunning {
            previous.terminate()
            // Native inference may delay SIGTERM handling; never leave an orphan worker.
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if previous.isRunning { kill(previous.processIdentifier, SIGKILL) }
            }
        }
        input = nil
        output = nil
        errors = nil
        buffer.removeAll()
        activeID = nil
        isReady = false
    }

    deinit { stop() }
}

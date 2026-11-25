import AVFoundation
import DictationCore

enum RecordingError: Error {
    case unavailable, unsupportedFormat, writeFailed
    var message: AppMessage {
        switch self {
        case .unavailable: return .key("error.microphone")
        case .unsupportedFormat: return .key("error.audioFormat")
        case .writeFailed: return .key("error.recordingFailed")
        }
    }
}

final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var capture: AudioCaptureSession?
    private var directory: URL?
    private var timer: Timer?
    private var configurationObserver: NSObjectProtocol?
    var onLevel: (([Double], TimeInterval) -> Void)?
    var onFailure: (() -> Void)?

    func start() throws {
        discard()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.directory = directory
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate.isFinite, format.sampleRate >= 8000, format.channelCount > 0 else {
            discard()
            throw RecordingError.unavailable
        }
        // Keep the hardware's native format. Whisper resamples/downmixes it;
        // the same PCM powers both the recording and the spectrum.
        let capture: AudioCaptureSession
        do { capture = try AudioCaptureSession(url: directory.appendingPathComponent("recording.caf"), format: format) }
        catch { discard(); throw error }
        self.engine = engine
        self.capture = capture
        input.installTap(onBus: 0, bufferSize: 512, format: format) { buffer, _ in capture.consume(buffer) }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            discard()
            throw error
        }
        configurationObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self, weak engine] _ in
            guard let self, let engine, self.engine === engine else { return }
            self.onFailure?()
        }
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            guard let self, let capture = self.capture else { return }
            let snapshot = capture.snapshot()
            guard !snapshot.failed, self.engine?.isRunning == true else { self.onFailure?(); return }
            self.onLevel?(snapshot.bands, snapshot.duration)
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
    }

    func stop() -> (url: URL, duration: TimeInterval, failed: Bool)? {
        timer?.invalidate()
        timer = nil
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        guard let capture else { return nil }
        let duration = capture.finish()
        self.capture = nil
        return (capture.url, duration, capture.snapshot().failed)
    }

    func discard() {
        _ = stop()
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    deinit { discard() }
}

/// The tap processes audio; the UI reads a small snapshot. Closing under the
/// same lock ensures no late callback writes after stop or before transcription.
final class AudioCaptureSession {
    let url: URL
    private let lock = NSLock()
    private let sampleRate: Double
    private let analyzer: SpectrumAnalyzer
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var failed = false
    private var mono: [Float] = []

    init(url: URL, format: AVAudioFormat) throws {
        // AVAudioFile.write and floatChannelData require a matching processing
        // format. Reject unsupported input instead of dereferencing channels.
        guard format.sampleRate.isFinite, format.sampleRate >= 8000,
              format.channelCount > 0, format.commonFormat == .pcmFormatFloat32,
              !format.isInterleaved else { throw RecordingError.unsupportedFormat }
        self.url = url
        sampleRate = format.sampleRate
        analyzer = SpectrumAnalyzer(sampleRate: format.sampleRate)
        // Channel layout is a processing property; on-disk PCM is interleaved.
        var fileSettings = format.settings
        fileSettings[AVLinearPCMIsNonInterleaved] = false
        file = try AVAudioFile(forWriting: url, settings: fileSettings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard let file, !failed else { return }
        guard buffer.format == file.processingFormat else { failed = true; return }
        do {
            try file.write(from: buffer)
            frames += AVAudioFramePosition(buffer.frameLength)
            guard let channels = buffer.floatChannelData else { failed = true; return }
            let length = Int(buffer.frameLength)
            if buffer.format.channelCount == 1 {
                analyzer.consume(UnsafeBufferPointer(start: channels[0], count: length))
            } else {
                if mono.count != length { mono = Array(repeating: 0, count: length) }
                for frame in 0..<length {
                    var value: Float = 0
                    for channel in 0..<Int(buffer.format.channelCount) { value += channels[channel][frame] }
                    mono[frame] = value / Float(buffer.format.channelCount)
                }
                mono.withUnsafeBufferPointer { analyzer.consume($0) }
            }
        } catch { failed = true }
    }

    func snapshot() -> (bands: [Double], duration: TimeInterval, failed: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (analyzer.bands, Double(frames) / sampleRate, failed)
    }

    @discardableResult
    func finish() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        file = nil // Finalize the header before Whisper opens the file.
        return Double(frames) / sampleRate
    }
}

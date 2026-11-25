import AppKit
import AVFoundation
import SwiftUI
import DictationCore

enum RecordingPhase: Equatable {
    case idle, recording, transcribing, success, copied, error
}

@MainActor
final class AppModel: ObservableObject {
    @Published var phase: RecordingPhase = .idle
    @Published var waveformLevels: [Double] = Array(repeating: 0, count: 25)
    @Published var duration: TimeInterval = 0
    @Published private var headlineMessage: AppMessage = .key("status.loading")
    @Published private var detailMessage: AppMessage = .key("status.loading.detail")
    @Published var interfaceLanguage: InterfaceLanguage {
        didSet {
            defaults.set(interfaceLanguage.rawValue, forKey: "interfaceLanguage")
            interfaceLanguageChanged?()
        }
    }
    var localization: AppLocalization { AppLocalization(language: interfaceLanguage.resolved()) }
    var headline: String { headlineMessage.resolve(using: localization) }
    var detail: String { detailMessage.resolve(using: localization) }
    func text(_ key: String, _ arguments: String...) -> String {
        localization.resolve(key, arguments: arguments)
    }
    @Published var modelReady = false
    @Published var modelLoading = true
    @Published var microphoneAllowed = false
    @Published var accessibilityAllowed = false
    @Published var shortcutReady = false
    @Published var lastTranscript = ""
    @Published var backendDescription = ""
    @Published var lastTranscriptionSeconds: Double?
    @Published var removePromotionalTail: Bool {
        didSet { defaults.set(removePromotionalTail, forKey: "removePromotionalTail") }
    }
    @Published var overlayPosition: OverlayPosition {
        didSet {
            defaults.set(overlayPosition.rawValue, forKey: "overlayPosition")
            overlayPositionChanged?()
        }
    }
    @Published var device: String {
        didSet {
            defaults.set(device, forKey: "device")
            if device != oldValue && started { restartModel() }
        }
    }
    @Published var beamSize: Int {
        didSet {
            defaults.set(beamSize, forKey: "beamSize")
            if beamSize != oldValue && started { restartModel() }
        }
    }
    @Published var pythonPath: String { didSet { defaults.set(pythonPath, forKey: "pythonPath") } }
    @Published var modelPath: String { didSet { defaults.set(modelPath, forKey: "modelPath") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }

    let shortcut = GlobalShortcut()
    private let audio = AudioRecorder()
    private let whisper = WhisperService()
    private let defaults: UserDefaults
    private var started = false
    private var permissionTimer: Timer?
    private var targetCaptureTask: Task<InsertionTarget?, Never>?
    private let insertionContext = InsertionContext()
    private var targetRevision: UInt64 = 0
    private var requestID: String?
    private var dismissWork: DispatchWorkItem?
    private var insertionTask: Task<Void, Never>?
    private var sleepObserver: NSObjectProtocol?
    private var lockObserver: NSObjectProtocol?
    var showOverlay: (() -> Void)?
    var hideOverlay: (() -> Void)?
    var showSettings: (() -> Void)?
    var overlayPositionChanged: (() -> Void)?
    var interfaceLanguageChanged: (() -> Void)?
    var busy: Bool { phase == .recording || phase == .transcribing }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/share/whisper-ru").path
        pythonPath = defaults.string(forKey: "pythonPath") ?? base + "/venv/bin/python"
        modelPath = defaults.string(forKey: "modelPath") ?? base + "/model"
        let selected = InterfaceLanguage(rawValue: defaults.string(forKey: "interfaceLanguage") ?? "") ?? .system
        interfaceLanguage = selected
        language = defaults.string(forKey: "language") ?? (selected.resolved() == .russian ? "ru" : "")
        device = defaults.string(forKey: "device") == "cpu" ? "cpu" : "mps"
        beamSize = defaults.integer(forKey: "beamSize") == 5 ? 5 : 1
        overlayPosition = OverlayPosition(rawValue: defaults.string(forKey: "overlayPosition") ?? "") ?? .bottom
        removePromotionalTail = defaults.object(forKey: "removePromotionalTail") as? Bool ?? true
    }

    func start() {
        guard !started else { return }
        started = true
        shortcut.onBegin = { [weak self] in self?.beginRecording() }
        shortcut.onEnd = { [weak self] in self?.finishRecording() }
        shortcut.onCancel = { [weak self] in self?.cancel() }
        audio.onLevel = { [weak self] bands, duration in
            guard let self else { return }
            self.waveformLevels = bands
            self.duration = duration
            if duration >= 180 { self.finishRecording() }
        }
        audio.onFailure = { [weak self] in self?.fail(.key("error.audioInterrupted")) }
        whisper.onReady = { [weak self] device, precision in
            guard let self else { return }
            self.modelReady = true
            self.modelLoading = false
            self.backendDescription = device == "mps" ? "Apple GPU · Metal · \(precision.uppercased())" : "CPU · \(precision.uppercased())"
            self.headlineMessage = .key("status.ready")
            self.detailMessage = .key("status.ready.detail")
        }
        whisper.onError = { [weak self] message in
            self?.modelReady = false
            self?.modelLoading = false
            self?.fail(message)
        }
        whisper.onResult = { [weak self] id, text, seconds in self?.received(id: id, text: text, seconds: seconds) }
        refreshPermissions()
        permissionTimer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermissions() }
        }
        if let permissionTimer { RunLoop.main.add(permissionTimer, forMode: .common) }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
        lockObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.cancel() }
        }
        restartModel()
    }

    func refreshPermissions() {
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAllowed = AXIsProcessTrusted()
        if busy && (!microphoneAllowed || !accessibilityAllowed) { cancel() }
        if accessibilityAllowed {
            insertionContext.start()
            shortcutReady = shortcut.start()
        } else {
            shortcut.stop()
            insertionContext.stop()
            shortcutReady = false
        }
    }

    func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                Task { @MainActor in self?.refreshPermissions() }
            }
        } else { openPrivacy("Privacy_Microphone") }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openPrivacy("Privacy_Accessibility")
    }

    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }

    func restartModel() {
        guard !busy else { return }
        dismissWork?.cancel()
        hideOverlay?()
        phase = .idle
        modelReady = false
        modelLoading = true
        backendDescription = ""
        headlineMessage = .key("status.loading")
        detailMessage = device == "mps" ? .key("status.loadingGPU") : .key("status.loadingCPU")
        whisper.start(python: NSString(string: pythonPath).expandingTildeInPath, model: NSString(string: modelPath).expandingTildeInPath, device: device, beamSize: beamSize)
    }

    func beginRecording() {
        guard !busy else { return }
        guard modelReady else {
            toast(.error, .key("status.notReady"), modelLoading ? .key("status.wait") : .key("status.restart"))
            return
        }
        guard microphoneAllowed, accessibilityAllowed else {
            showSettings?()
            return
        }
        dismissWork?.cancel()
        // Capture only the app identity synchronously. AX IPC can take hundreds
        // of milliseconds in other apps and must not hold up recording or UI.
        let destinationPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetRevision = insertionContext.revision
        cancelTargetCapture()
        if let destinationPID {
            targetCaptureTask = Task.detached(priority: .userInitiated) {
                InsertionTarget.capture(pid: destinationPID)
            }
        }
        waveformLevels = Array(repeating: 0, count: 25)
        duration = 0
        do {
            try audio.start()
            phase = .recording
            headlineMessage = .key("status.listening")
            detailMessage = .key("status.listening.detail")
            showOverlay?()
        } catch { fail((error as? RecordingError)?.message ?? .literal(error.localizedDescription)) }
    }

    func finishRecording() {
        guard phase == .recording, let recording = audio.stop() else { return }
        guard !recording.failed else { fail(RecordingError.writeFailed.message); return }
        guard recording.duration >= 0.3 else {
            audio.discard()
            cancelTargetCapture()
            toast(.idle, .key("status.tooShort"), .key("status.tooShort.detail"))
            return
        }
        phase = .transcribing
        headlineMessage = .key("status.transcribing")
        detailMessage = .literal(backendDescription)
        requestID = whisper.transcribe(url: recording.url, language: language)
        if requestID == nil { fail(.key("error.workerUnavailable")) }
    }

    private func received(id: String, text: String, seconds: Double) {
        guard requestID == id, phase == .transcribing else { return }
        requestID = nil
        audio.discard()
        lastTranscriptionSeconds = seconds
        let rawText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = removePromotionalTail ? TranscriptCleanup.removingPromotionalTail(from: rawText) : rawText
        guard !text.isEmpty else {
            cancelTargetCapture()
            toast(.idle, rawText.isEmpty ? .key("status.noSpeech") : .key("status.cleaned"), rawText.isEmpty ? .key("status.noSpeech.detail") : .key("status.cleaned.detail"))
            return
        }
        lastTranscript = text
        let capture = targetCaptureTask
        let revision = targetRevision
        insertionTask = Task { [weak self] in
            guard let self else { return }
            let destination = await capture?.value
            guard !Task.isCancelled else { return }
            let outcome = await TextInsertion.insert(text, target: destination, contextUnchanged: { [weak self] in
                self?.insertionContext.isMonitoring == true && self?.insertionContext.revision == revision
            })
            guard !Task.isCancelled else { return }
            switch outcome {
            case .pasted: self.toast(.success, .key("status.sent"), .key("status.sent.detail"), seconds: 0.8)
            case .readyToCopy: self.toast(.copied, .key("status.readyToCopy"), .key("status.readyToCopy.detail"))
            case .copied: self.toast(.copied, .key("status.copied"), .key("status.copied.detail"))
            }
            self.insertionTask = nil
            self.targetCaptureTask = nil
        }
    }

    func cancel() {
        guard busy else { return }
        let needsWorkerRestart = requestID != nil
        shortcut.cancelCurrentHold()
        insertionTask?.cancel()
        insertionTask = nil
        requestID = nil
        audio.discard()
        cancelTargetCapture()
        phase = .idle
        if needsWorkerRestart { restartModel() }
        toast(.idle, .key("status.cancelled"), .key("status.cancelled.detail"))
    }

    private func fail(_ message: AppMessage) {
        insertionTask?.cancel()
        insertionTask = nil
        shortcut.cancelCurrentHold()
        audio.discard()
        cancelTargetCapture()
        requestID = nil
        toast(.error, .key("status.failed"), message, seconds: 6)
    }

    private func cancelTargetCapture() {
        targetCaptureTask?.cancel()
        targetCaptureTask = nil
    }

    private func toast(_ phase: RecordingPhase, _ title: AppMessage, _ subtitle: AppMessage, seconds: Double = 2.8) {
        dismissWork?.cancel()
        self.phase = phase
        headlineMessage = title
        detailMessage = subtitle
        showOverlay?()
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.busy else { return }
            self.hideOverlay?()
            if self.phase != .error { self.phase = .idle }
        }
        dismissWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    func preview() {
        guard !busy else { return }
        toast(.success, .key("status.preview"), .key("status.preview.detail"), seconds: 4)
    }

    func shutdown() {
        started = false
        dismissWork?.cancel()
        permissionTimer?.invalidate()
        permissionTimer = nil
        insertionTask?.cancel()
        cancelTargetCapture()
        audio.discard()
        whisper.stop()
        shortcut.stop()
        insertionContext.stop()
        if let sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver) }
        if let lockObserver { NSWorkspace.shared.notificationCenter.removeObserver(lockObserver) }
    }
}

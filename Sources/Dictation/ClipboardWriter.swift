import AppKit

/// A single restoration transaction spans overlapping, fast dictations. Never
/// restore a previous dictation as if it were the user's original clipboard.
@MainActor
final class ClipboardWriter {
    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]
    private let pasteboard: NSPasteboard
    private var original: Snapshot?
    private var expectedChangeCount: Int?
    private var restoreWork: DispatchWorkItem?

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    func copy(_ text: String) {
        cancelRestoration()
        write(text)
    }

    func preparePaste(_ text: String) {
        restoreWork?.cancel()
        if expectedChangeCount != pasteboard.changeCount {
            let count = pasteboard.changeCount
            let snapshot = (pasteboard.pasteboardItems ?? []).map { item in
                item.types.compactMap { type -> (NSPasteboard.PasteboardType, Data)? in
                    guard let data = item.data(forType: type) else { return nil }
                    return (type, data)
                }
            }
            // A promised representation can take time to load. Do not restore
            // a mixed snapshot if another app changes the clipboard meanwhile.
            original = pasteboard.changeCount == count ? snapshot : nil
        }
        write(text)
        expectedChangeCount = pasteboard.changeCount
        let count = pasteboard.changeCount
        let work = DispatchWorkItem { [weak self] in
            guard self?.expectedChangeCount == count else { return }
            self?.restoreIfUnchanged()
        }
        restoreWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    var isPrepared: Bool { expectedChangeCount == pasteboard.changeCount }

    func restoreIfUnchanged() {
        defer { cancelRestoration() }
        guard isPrepared, let original else { return }
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        let items = original.map { representations in
            let item = NSPasteboardItem()
            for (type, data) in representations { item.setData(data, forType: type) }
            return item
        }
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }

    private func write(_ text: String) {
        // Apple's local-only option prevents sharing dictation via Handoff /
        // Universal Clipboard. It applies to manual copies and fallbacks too.
        pasteboard.prepareForNewContents(with: .currentHostOnly)
        pasteboard.setString(text, forType: .string)
    }

    private func cancelRestoration() {
        restoreWork?.cancel()
        restoreWork = nil
        original = nil
        expectedChangeCount = nil
    }
}

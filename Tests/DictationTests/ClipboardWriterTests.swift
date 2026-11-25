import AppKit
import XCTest
@testable import Dictation

final class ClipboardWriterTests: XCTestCase {
    @MainActor
    func testOverlappingDictationsRestoreOriginalRichClipboard() {
        let board = NSPasteboard(name: .init("DictationTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("original", forType: .string)
        let rich = Data([1, 2, 3, 4])
        item.setData(rich, forType: .rtf)
        board.writeObjects([item])
        let writer = ClipboardWriter(pasteboard: board)
        writer.preparePaste("first dictation")
        writer.preparePaste("second dictation")
        XCTAssertEqual(board.string(forType: .string), "second dictation")
        writer.restoreIfUnchanged()
        XCTAssertEqual(board.string(forType: .string), "original")
        XCTAssertEqual(board.data(forType: .rtf), rich)
    }

    @MainActor
    func testUserCopyIsNotOverwrittenByRestoration() {
        let board = NSPasteboard(name: .init("DictationTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let writer = ClipboardWriter(pasteboard: board)
        writer.preparePaste("dictation")
        board.clearContents()
        board.setString("user copied something new", forType: .string)
        writer.restoreIfUnchanged()
        XCTAssertEqual(board.string(forType: .string), "user copied something new")
    }

    @MainActor
    func testManualCopyCancelsPendingRestorationAndBecomesNextBaseline() {
        let board = NSPasteboard(name: .init("DictationTests.\(UUID().uuidString)"))
        defer { board.releaseGlobally() }
        let writer = ClipboardWriter(pasteboard: board)
        writer.preparePaste("automatic")
        writer.copy("manual")
        writer.restoreIfUnchanged()
        XCTAssertEqual(board.string(forType: .string), "manual")
        writer.preparePaste("next dictation")
        writer.restoreIfUnchanged()
        XCTAssertEqual(board.string(forType: .string), "manual")
    }
}

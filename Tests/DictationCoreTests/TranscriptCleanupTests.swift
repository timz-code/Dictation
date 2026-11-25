import XCTest
@testable import DictationCore

final class TranscriptCleanupTests: XCTestCase {
    private let junk = "Подписывайтесь на наш канал, ставьте лайки и подписывайтесь на наш канал."

    func testRemovesOnlyTrailingPhrase() {
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: "Добавь выбор микрофона. " + junk), "Добавь выбор микрофона.")
    }

    func testHandlesCasePunctuationAndLineBreaks() {
        let text = "Готово! ПОДПИСЫВАЙТЕСЬ на наш канал!\nСтавьте лайки, и подписывайтесь на наш канал…"
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: text), "Готово!")
    }

    func testAllJunkBecomesEmpty() {
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: junk), "")
    }

    func testRepeatedTailIsFullyRemoved() {
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: "Текст. " + junk + " " + junk), "Текст.")
    }

    func testPhraseInsideTextIsPreserved() {
        let text = "Он сказал: «\(junk)» Это нужно обсудить."
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: text), text)
    }

    func testShorterAndDifferentPhrasesArePreserved() {
        for text in ["Подписывайтесь на наш канал.", "Ставьте лайки.", "Подписывайтесь на ваш канал, ставьте лайки и подписывайтесь на наш канал."] {
            XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: text), text)
        }
    }

    func testQuotedSuffixAndMissingConjunction() {
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: "Привет. «\(junk)»"), "Привет.")
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: "Привет. Подписывайтесь на наш канал, ставьте лайки, подписывайтесь на наш канал!"), "Привет.")
    }

    func testEmptyAndOrdinaryText() {
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: " \n "), "")
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: "Открой настройки канала."), "Открой настройки канала.")
    }
}

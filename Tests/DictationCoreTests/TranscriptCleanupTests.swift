import XCTest
@testable import DictationCore

final class TranscriptCleanupTests: XCTestCase {
    private let junk = "Подписывайтесь на наш канал, ставьте лайки и подписывайтесь на наш канал."
    private let commentsJunk = "Подписывайтесь на наш канал, ставьте лайки и пишите комментарии."

    func testRemovesCommentsOutroAtEnd() {
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: "Добавь кнопку. " + commentsJunk), "Добавь кнопку.")
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: commentsJunk), "")
    }

    func testCommentsOutroHandlesCasePunctuationAndQuotes() {
        let text = "Готово! «ПОДПИСЫВАЙТЕСЬ на наш канал!\nСтавьте лайки, и пишите комментарии…»\n"
        XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: text), "Готово!")
    }

    func testMixedRepeatedOutrosAreRemovedInEitherOrder() {
        for tail in [junk + " " + commentsJunk, commentsJunk + " " + junk] {
            XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: "Текст. " + tail), "Текст.")
        }
    }

    func testCommentsOutroInsideTextAndSimilarPhrasesArePreserved() {
        for text in [
            "Он сказал: «\(commentsJunk)» Это нужно обсудить.",
            "Пишите комментарии.",
            "Ставьте лайки и пишите комментарии.",
            "Подписывайтесь на ваш канал, ставьте лайки и пишите комментарии.",
            "Подписывайтесь на наш канал, ставьте лайки и пишите комментарии к коду."
        ] {
            XCTAssertEqual(TranscriptCleanup.removingPromotionalTail(from: text), text)
        }
    }

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

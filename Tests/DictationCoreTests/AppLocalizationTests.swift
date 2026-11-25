import XCTest
@testable import DictationCore

final class AppLocalizationTests: XCTestCase {
    func testSystemUsesRussianOnlyForPrimaryRussianLanguage() {
        for primary in ["ru", "ru-RU", "ru_KZ"] {
            XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: [primary, "en"]), .russian)
        }
        for languages in [["en-US", "ru"], ["fr", "ru"], ["tr-TR"], []] {
            XCTAssertEqual(InterfaceLanguage.system.resolved(preferredLanguages: languages), .english)
        }
    }

    func testExplicitChoiceOverridesSystem() {
        XCTAssertEqual(InterfaceLanguage.english.resolved(preferredLanguages: ["ru"]), .english)
        XCTAssertEqual(InterfaceLanguage.russian.resolved(preferredLanguages: ["en"]), .russian)
    }

    func testEnglishAndRussianResourcesAndDynamicMessages() {
        let en = AppLocalization(language: .english)
        let ru = AppLocalization(language: .russian)
        XCTAssertEqual(en.text("status.listening"), "Listening")
        XCTAssertEqual(ru.text("status.listening"), "Слушаю")
        let message = AppMessage.format("error.workerExited", ["9"])
        XCTAssertTrue(message.resolve(using: en).contains("code 9"))
        XCTAssertTrue(message.resolve(using: ru).contains("код 9"))
        XCTAssertEqual(en.text("model.current", "CPU"), "Currently: CPU")
    }
}

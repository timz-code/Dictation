import XCTest
import DictationCore
@testable import Dictation

final class AppModelTests: XCTestCase {
    @MainActor
    func testLanguageSwitchIsImmediatePersistedAndIndependentOfSpeech() {
        let suite = "DictationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("ru", forKey: "language")
        let model = AppModel(defaults: defaults)
        defer { model.shutdown() }
        XCTAssertEqual(model.interfaceLanguage, .system)
        model.interfaceLanguage = .english
        model.preview()
        XCTAssertEqual(model.headline, "Your dictation indicator")
        model.interfaceLanguage = .russian
        XCTAssertEqual(model.headline, "Так выглядит диктовка")
        XCTAssertEqual(model.language, "ru")
        XCTAssertEqual(AppModel(defaults: defaults).interfaceLanguage, .russian)
        XCTAssertEqual(defaults.string(forKey: "interfaceLanguage"), "ru")
    }

    @MainActor
    func testInvalidSavedOptionsUseSupportedDefaults() {
        let suite = "DictationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("obsolete", forKey: "interfaceLanguage")
        defaults.set("cuda", forKey: "device")
        defaults.set(99, forKey: "beamSize")
        let model = AppModel(defaults: defaults)
        XCTAssertEqual(model.interfaceLanguage, .system)
        XCTAssertEqual(model.device, "mps")
        XCTAssertEqual(model.beamSize, 1)
    }
}

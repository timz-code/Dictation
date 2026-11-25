import XCTest
@testable import DictationCore

final class InsertionPolicyTests: XCTestCase {
    func testNativeFieldRemainsSupported() {
        XCTAssertTrue(InsertionPolicy.allowsPaste(sameApplication: true, contextUnchanged: true, window: .same, element: .same))
    }

    func testMissingWebEditorAXElementAllowsPasteInUnchangedWindow() {
        XCTAssertTrue(InsertionPolicy.allowsPaste(sameApplication: true, contextUnchanged: true, window: .same, element: .unavailable))
    }

    func testRecreatedWebFieldAllowsPasteWithSameDescription() {
        XCTAssertTrue(InsertionPolicy.allowsPaste(sameApplication: true, contextUnchanged: true, window: .same, element: .different, sameFieldDescription: true))
    }

    func testUnknownWindowAndUnknownFieldCannotAuthorizePaste() {
        XCTAssertFalse(InsertionPolicy.allowsPaste(sameApplication: true, contextUnchanged: true, window: .unavailable, element: .unavailable))
    }

    func testSwitchingApplicationsOrWindowsPreventsPaste() {
        XCTAssertFalse(InsertionPolicy.allowsPaste(sameApplication: false, contextUnchanged: true, window: .same, element: .same))
        XCTAssertFalse(InsertionPolicy.allowsPaste(sameApplication: true, contextUnchanged: true, window: .different, element: .same))
    }

    func testClickTypingOrSwitchingAwayAndBackPreventsAllFallbacks() {
        for element: FocusComparison in [.same, .different, .unavailable] {
            XCTAssertFalse(InsertionPolicy.allowsPaste(sameApplication: true, contextUnchanged: false, window: .same, element: element, sameFieldDescription: true))
        }
    }

    func testDifferentKnownFieldPreventsPaste() {
        XCTAssertFalse(InsertionPolicy.allowsPaste(sameApplication: true, contextUnchanged: true, window: .same, element: .different))
    }
}

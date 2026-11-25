import XCTest
@testable import DictationCore

final class HoldShortcutTests: XCTestCase {
    func testControlThenGlobeAndReleaseEitherKey() {
        for releaseGlobe in [true, false] {
            var shortcut = HoldShortcut()
            XCTAssertNil(shortcut.update(keyCode: 59, control: true, function: false, otherModifier: false))
            XCTAssertEqual(shortcut.update(keyCode: 63, control: true, function: true, otherModifier: false), .began)
            XCTAssertNil(shortcut.update(keyCode: 59, control: true, function: true, otherModifier: false))
            XCTAssertEqual(shortcut.update(keyCode: releaseGlobe ? 63 : 59, control: releaseGlobe, function: !releaseGlobe, otherModifier: false), .ended)
        }
    }

    func testGlobeThenControl() {
        var shortcut = HoldShortcut()
        XCTAssertNil(shortcut.update(keyCode: 63, control: false, function: true, otherModifier: false))
        XCTAssertEqual(shortcut.update(keyCode: 59, control: true, function: true, otherModifier: false), .began)
    }

    func testArrowDoesNotImpersonateGlobe() {
        var shortcut = HoldShortcut()
        XCTAssertNil(shortcut.update(keyCode: 126, control: true, function: true, otherModifier: false))
        XCTAssertFalse(shortcut.isHeld)
    }

    func testCancelRequiresReleaseBeforeRestart() {
        var shortcut = HoldShortcut()
        _ = shortcut.update(keyCode: 63, control: true, function: true, otherModifier: false)
        shortcut.cancel()
        XCTAssertNil(shortcut.update(keyCode: 59, control: true, function: true, otherModifier: false))
        XCTAssertNil(shortcut.update(keyCode: 63, control: true, function: false, otherModifier: false))
        XCTAssertEqual(shortcut.update(keyCode: 63, control: true, function: true, otherModifier: false), .began)
    }

    func testExtraModifierStopsRecording() {
        var shortcut = HoldShortcut()
        _ = shortcut.update(keyCode: 63, control: true, function: true, otherModifier: false)
        XCTAssertEqual(shortcut.update(keyCode: 56, control: true, function: true, otherModifier: true), .ended)
        // Releasing Shift while still holding the chord must not start a new
        // recording after the first transcription has already finished.
        XCTAssertNil(shortcut.update(keyCode: 56, control: true, function: true, otherModifier: false))
        XCTAssertNil(shortcut.update(keyCode: 59, control: false, function: true, otherModifier: false))
        XCTAssertEqual(shortcut.update(keyCode: 59, control: true, function: true, otherModifier: false), .began)
    }

    func testUnrelatedEventWithoutFnFlagDoesNotReleasePhysicalGlobe() {
        var shortcut = HoldShortcut()
        _ = shortcut.update(keyCode: 59, control: true, function: false, otherModifier: false)
        XCTAssertEqual(shortcut.update(keyCode: 63, control: true, function: true, otherModifier: false), .began)
        // Session flags can omit Fn after the event tap consumes the Globe press.
        for _ in 0..<20 {
            XCTAssertNil(shortcut.update(keyCode: 57, control: true, function: false, otherModifier: false))
            XCTAssertTrue(shortcut.isHeld)
        }
        XCTAssertEqual(shortcut.update(keyCode: 63, control: true, function: false, otherModifier: false), .ended)
    }

    func testGlobeFirstWorksWhenControlEventOmitsFnFlag() {
        var shortcut = HoldShortcut()
        XCTAssertNil(shortcut.update(keyCode: 63, control: false, function: true, otherModifier: false))
        XCTAssertEqual(shortcut.update(keyCode: 59, control: true, function: false, otherModifier: false), .began)
        XCTAssertEqual(shortcut.update(keyCode: 59, control: false, function: false, otherModifier: false), .ended)
    }

    func testReleasingControlThenGlobeDoesNotEndTwice() {
        var shortcut = HoldShortcut()
        _ = shortcut.update(keyCode: 63, control: true, function: true, otherModifier: false)
        XCTAssertEqual(shortcut.update(keyCode: 59, control: false, function: false, otherModifier: false), .ended)
        XCTAssertNil(shortcut.update(keyCode: 63, control: false, function: false, otherModifier: false))
        XCTAssertFalse(shortcut.isHeld)
    }
}

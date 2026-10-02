import Testing
import Foundation
@testable import SuperAgent

/// The conversation makes room for a keyboard that is on screen, and only
/// stays put for a hardware keyboard's strip.
struct KeyboardRoomTests {
    private let screen: CGFloat = 844

    @Test func aRealKeyboardIsOnScreen() {
        #expect(KeyboardRoom.onScreen(frame: CGRect(x: 0, y: 508, width: 390, height: 336), screenHeight: screen))
        // A phone's, on its side.
        #expect(KeyboardRoom.onScreen(frame: CGRect(x: 0, y: 190, width: 844, height: 200), screenHeight: 390))
    }

    @Test func aHardwareKeyboardsStripIsNot() {
        // The keyboard keeps its full height and sits below the screen; only
        // the strip shows.
        #expect(!KeyboardRoom.onScreen(frame: CGRect(x: 0, y: 775, width: 390, height: 336), screenHeight: screen))
        #expect(!KeyboardRoom.onScreen(frame: CGRect(x: 0, y: 844, width: 390, height: 336), screenHeight: screen))
        #expect(!KeyboardRoom.onScreen(frame: .zero, screenHeight: screen))
    }

    @Test func onlyAStripWithAKeyboardAttachedIsIgnored() {
        #expect(KeyboardRoom.ignoresKeyboard(hardwareAttached: true, onScreen: false))
        #expect(!KeyboardRoom.ignoresKeyboard(hardwareAttached: true, onScreen: true))
        #expect(!KeyboardRoom.ignoresKeyboard(hardwareAttached: false, onScreen: true))
        #expect(!KeyboardRoom.ignoresKeyboard(hardwareAttached: false, onScreen: false))
    }
}

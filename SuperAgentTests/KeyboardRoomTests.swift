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

    /// A Magic Keyboard's strip is evidence of a hardware keyboard on its own:
    /// GameController is not always ready to say so when a chat appears, and
    /// trusting only it left a strip's height of empty room under the composer.
    @Test func aStripIsAStripWithoutBeingTold() {
        // The iPad's keyboard, parked below the screen with its strip showing.
        #expect(KeyboardRoom.isStrip(frame: CGRect(x: 0, y: 1150, width: 834, height: 400), screenHeight: 1210))
        // A real keyboard is not a strip, and nothing at all is not one either.
        #expect(!KeyboardRoom.isStrip(frame: CGRect(x: 0, y: 810, width: 834, height: 400), screenHeight: 1210))
        #expect(!KeyboardRoom.isStrip(frame: .zero, screenHeight: 1210))
    }
}

/// A picture in a reply keeps its own shape inside the most it may take.
struct MarkdownImageSizeTests {
    @Test func aTallScreenshotIsTallNotASliverInAWideBox() {
        let s = MarkdownImage.fitted(CGSize(width: 1206, height: 2622), within: CGSize(width: 240, height: 200))
        #expect(s.height == 200)
        #expect(abs(s.width / s.height - 1206 / 2622) < 0.01)
    }

    @Test func aWidePictureFillsTheWidth() {
        let s = MarkdownImage.fitted(CGSize(width: 2000, height: 1000), within: CGSize(width: 360, height: 280))
        #expect(s == CGSize(width: 360, height: 180))
    }

    @Test func aSmallPictureIsNotBlownUp() {
        #expect(MarkdownImage.fitted(CGSize(width: 64, height: 32), within: CGSize(width: 240, height: 200))
                == CGSize(width: 64, height: 32))
    }
}

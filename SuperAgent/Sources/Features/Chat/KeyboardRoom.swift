import GameController
import UIKit

/// Whether the conversation should make room for the keyboard.
///
/// A hardware keyboard leaves only the system's thin shortcuts strip on
/// screen, and SwiftUI's keyboard-avoidance reserves a full keyboard's room
/// for it anyway — so the conversation stops avoiding the keyboard while one
/// is attached. But "attached" is only what GameController says, and it says
/// so in cases where the on-screen keyboard comes up regardless: a phone that
/// Xcode's Device Hub has lent a "Generic Keyboard", a simulator borrowing the
/// Mac's, a Bluetooth keyboard with the on-screen one called back up. Trusting
/// it alone put that keyboard straight over the composer. What the keyboard
/// actually covers decides; the attached keyboard only explains a strip.
enum KeyboardRoom {
    /// Taller than any shortcuts strip, shorter than any real keyboard (a
    /// phone's in landscape is about 160pt).
    static let stripLimit: CGFloat = 120

    static var hardwareAttached: Bool {
        #if DEBUG
        // `-hardwareKeyboard`: claim one, the way a phantom keyboard does, on
        // a simulator that still shows the on-screen keyboard.
        if ProcessInfo.processInfo.arguments.contains("-hardwareKeyboard") { return true }
        #endif
        return GCKeyboard.coalesced != nil
    }

    /// How much of the screen the keyboard takes once it has settled at `frame`
    /// (screen coordinates, as the keyboard notifications give it).
    static func covered(frame: CGRect, screenHeight: CGFloat) -> CGFloat {
        max(0, min(frame.maxY, screenHeight) - max(frame.minY, 0))
    }

    /// A real keyboard is on screen, whatever is attached.
    static func onScreen(frame: CGRect, screenHeight: CGFloat) -> Bool {
        covered(frame: frame, screenHeight: screenHeight) > stripLimit
    }

    /// Leave the conversation where it is: there is a hardware keyboard and
    /// nothing on screen but its strip.
    static func ignoresKeyboard(hardwareAttached: Bool, onScreen: Bool) -> Bool {
        hardwareAttached && !onScreen
    }
}

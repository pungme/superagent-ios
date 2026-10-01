import Foundation
import UIKit

/// What to call the device in hand: "this phone" reads wrong on an iPad.
@MainActor var thisDevice: String { UIDevice.current.userInterfaceIdiom == .pad ? "this iPad" : "this phone" }

/// Which device a message was sent from, carried in the message's own id.
///
/// The Mac only records "from iOS", so a message typed on the iPad read "from
/// this phone" on the iPad, and on the iPhone too. The id is this app's to
/// choose (the Mac echoes it back untouched), so it says what kind of device
/// made it and which one: `Lp-1a2b-5E2AF2D5` is an iPad, `Li-…` an iPhone.
/// Ids from before this (`L-5E2AF2D5`) say neither.
enum MessageOrigin {
    @MainActor private static var kind: String { UIDevice.current.userInterfaceIdiom == .pad ? "p" : "i" }
    private static var tag: String { String(DeviceIdentity.id.prefix(4)) }

    @MainActor static func newId() -> String { "L\(kind)-\(tag)-" + UUID().uuidString.prefix(8) }

    /// "from this iPad", "from iPhone", …
    @MainActor static func label(forMessage id: String) -> String {
        let parts = id.split(separator: "-")
        guard parts.count == 3, parts[0] == "Li" || parts[0] == "Lp" else { return "from \(thisDevice)" }
        if parts[1] == tag { return "from \(thisDevice)" }
        return parts[0] == "Lp" ? "from iPad" : "from iPhone"
    }
}

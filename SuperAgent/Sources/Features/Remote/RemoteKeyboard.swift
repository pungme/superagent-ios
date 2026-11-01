import SwiftUI
import UIKit

// MARK: - The phone's keyboard, for the Mac

/// Typing for the Mac with the system keyboard: a responder that takes the
/// keyboard and hands each key on as it is pressed, keeping no text of its own
/// (the text is on the Mac). Over the keyboard, a row of the Mac keys a phone's
/// keyboard lacks, with ⌃ ⌥ ⌘ ⇧ that stay down for the next key.
struct RemoteKeyboardHost: UIViewRepresentable {
    @Binding var active: Bool
    let controller: RemoteController

    func makeUIView(context: Context) -> RemoteKeyCatcher {
        let v = RemoteKeyCatcher()
        v.controller = controller
        v.onDone = { active = false }
        return v
    }

    func updateUIView(_ v: RemoteKeyCatcher, context: Context) {
        v.controller = controller
        v.onDone = { active = false }
        if active, !v.isFirstResponder {
            DispatchQueue.main.async { v.becomeFirstResponder() }
        } else if !active, v.isFirstResponder {
            DispatchQueue.main.async { v.resignFirstResponder() }
        }
    }
}

final class RemoteKeyCatcher: UIView, UIKeyInput {
    weak var controller: RemoteController?
    var onDone: (() -> Void)?

    // What the Mac gets is what was pressed: no corrections it never sees.
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }

    func insertText(_ text: String) {
        MainActor.assumeIsolated { controller?.type(text) }
    }

    func deleteBackward() {
        MainActor.assumeIsolated { controller?.press("delete") }
    }

    private lazy var strip: UIView = {
        let host = UIHostingController(rootView: RemoteKeyStrip(controller: controller, done: { [weak self] in
            _ = self?.resignFirstResponder()
            self?.onDone?()
        }))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        let bar = UIInputView(frame: CGRect(x: 0, y: 0, width: 320, height: 48), inputViewStyle: .keyboard)
        bar.allowsSelfSizing = false
        bar.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: bar.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
        ])
        hostRef = host
        return bar
    }()
    private var hostRef: UIViewController?

    override var inputAccessoryView: UIView? { strip }

    /// A hardware keyboard (an iPad's): arrows, escape and the like, and every
    /// shortcut with ⌘ ⌃ ⌥ in it, which UIKeyInput does not hand on.
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var rest = Set<UIPress>()
        for press in presses {
            guard let k = press.key else { rest.insert(press); continue }
            let flags = k.modifierFlags
            var mods: [RemoteMod] = []
            if flags.contains(.control) { mods.append(.ctrl) }
            if flags.contains(.alternate) { mods.append(.opt) }
            if flags.contains(.command) { mods.append(.cmd) }
            if flags.contains(.shift) { mods.append(.shift) }
            if let name = RemoteKeys.named(k.keyCode) {
                // Plain Return, Tab and Delete are inserted as text by UIKit: not twice.
                let plain = mods.isEmpty || mods == [.shift]
                if plain, ["return", "tab", "delete"].contains(name) { rest.insert(press); continue }
                MainActor.assumeIsolated { controller?.press(name, extra: mods) }
            } else if flags.isDisjoint(with: [.command, .control, .alternate]) {
                rest.insert(press)
            } else if let ch = k.charactersIgnoringModifiers.first, let key = RemoteKeys.key(for: ch) {
                MainActor.assumeIsolated { controller?.press(key.name, extra: mods) }
            } else {
                rest.insert(press)
            }
        }
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }
}

/// The row over the system keyboard: Esc, Tab, the four modifiers, Spotlight,
/// Mission Control, App Windows, the arrows, and the function keys.
private struct RemoteKeyStrip: View {
    weak var controller: RemoteController?
    var done: () -> Void

    var body: some View {
        if let controller {
            Strip(controller: controller, mods: controller.modifiers, done: done)
        }
    }

    private struct Strip: View {
        let controller: RemoteController
        let mods: RemoteModifiers
        var done: () -> Void

        var body: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    key("esc") { controller.press("escape") }
                    key("tab") { controller.press("tab") }
                    mod("⌃", .ctrl, "Control")
                    mod("⌥", .opt, "Option")
                    mod("⌘", .cmd, "Command")
                    mod("⇧", .shift, "Shift")
                    key("Spotlight") { controller.shortcut("space", [.cmd]) }
                    key("Mission Control") { controller.shortcut("up", [.ctrl]) }
                    key("App Windows") { controller.shortcut("down", [.ctrl]) }
                    key("←") { controller.press("left") }
                    key("↑") { controller.press("up") }
                    key("↓") { controller.press("down") }
                    key("→") { controller.press("right") }
                    ForEach(1...12, id: \.self) { n in key("F\(n)") { controller.press(RemoteKeys.function(n)) } }
                    Button(action: done) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 15, weight: .medium)).frame(width: 40, height: 34)
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Hide keyboard")
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: .infinity)
        }

        private func key(_ label: String, _ action: @escaping () -> Void) -> some View {
            Button { action(); UIDevice.current.playInputClick() } label: {
                Text(label).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    .frame(minWidth: 34, minHeight: 34).padding(.horizontal, 6)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain).foregroundStyle(.primary)
        }

        private func mod(_ glyph: String, _ m: RemoteMod, _ name: String) -> some View {
            let on = mods.held.contains(m)
            return Button { mods.toggle(m); UIDevice.current.playInputClick() } label: {
                Text(glyph).font(.system(size: 17, weight: .medium))
                    .frame(minWidth: 34, minHeight: 34)
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .background(on ? Theme.accent : Color(uiColor: .secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(name)
            .accessibilityValue(on ? "down for the next key" : "")
        }
    }
}

// MARK: - A Mac keyboard and trackpad, for the bottom screen of a Duo

/// What a key on the Mac keyboard does.
private enum MacKeyAction {
    case char(String)
    case named(String)
    case mod(RemoteMod)
    case shortcut(String, [RemoteMod])
    case fn
}

private struct MacKeySpec: Identifiable {
    let id: String
    let label: String
    var symbol: String?
    let action: MacKeyAction
    var weight: CGFloat = 1
}

private func ch(_ c: String) -> MacKeySpec { MacKeySpec(id: "c" + c, label: c, action: .char(c)) }

/// The keyboard of a Mac, laid out as the photo's: a row of Mac shortcuts above
/// the letters, the modifiers at the bottom with the arrows, and under it all a trackpad.
struct MacKeyboard: View {
    let controller: RemoteController
    @State private var fn = false
    private var modifiers: RemoteModifiers { controller.modifiers }

    private var top: [MacKeySpec] {
        if fn {
            return (1...12).map { MacKeySpec(id: "f\($0)", label: "F\($0)", action: .named(RemoteKeys.function($0))) }
                + [MacKeySpec(id: "fn", label: "fn", action: .fn)]
        }
        return [
            MacKeySpec(id: "esc", label: "esc", action: .named("escape")),
            MacKeySpec(id: "spot", label: "Spotlight", symbol: "magnifyingglass", action: .shortcut("space", [.cmd]), weight: 2),
            MacKeySpec(id: "mc", label: "Mission Control", symbol: "rectangle.3.group", action: .shortcut("up", [.ctrl]), weight: 2.4),
            MacKeySpec(id: "aw", label: "App Windows", symbol: "rectangle.on.rectangle", action: .shortcut("down", [.ctrl]), weight: 2),
            MacKeySpec(id: "undo", label: "Undo", symbol: "arrow.uturn.backward", action: .shortcut("z", [.cmd]), weight: 1.6),
            MacKeySpec(id: "redo", label: "Redo", symbol: "arrow.uturn.forward", action: .shortcut("z", [.cmd, .shift]), weight: 1.6),
            MacKeySpec(id: "fn", label: "fn", action: .fn)
        ]
    }

    private var rows: [[MacKeySpec]] {
        let digits = "1234567890-=".map { ch(String($0)) }
        let q = "qwertyuiop[]\\".map { ch(String($0)) }
        let a = "asdfghjkl;'".map { ch(String($0)) }
        let z = "zxcvbnm,./".map { ch(String($0)) }
        return [
            top,
            digits + [MacKeySpec(id: "del", label: "delete", symbol: "delete.left", action: .named("delete"), weight: 1.6)],
            [MacKeySpec(id: "tab", label: "tab", symbol: "arrow.right.to.line", action: .named("tab"), weight: 1.5)] + q,
            a + [MacKeySpec(id: "ret", label: "return", symbol: "return", action: .named("return"), weight: 2)],
            [MacKeySpec(id: "lsh", label: "shift", symbol: "shift", action: .mod(.shift), weight: 2.2)] + z
                + [MacKeySpec(id: "rsh", label: "shift", symbol: "shift", action: .mod(.shift), weight: 2.2)],
            [
                MacKeySpec(id: "ctrl", label: "control", symbol: "control", action: .mod(.ctrl), weight: 1.3),
                MacKeySpec(id: "opt", label: "option", symbol: "option", action: .mod(.opt), weight: 1.3),
                MacKeySpec(id: "cmd", label: "command", symbol: "command", action: .mod(.cmd), weight: 1.6),
                MacKeySpec(id: "space", label: "space", action: .named("space"), weight: 5.5),
                MacKeySpec(id: "cmd2", label: "command", symbol: "command", action: .mod(.cmd), weight: 1.6),
                MacKeySpec(id: "left", label: "", symbol: "arrow.left", action: .named("left")),
                MacKeySpec(id: "up", label: "", symbol: "arrow.up", action: .named("up")),
                MacKeySpec(id: "down", label: "", symbol: "arrow.down", action: .named("down")),
                MacKeySpec(id: "right", label: "", symbol: "arrow.right", action: .named("right"))
            ]
        ]
    }

    var body: some View {
        VStack(spacing: 5) {
            VStack(spacing: 4) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    WeightedRow(spacing: 4) {
                        ForEach(row) { key in keyView(key).layoutValue(key: KeyWeight.self, value: key.weight) }
                    }
                }
            }
            .frame(maxHeight: .infinity)
            RemoteTrackpad(controller: controller)
                .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(height: 120)
        }
        .padding(.horizontal, 6).padding(.top, 6).padding(.bottom, 8)
    }

    private func keyView(_ k: MacKeySpec) -> some View {
        let isMod: Bool = { if case .mod = k.action { return true }; return false }()
        var on = false
        if case .mod(let m) = k.action { on = modifiers.held.contains(m) }
        if case .fn = k.action { on = fn }
        return Button { press(k) } label: {
            Group {
                if let s = k.symbol, k.label.count > 1 && k.id != "space" {
                    VStack(spacing: 1) {
                        Image(systemName: s).font(.system(size: 11))
                        if k.weight >= 2 { Text(k.label).font(.system(size: 8, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6) }
                    }
                } else if let s = k.symbol {
                    Image(systemName: s).font(.system(size: 13, weight: .medium))
                } else {
                    Text(label(for: k)).font(.system(size: 14, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                }
            }
            .foregroundStyle(on ? Color.white : Color(white: 0.92))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? Theme.accent : Color(white: isMod || k.label.count > 1 ? 0.2 : 0.27),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(k.label.isEmpty ? (k.symbol ?? "key") : k.label)
    }

    /// A letter shows as it will be typed: capital while Shift is down.
    private func label(for k: MacKeySpec) -> String {
        if case .char(let c) = k.action, modifiers.held.contains(.shift), c.first?.isLetter == true { return c.uppercased() }
        return k.label
    }

    private func press(_ k: MacKeySpec) {
        switch k.action {
        case .char(let c): controller.type(c)
        case .named(let n): controller.press(n)
        case .mod(let m): modifiers.toggle(m); Haptics.tap()
        case .shortcut(let n, let mods): controller.shortcut(n, mods)
        case .fn: fn.toggle(); Haptics.tap()
        }
    }
}

private struct KeyWeight: LayoutValueKey { static let defaultValue: CGFloat = 1 }

/// A row of keys whose widths are shares of the row, by weight: a space bar is
/// wider than a letter, and every row ends at the same edge.
private struct WeightedRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 300, height: proposal.height ?? 36)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let total = subviews.reduce(0) { $0 + $1[KeyWeight.self] }
        guard total > 0 else { return }
        let room = bounds.width - spacing * CGFloat(max(0, subviews.count - 1))
        var x = bounds.minX
        for v in subviews {
            let w = room * v[KeyWeight.self] / total
            v.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + spacing
        }
    }
}

import AppKit
import SwiftUI

/// Tomo's design system (DESIGN.md section 15): warm paper, tomato and leaf accents, one spacing, type and
/// radius scale, and custom controls so no window falls back to grey system widgets.
/// Every text colour clears WCAG 4.5:1 on its backgrounds in both themes (computed 23 Oct), except `ink3`
/// (3.5:1 light), which is for large text and decoration only.
enum T {
    // MARK: colour (light / dark, tuned per token, not inverted)
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { a in
            let h = a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(h >> 16 & 255) / 255, green: CGFloat(h >> 8 & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
        })
    }
    static let paper = dyn(0xFBF7F2, 0x1A1513)      // window background
    static let surface = dyn(0xFFFFFF, 0x241D1B)    // cards
    static let fill = dyn(0xF4EEE7, 0x2E2624)       // quiet fills: chips, inputs, rows
    static let line = dyn(0xEAE1D7, 0x3A302D)
    static let ink = dyn(0x2B1A17, 0xF6EEE8)
    static let ink2 = dyn(0x6B5B54, 0xC2B5AE)
    static let ink3 = dyn(0x8E827B, 0x978A84)
    static let tomato = dyn(0xC8372B, 0xFF7B6B)
    static let tomatoBright = dyn(0xE8392B, 0xFF7B6B)
    static let blush = dyn(0xFFE9E3, 0x3A2420)
    static let leaf = dyn(0x2F7A33, 0x7BC86A)
    static let leafSoft = dyn(0xE6F2E2, 0x22331F)
    static let onTomato = dyn(0xFFFFFF, 0x1A1513)

    // MARK: spacing (8-point grid; 4 only for icon-to-text pairs)
    static let s1: CGFloat = 4, s2: CGFloat = 8, s3: CGFloat = 12, s4: CGFloat = 16, s5: CGFloat = 24, s6: CGFloat = 32, s7: CGFloat = 48

    // MARK: radius
    static let rControl: CGFloat = 8, rRow: CGFloat = 10, rCard: CGFloat = 16, rPanel: CGFloat = 20

    // MARK: type (rounded throughout; a 1.2 step scale)
    static func display() -> Font { .system(size: 26, weight: .bold, design: .rounded) }
    static func title() -> Font { .system(size: 20, weight: .bold, design: .rounded) }
    static func headline() -> Font { .system(size: 15, weight: .semibold, design: .rounded) }
    static func body() -> Font { .system(size: 13.5, weight: .regular, design: .rounded) }
    static func callout() -> Font { .system(size: 12.5, weight: .medium, design: .rounded) }
    static func caption() -> Font { .system(size: 11.5, weight: .medium, design: .rounded) }
    static func overline() -> Font { .system(size: 11, weight: .bold, design: .rounded) }
}

// MARK: components

/// A card: white (or warm dark) surface, 16 pt corners, a hairline and a soft shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = T.s4
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: T.rCard, style: .continuous).fill(T.surface))
            .overlay(RoundedRectangle(cornerRadius: T.rCard, style: .continuous).stroke(T.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}

/// Section label above a card's content.
struct Overline: View {
    var text: String
    var body: some View { Text(text.uppercased()).font(T.overline()).tracking(0.6).foregroundStyle(T.ink2) }
}

struct PButton: View {
    enum Kind { case primary, secondary, ghost }
    var title: String
    var symbol: String? = nil
    var kind: Kind = .secondary
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            HStack(spacing: T.s1 + 2) {
                if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .bold)) }
                Text(title).font(T.callout()).fontWeight(.semibold)
            }
            .foregroundStyle(kind == .primary ? T.onTomato : kind == .secondary ? T.ink : T.tomato)
            .padding(.horizontal, T.s3 + 2).padding(.vertical, T.s2)
            .background(RoundedRectangle(cornerRadius: T.rControl, style: .continuous)
                .fill(kind == .primary ? T.tomato.opacity(hover ? 0.88 : 1) : kind == .secondary ? T.fill.opacity(hover ? 0.7 : 1) : (hover ? T.blush : .clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { hover = $0 }
    }
}

/// An on/off switch drawn in Tomo's colours: a leaf-green track when on.
struct PToggle: View {
    var label: String
    var detail: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        Button { withAnimation(.snappy(duration: 0.18)) { isOn.toggle() } } label: {
            HStack(alignment: .center, spacing: T.s3) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(T.body()).foregroundStyle(T.ink)
                    if let detail { Text(detail).font(T.caption()).foregroundStyle(T.ink2) }
                }
                Spacer(minLength: T.s2)
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule().fill(isOn ? T.leaf : T.line).frame(width: 36, height: 21)
                    Circle().fill(.white).frame(width: 17, height: 17).shadow(color: .black.opacity(0.18), radius: 1.5, y: 1).padding(2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityValue(isOn ? "on" : "off")
    }
}

/// A rounded checkbox for lists of apps: tomato when ticked.
struct PCheck: View {
    var on: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(on ? T.tomato : T.surface)
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(on ? T.tomato : T.ink3.opacity(0.6), lineWidth: 1.5))
            .overlay { if on { Image(systemName: "checkmark").font(.system(size: 9.5, weight: .heavy)).foregroundStyle(T.onTomato) } }
            .frame(width: 18, height: 18)
    }
}

/// A pill choice; a row of them replaces every pop-up menu.
struct PChip: View {
    var title: String
    var on: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(T.callout()).fontWeight(on ? .semibold : .medium)
                .foregroundStyle(on ? T.onTomato : T.ink)
                .padding(.horizontal, T.s3).padding(.vertical, 6)
                .background(Capsule().fill(on ? T.tomato : T.fill))
                .contentShape(Capsule())
        }.buttonStyle(.plain)
    }
}

/// The app's real icon (from Launch Services), or a symbol in a soft circle for websites and Other.
struct AppIcon: View {
    var bundleID: String?
    var symbol: String = "app"
    var size: CGFloat = 24
    var body: some View {
        if let id = bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(T.tomato)
                .frame(width: size, height: size).background(Circle().fill(T.blush))
        }
    }
}

/// A search or text field in Tomo's style.
struct PField: View {
    var placeholder: String
    @Binding var text: String
    var symbol: String? = nil
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: T.s2) {
            if let symbol { Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(T.ink3) }
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(T.body()).foregroundStyle(T.ink).onSubmit(onSubmit)
        }
        .padding(.horizontal, T.s3).padding(.vertical, T.s2)
        .background(RoundedRectangle(cornerRadius: T.rControl, style: .continuous).fill(T.fill))
    }
}

/// Window chrome: the content runs under a transparent title bar, so there is no separate (and clashing)
/// system bar; the traffic lights stay where macOS puts them, and the window drags by its background.
enum Chrome {
    /// App-wide appearance setting: system, light or dark (never touches the Mac's own setting).
    static func applyAppearance() {
        switch UserDefaults.standard.string(forKey: "appearance") ?? "system" {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    static func style(_ w: NSWindow) {
        w.styleMask.insert(.fullSizeContentView)
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isMovableByWindowBackground = true
        w.backgroundColor = NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(srgbRed: 0x1A / 255, green: 0x15 / 255, blue: 0x13 / 255, alpha: 1)
                                                               : NSColor(srgbRed: 0xFB / 255, green: 0xF7 / 255, blue: 0xF2 / 255, alpha: 1)
        }
    }
}

/// The top of every window: room for the traffic lights, then the title in the content, like Things or Craft.
struct WindowHeader<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: T.s3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(T.display()).foregroundStyle(T.ink)
                if let subtitle { Text(subtitle).font(T.callout()).foregroundStyle(T.ink2) }
            }
            Spacer(minLength: T.s3)
            trailing
        }
        .padding(.top, 36)   // clears the traffic lights in a transparent title bar
    }
}

import SwiftUI
import PomodoroCore

/// Shortcuts & help (24 Oct: "there should be info about exit shortcuts and everything"). Every entry here is a
/// control that exists in the app; the way out comes first.
struct HelpView: View {
    @ObservedObject var m: Model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: T.s4) {
                WindowHeader(title: "Shortcuts & help", subtitle: "Everything Tomo responds to") { EmptyView() }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "If you need out")
                        HStack(alignment: .center, spacing: T.s3) {
                            Keys(["⌃", "⌥", "⌘", "E"], big: true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Emergency exit").font(T.headline()).foregroundStyle(T.ink)
                                Text("Stops the session and brings every hidden app back, from anywhere, at any time.")
                                    .font(T.callout()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        row(["⌘", "Q"], "Quit Pomodoro", "Asks first mid-session; the session comes back paused next time")
                        Text("Claude, Terminal, Finder and System Settings are never hidden, and nothing is ever quit.")
                            .font(T.caption()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "Tomo")
                        gesture("hand.tap", "Tap", "Pick what to focus on, or start the next session when ripe")
                        gesture("hand.point.up.left", "Hold 1.5 s", "Pause, or carry on where you left off")
                        gesture("arrow.up.and.down.and.arrow.left.and.right", "Drag", "Move Tomo anywhere")
                        gesture("leaf", "Tap the leaves", "Park an idea for later")
                        gesture("face.smiling", "Tap when cross", "\"I'm back\": Tomo calms down at once")
                        row(["?"], "This window", "With Tomo selected")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s3) {
                        Overline(text: "Keyboard")
                        row(["⌃", "⌥", "⌘", "I"], "Park an idea", "From any app")
                        row(["⌘", ","], "Settings", nil)
                        row(["⌘", "I"], "Insights", "From the menu bar menu")
                        row(["⌘", "T"], "Show Tomo", "If you hid it")
                        row(["↩"], "Start or save", "In the launcher and when making a profile")
                        row(["esc"], "Close or cancel", nil)
                        row(["←", "→"], "Twist the timer", "5 minutes a step, 5 to 60")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s2) {
                        Overline(text: "During a session")
                        bullet("Tracking starts by itself after about 10 seconds of real use of a profile's app, at that profile's last length. Not for 10 minutes after an emergency exit.")
                        bullet("Only engaged time counts: typing, clicking or scrolling in the last 20 seconds, or a page or item your app reported in the last 2 minutes.")
                        bullet("Apps outside your focus profile are hidden (Cmd-H), never closed.")
                        bullet("Open another study app and Tomo asks: Switch focus, or Stay.")
                        bullet("Off task: a nudge at 10 s, cross at 22 s, simmering at 44 s, boiling at 66 s, a siren at 116 s. Tap Tomo when you're back.")
                        bullet("No keyboard or mouse for a minute and no progress for three is \"not working\"; reading is fine.")
                        bullet("An app that keeps coming back after three hides is let be for that session.")
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: T.s2) {
                        Overline(text: "Files")
                        file("Ideas inbox", m.lot.file.path)
                        file("Your data", m.store.root.path)
                    }
                }
            }
            .padding(.horizontal, T.s5).padding(.bottom, T.s5)
        }
        .frame(minWidth: 460, minHeight: 520)
        .background(T.paper)
    }

    func row(_ keys: [String], _ title: String, _ detail: String?) -> some View {
        HStack(alignment: .center, spacing: T.s3) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(T.body()).foregroundStyle(T.ink)
                if let detail { Text(detail).font(T.caption()).foregroundStyle(T.ink2) }
            }
            Spacer(minLength: T.s2)
            Keys(keys)
        }
    }

    func gesture(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .center, spacing: T.s3) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(T.tomato)
                .frame(width: 30, height: 30).background(Circle().fill(T.blush))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(T.body()).foregroundStyle(T.ink)
                Text(detail).font(T.caption()).foregroundStyle(T.ink2).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    func bullet(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: T.s2) {
            Circle().fill(T.tomato).frame(width: 5, height: 5).offset(y: -2)
            Text(text).font(T.callout()).foregroundStyle(T.ink).fixedSize(horizontal: false, vertical: true)
        }
    }

    func file(_ title: String, _ path: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(T.body()).foregroundStyle(T.ink)
            Spacer(minLength: T.s3)
            Button(path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
                NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
            }
            .buttonStyle(.plain).font(T.callout()).foregroundStyle(T.tomato).lineLimit(1).truncationMode(.middle)
        }
    }
}

/// Keycaps drawn in Tomo's style.
struct Keys: View {
    var keys: [String]
    var big = false
    init(_ keys: [String], big: Bool = false) { self.keys = keys; self.big = big }
    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { k in
                Text(k).font(.system(size: big ? 15 : 12, weight: .semibold, design: .rounded)).foregroundStyle(T.ink)
                    .frame(minWidth: big ? 30 : 24, minHeight: big ? 30 : 24).padding(.horizontal, k.count > 1 ? 6 : 0)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(T.surface))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(T.line, lineWidth: 1))
                    .shadow(color: .black.opacity(0.08), radius: 0, y: 1.5)
            }
        }
        .accessibilityElement().accessibilityLabel(keys.joined(separator: " "))
    }
}

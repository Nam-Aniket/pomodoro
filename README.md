# Pomodoro

**Tomo, a cute tomato that sits on your Mac, keeps you on one task, and gets eaten bite by bite as you actually work.**

![Tomo eaten by active minutes: 0, 25, 50, 75 and 100%](docs/media/eaten-strip.png)

- **Counts only real work.** The clock fills with *active* minutes: your task's app in front, recent typing or progress, the page on topic. An open window that you're not using doesn't count.
- **Keeps distractions out, gently.** Other apps are hidden (never quit) while a session runs. Drift and Tomo goes *hmmph*, then simmers, boils, and finally sounds a siren. Get back on track or tap Tomo and it calms down at once.
- **Breaks that restore you.** Each break starts with guided breathing (cyclic sighing, or box breathing), then real rest while the next tomato regrows and ripens.
- **A daily harvest.** Five tomatoes = 5 × 45 active minutes. Any session length works; the crate fills by minutes. Finishing the day gets a little dance.
- **Private by design.** Everything stays on your Mac: no account, no network, no API key. Sessions live in a local SQLite file you can export as CSV.

| ![entrance](docs/media/entrance.gif) | ![5 of 5](docs/media/celebrate.gif) | ![siren](docs/media/siren.gif) |
|---|---|---|
| The ripe tomato jumps off the vine | Full harvest | Ignored the boil? Siren. |

## Install

Needs macOS 26 and the Xcode command-line tools.

```bash
git clone https://github.com/Nam-Aniket/pomodoro.git
cd pomodoro
tools/make_app.sh
```

This builds, runs the checks, and installs `Pomodoro.app` into `/Applications`. The build is ad-hoc signed, not notarized, so the first launch may need right-click → Open.

## Use

- **Tap Tomo** to pick what you're working on (an app, or *Other* with a typed task) and a length (25, 30, 45, 60 min).
- **Hold Tomo 1.5 s** to pause or resume. Quit (⌘Q) remembers your place.
- **Click the leaves** (⌃⌥⌘I) to park an idea without leaving your task. It goes to `~/Documents/Pomodoro/ideas-inbox.md`.
- **Emergency exit:** ⌃⌥⌘E, the menu, or Quit. Hidden apps come back.
- **Insights** (⌘I): active time, tomatoes, focus quality, per task and app; today, week, month.

## Privacy and permissions

| What Pomodoro reads | Why | Permission |
|---|---|---|
| Which app is in front | to know if you're on task, and to hide distractions | none |
| Seconds since your last key or mouse event (never the keys themselves) | to tell working from idle | none |
| Whether a mic is in use, and whether the Mac is muted | to stay silent during calls and recordings | none |
| The address and title of Chrome's front tab, during sessions that allow Chrome | to check the page fits your task (judged on-device by Apple's sentence model) | Automation, asked once by macOS |

Nothing is sent anywhere. Apps that are never hidden: Claude, Terminal, Finder, System Settings, FaceTime, Activity Monitor and every system process.

## Plug in your own app

Post one distributed notification when a task starts, ends, or makes progress:

```swift
DistributedNotificationCenter.default().postNotificationName(.init("com.aniket.focus"), object: nil,
    userInfo: ["app": "YourApp", "phase": "start", "task": "Chapter 3", "at": ISO8601DateFormatter().string(from: .now)],
    deliverImmediately: true)
```

`phase` is `start`, `end`, or `activity` (real progress, about once per 30 s at most). The current version ships presets for three example apps; general app and website profiles are next (see DESIGN.md section 12).

## Build and check

- `swift run pomodoro-check`: logic checks (schedule, active clock, ladder, policy, store, rules).
- `Pomodoro --sheet light out.png`: every state drawn side by side. `--eaten`, `--frames <moment> <dir>`, `--reels <dir>`: renders and sound demos.

Design notes and the research behind them: [DESIGN.md](DESIGN.md). Licence: [MIT](LICENSE).

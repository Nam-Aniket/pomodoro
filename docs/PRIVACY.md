# Privacy

Pomodoro keeps everything on your Mac. There is no account, no analytics and no telemetry.

## The one network request: the update check

- **What:** one HTTPS `GET` to `https://api.github.com/repos/Nam-Aniket/pomodoro/releases/latest`, which returns the latest release's version, notes and download link.
- **What it carries:** nothing about you. No ID, no usage data, no session data. GitHub sees what any web request shows: your IP address and that a request was made (see GitHub's own privacy statement).
- **When:** at launch, at most once a day, and when you choose **Check for updates** (Help menu, the menu bar menu, or Settings → Updates).
- **What happens next:** if a newer version exists, a small seed packet appears beside Tomo (never during a focus session). Clicking it shows the notes; **Get the new version** downloads the disk image to your Downloads folder and opens it. Pomodoro never replaces itself.
- **Turn it off:** Settings → Updates → Check for updates.

## What stays on your Mac

| Data | Where |
|---|---|
| Sessions and events | `~/Library/Application Support/Pomodoro/sessions.sqlite` |
| Focus profiles | `~/Library/Application Support/Pomodoro/profiles.json` |
| Current state | `~/Library/Application Support/Pomodoro/state.json` |
| Parked ideas | `~/Documents/Pomodoro/ideas-inbox.md` (or the path you set) |

The page topic check runs on-device with Apple's sentence model. Keys you type are never read; only the seconds since the last key or mouse event.

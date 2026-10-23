# Pomodoro - design

A floating tomato that keeps the user on the one task you opened, and gets eaten as the focus session runs.

## 1. What the research says (and what it changes)

| Finding | Source | Design consequence |
|---|---|---|
| 25 minutes is a convention, not a proven optimum; evidence supports alternating focused blocks with deliberate breaks | [Ogut 2025, BMC Medical Education 25:1440](https://link.springer.com/article/10.1186/s12909-025-08001-0) (scoping review: time-structured breaks improved focus and reduced fatigue vs self-paced), [Wikipedia summary](https://en.wikipedia.org/wiki/Pomodoro_Technique) | 45/10 is a fine choice; keep it fixed, as he asked |
| Micro-breaks boost vigor (d = .36) and cut fatigue (d = .35); performance gains grow with break length; very depleting work may need more than 10 minutes | [Albulescu et al. 2022, PLOS ONE](https://doaj.org/article/c6f37b6ba159469296b2cb968b65505f) | 10-minute breaks are real recovery, not dead time; the tomato does not shorten them |
| Phone breaks were no better than no break (22% fewer problems solved after); computer breaks did not deplete the same way | [Rutgers, Kang and Kurtzberg](https://www.rutgers.edu/news/need-mental-break-avoid-your-cell-phone-rutgers-researchers-say) | The break animation suggests standing up and looking away, not scrolling |
| If-then plans ("when X, I will Y") have a medium-to-large effect on goal attainment, d = 0.65 across 94 tests | Gollwitzer and Sheeran 2006, Advances in Experimental Social Psychology (figures via [secondary summary](https://goalsandprogress.com/implementation-intentions-research/), original chapter not read) | Session start shows the task as a plan: "HackerSolve, Lesson 4. When I want to switch, I park the idea." |
| A pause plus an option to back out made people abandon 36% of distracting app opens; the dismiss option was the strongest ingredient | [Grüning, Riedel, Lorenz-Spreen 2023, PNAS](https://pmc.ncbi.nlm.nih.gov/articles/PMC9974409) | Blocking is friction with a visible way out, not a jail. Tools people feel trapped by get uninstalled |
| 367 self-control tools reviewed; design mechanisms that support self-control are still poorly understood | [Lyngs et al. 2019, CHI](https://arxiv.org/abs/1902.00157) | Keep the mechanism small and measurable; log every nudge so we can see if it works |

Unverified: the "32 studies / 5,270 participants" figures some blogs attach to the Ogut review. Not used.

## 2. The character: Tomo

Original design. Only the idea of a talking, reacting mascot is borrowed from Miss Minutes; no shape, colour or styling is. Revised 23 Oct 2026 after Requirement: "Normal face looks creepy - Should be cute" and, of the headset, "whats this".

**Face rules (baby schema).** People read "cute" from a fixed set of cues: big round eyes set low on a big round head, a small mouth, soft shapes and catchlights in the eyes; narrow eyes and lowered brows read as suspicion (Lorenz's Kindchenschema; Glocker et al. confirmed experimentally that more of these cues means rated cuter: [PMC3105163](https://pmc.ncbi.nlm.nih.gov/articles/PMC3105163)).

| Rule | Value |
|---|---|
| Eyes | Round, 0.26 x 0.31 of the body radius, set **below** the middle (+0.06 r) and apart (±0.33 r), dark brown fading lighter at the bottom |
| Sparkle | Two catchlights in every open eye: a big one top-left, a small one bottom-right |
| Brows | **None at rest.** Soft raised arcs only in nudge; lowered (inner end down) only in simmer and boil |
| Mouth | Small soft "u" smile, close under the eyes |
| Cheeks | Pink ovals just under and outside the eyes |
| Silhouette | A real tomato, not a ball: flatter than tall (1.12 x 0.9 of the radius), soft ribbed shoulders, a dip where the stem sits, a slightly flat bottom |
| Realism | Photoreal light with a cartoon face ("photorealistic but with this cute animated feel"): no drawn lines; lobes are soft shading; the skin glows warmer at its edges (translucent), has a broad sheen plus one sharp wet highlight, a faint speckle, orange shoulders, a darker underside |
| Eating | The way people eat one: first bite upper right, each next bite beside the last, down the right side then back up deeper; bites overlap so the edge is soft tooth marks; the face is never reached |
| Inside the bite | As a ripe tomato ([UC Davis anatomy](https://labs.plb.ucdavis.edu/rost/Tomato/Reproductive/anat.html)): thin deep-red wall, glistening red flesh, glossy **red** gel pockets with pale teardrop seeds (yellow-green gel reads as unripe), wet glints on the edge, and a drop of juice running down every 6 s |
| Accessories | **None.** The 0.1.0 glasses, headset and star were removed: at 12 px they did not read, and the glasses hid the eyes. The app shows in the bubble and hover line instead |
| Stem | The cowlick that carries mood: sways, droops asleep, swings on a full harvest |

## 3. States and motion

Every state starts from the cute baseline and turns stern only when it means to.

| State | Face and body | Motion |
|---|---|---|
| Idle | Round eyes **follow the cursor**, soft smile | Breathing bob (4 s), irregular blinks (3 to 6 s), leaf sway, a stretch every 25 to 50 s |
| Focus | Same eyes looking **down at the work**, smaller smile; a glance at the cursor every 25 to 45 s | A stretch only every 4 to 7 minutes, so it never pulls attention |
| Eaten | Each 5 minutes a side nibble deepens (right, then left, alternating), flesh and seeds showing, with a quick chomp | |
| Nudge | Eyes to the side, soft raised brows, little "o" | Wobble |
| Hmmph | Flat side-eye lids, puffed cheeks, pout, slightly redder | Puffed up |
| Simmer | Lowered brows, gritted wavy mouth, redder, two steam wisps | Faint tremble |
| Siren | Boil face plus a red and blue beacon on the stem alternating every 0.35 s, light beams sweeping, bouncing; Tomo's own voice doing "wee-woo" (sound guards apply). Stops the instant he is back on track, on a tap ("I'm back") or the emergency exit | Bounce and tilt |
| Boil | "> <" squeezed eyes, open shouting mouth, deep red, bubbles on the skin, puffs of steam, the leaf "lid" rattling | Shaking |
| Splash (end of focus) | Last bite, squish, juice burst with droplets, "+1" drops into the crate | 1.9 s |
| Break | The pot springs up out of the splash (0.55 s overshoot); a seedling grows into a sleeping baby tomato that ripens green to red | Sway |
| Entrance (break over) | The ripe tomato swells and wiggles, pops off the vine, hops and spins along an arc, lands with a squash, opens its eyes and smiles | 1.45 s |
| Ready | Happy "^ ^", gentle bounce, pulse ring | |
| Paused | Asleep, "z z", muted colours, drooping stem | |
| 5 of 5 | Three hops (left, right, spin), confetti burst, the crate's tomatoes wave in turn, bubble lists the day's 5 tasks and counts full-harvest days (a count, **never a streak**) | 4.2 s, then "day done" with sparkles and a glowing crate |

**Motion rules** (Thomas and Johnston's 12 principles, [summary](https://en.wikipedia.org/wiki/Twelve_basic_principles_of_animation)): squash and stretch keep volume (wider when shorter); every hop has anticipation (squash), stretch, landing squash and an overshoot settle (ease-out-back); eyes ease towards their target instead of snapping. No state cuts: start and resume hop, nudge wobbles, parking puffs, splash leads into the pot growing in, the ripe tomato performs its entrance, and 5 of 5 dances. With macOS Reduce Motion on, the entrance crossfades and reactions are skipped.

**Performance:** 15 frames per second at rest, 30 during reactions and performed moments, **zero while Tomo is hidden or the screen is locked** (measured 0.3% CPU hidden). Measured visible: about 4% of one core at rest after start-up settles (23 Oct 2026). 60 frames per second was asked for; at this drawing cost it would roughly quadruple CPU. the user kept 15/30 (D10).

## 4. Interaction

- **Window:** borderless floating panel, always on top, on every Space, draggable, position remembered. A small × on hover hides Tomo (Pomodoro keeps running).
- **A normal Mac app too:** Dock icon (switchable in Settings), app menu with Settings (⌘,), Show Tomo (⌘T) and Quit (⌘Q). Clicking the Dock icon brings Tomo back.
- **Quit always works.** Mid-session it asks once ("Tomo will remember where you were"), Quit is the default button; quitting saves the place, brings hidden apps back and stops every watcher. Never blocked, because quitting is also a way out.
- **Menu bar:** tomato plus minutes left. Menu: pause or resume, start a session, Search, Park an idea, Show or hide Tomo, Settings, Emergency exit, Quit.
- **Hover:** minutes left and task. **Hold 1.5 s:** pause or resume.
- **Ideas inbox:** click the leaves or press ⌃⌥⌘I, type, Enter. Every idea goes to one file, `~/Documents/Pomodoro/ideas-inbox.md` (the `ideasInboxPath` setting), one line each: time · app · task: idea.
- **Sessions start** when a study app launches, when you switch to one while Tomo is idle, or when Pomodoro opens with one in front.

## 5. Keeping other apps out

**Mechanism:** Pomodoro listens for `NSWorkspace.didActivateApplicationNotification`. When an app that is not allowed comes to the front during focus, Pomodoro calls `NSRunningApplication.hide()` on it (the same thing Cmd-H does) and shows a nudge. Nothing is ever quit or killed, so unsaved work is never lost.

- **Verified on this Mac (23 Oct 2026): no permission needed.** The bundled app, launched with `open` and logging `AXIsProcessTrusted() = false`, hid Calculator at session start and on every switch.
- Hiding inside the activation notification is undone by macOS, and `hide()` returns false even when it works. So Pomodoro hands focus back to the study app, hides 0.15 s later, checks at 0.7 s and retries once.
- Third-party focus apps use the same call ([BSN4/focus](https://github.com/BSN4/focus)); one ([Fader](https://apps.apple.com/us/app/fader-hide-background-apps/id6764862445?mt=12)) states it needs no permissions for hiding.
- Gap: minimising a window posts no activation notification ([Apple forum](https://developer.apple.com/forums/thread/747352)). Irrelevant here: we only care what comes to the front.

**Always allowed, never hidden (safety list):** Pomodoro itself, the session's own app, Claude (com.anthropic.claudefordesktop), Terminal, Finder, System Settings, FaceTime (incoming calls), and every non-regular process (login window, lock screen, password dialogs, Notification Centre, menu bar agents).

**Per-app allowlist during focus:**

| Session app | Also allowed |
|---|---|
| SpeakFit | nothing else |
| HackerSolve | Google search (in Tomo's search window) |
| Northstar Viewer | Chrome (full, for applying on job sites), Google search window, Claude, Preview |

Decided 23 Oct 2026: the same rules hold through the 10-minute break; at session start every app not allowed is hidden at once; after a break the next session waits for a tap on the ripe tomato.

## 6. "Google only"

A Google results page links to every site, so "allow Chrome" means "allow everything". Options:

| Option | How | Pros | Cons |
|---|---|---|---|
| A. Tomo's search window | A small in-app browser (`WKWebView`) that loads only `google.com/search`; every other navigation is cancelled in `decidePolicyFor` ([pattern](https://www.hackingwithswift.com/example-code/wkwebview/how-to-control-the-sites-a-wkwebview-can-visit-using-wknavigationdelegate)) | No install, no permission, exact control, cannot leak | Not his Chrome profile (no saved logins; fine for search) |
| B. Chrome extension allowlist | Unpacked extension blocks all but Google while a session runs | His real Chrome | Needs Chrome developer mode on, plus a bridge between the app and the extension; more moving parts |
| C. Chrome managed policy | `URLBlocklist *` plus `URLAllowlist` ([Google](https://support.google.com/chrome/a/answer/7532419)) | Airtight | Needs a configuration profile and Chrome restart: a system-level change. Excluded by his rules |

Chosen: **A**, results page only (decided 23 Oct 2026). Clicking a result is cancelled and Tomo nudges. Allowed: `www.google.com` and `google.com.au` paths `/`, `/search`, plus `consent.google.com` for the cookie screen.

## 6b. Sound

Revised 23 Oct 2026 after "Sounds are not that natural" and "a light sound - to show that something alive is near us".

**Sources:** all synthesized in code from physical models, so every sound is original and free to publish: drops are the bubble a landing drop traps, ringing with a rising pitch (Minnaert resonance); the squelch is noise through a resonance sweeping down; the little voice is a soft buzz shaped by mouth resonances (formants), nasal for "mm", open for "hup"; the ripe chime is a wooden bar (marimba-like partials); leaves are airy noise with crackle. Every play draws new randomness (about ±4% pitch, droplet timing and count), soft attacks and releases (3 ms in, 40 ms out, never a click), warmed by a 5 kHz low-pass. Measured: the old splash centred at 6.8 kHz (a hiss), the new one at 1.8 kHz; takes correlate 0.3 or less, so no two plays match.

| Moment | Sound |
|---|---|
| Session start | a tiny "hup" and a squish |
| Nudge | rising "hm?" |
| Hmmph | falling "hmph" with a breath puff |
| Boil | bubbling and a low simmer |
| End of focus | plop, squelch, droplets |
| Break over | a pop, a leaf rustle, two wooden notes |
| 5 of 5 | four rising wooden notes, three little "he"s, pops |
| Idea parked | rustle and squish |
| Presence | a contented "mm", a soft pop, a leaf rustle: every 45 to 120 s outside focus; in focus only a pop or rustle every 5 to 10 min (D9) |

**Why no presence sounds during focus:** background sound that changes over time, especially speech-like sound, disrupts memory and reading work even when you try to ignore it (changing-state effect, [Jones and Macken line](https://pmc.ncbi.nlm.nih.gov/articles/PMC9569014); semantic sound and reading, [review](https://0-www-mdpi-com.brum.beds.ac.uk/2039-4349/11/2/21)). the user chose rare non-voice sounds in focus (D9).

**Hard guards** (no permission needed, they read device state, never audio): silent for the whole of a SpeakFit session (from the focus contract), whenever any app records from the mic (calls, meetings, dictation; built-in and wired mics only, Bluetooth mics do not report it, [Apple forum](https://developer.apple.com/forums/thread/741026)), and when the Mac is muted. Do Not Disturb has no public API, so it is not detected. Settings: volume (default 35%) and mute.

Demo: `renders/audio/AB-demo.wav` (old then new, then the rest).

## 7. Integration with the three apps (contract agreed 23 Oct 2026)

Two layers, so app launch needs no change in any app:

1. **App open and quit:** Pomodoro watches `NSWorkspace.didLaunchApplicationNotification` and `didTerminateApplicationNotification` for `com.aniketnamjoshi.hackersolve` (and copies starting `com.aniketnamjoshi.hackersolve.`), `com.aniketnamjoshi.speakfit`, `com.aniket.northstar.viewer`. Launch starts a session tagged with the app name.
2. **Task detail:** each app posts one shared distributed notification, `com.aniket.focus`, with all-string `userInfo`:
   - required: `app` (`HackerSolve` | `SpeakFit` | `NorthstarViewer`), `phase` (`start` | `end`), `task` (title Tomo shows), `at` (ISO 8601)
   - optional extras pass through (SpeakFit: `kind`, `day`, `area`, `minutes`); unknown keys ignored.

```swift
DistributedNotificationCenter.default().postNotificationName(.init("com.aniket.focus"), object: nil,
    userInfo: ["app": "SpeakFit", "phase": "start", "task": title, "at": ISO8601DateFormatter().string(from: .now)],
    deliverImmediately: true)
```

- Distributed notifications reach only running apps and never launch one, so Pomodoro offers an **Open at login** toggle that the user switches on himself (a normal per-app login item; Pomodoro never flips it).
- None of the three apps is sandboxed (checked with `codesign -d --entitlements`), so `userInfo` arrives intact.
- **v2 (23 Oct 2026):** adds phase `activity`, posted on real work (HackerSolve: slide advance, answer, diagram step; SpeakFit: recording start, stop, review; Viewer: edit, tailor, save), at most about once every 30 s per app. Optional `taskId` passes through. v1 posters keep working.
- Test copies listen on `com.aniket.focus.test` (`POMODORO_EVENT_NAME`): a test once retitled the user's live session.
- Rejected: a `pomodoro://` URL in every app (second dependency per app); per-app notification names, as first drafted by the Viewer and SpeakFit chats (one observer per app, and every new app would need a Pomodoro change).

## 8. Data

- `~/Library/Application Support/Pomodoro/state.json`: current phase, app, task, seconds done, saved every 15 s and on every change.
- `~/Library/Application Support/Pomodoro/sessions.jsonl`: one line per finished session and per nudge (app, task, start, end, blocked app). This is the evidence for whether it works.
- Ideas inbox: `~/Documents/Pomodoro/ideas-inbox.md` (the `ideasInboxPath` setting), one line per idea with time, app and task, newest at the bottom.
- Full-harvest days: `full-harvests.json`, a list of dates. A count, never a streak.
- A crash or quit mid-session counts as paused at the last save. A new day starts at 4:00 local time.

## 9. Safety

- **Emergency exit, three ways, all without permissions:** menu bar item, the shortcut Control-Option-Command-E (Carbon hotkey, needs no Accessibility per [go-macos/hotkey](https://pkg.go.dev/github.com/go-macos/hotkey)), or quitting Pomodoro. Exit stops all hiding at once and saves state.
- **Fails open:** blocking only exists while Pomodoro runs. If it crashes, nothing stays blocked; hidden apps reappear from the Dock.
- **Never:** quit, force-kill, admin rights, kernel or network extensions, `/etc/hosts`, configuration profiles, system settings.

## 10. Chrome topic watcher (designed, not built; decisions pending)

Requirement: "if im on chrome then can it actually check what am i doing? ... has to be very low lag - and should get angry at me like boiling". Applies in HackerSolve and Northstar sessions (Chrome is fully allowed in Northstar, so the watcher judges the topic, not the site).

| Tier | What | Speed | Privacy | Needs |
|---|---|---|---|---|
| 1. Rules | Read the active tab's address and title through Chrome's AppleScript, then instant lists: always on topic (google.com/search, docs sites, job boards, ATS), always off (youtube.com, instagram.com, news, shopping) | milliseconds (not yet measured: reading Chrome needs the permission first) | stays on the Mac | **Automation permission for Chrome**, which the user grants himself when macOS asks |
| 2. On-device meaning check | Apple's built-in sentence model compares the page title or search words with the session task | **~10 ms measured**, model loads in 86 ms | stays on the Mac | nothing |
| 3. AI check, unclear pages only | Title, address and task (text only) sent to a model | about a second or more, network | text leaves the Mac | an API key; off by default |
| 4. Screenshot + image model | Last resort | slowest | an image of the screen leaves the Mac | Screen Recording permission; **off, not built unless the user asks** |

Measured tier 2 (23 Oct 2026, distance, lower is closer, task "Lesson 4: Spark partitioning"): Google search for it 0.82, Medium article 0.84, Instagram 0.99, YouTube cats 1.13, cricket score 1.26. Miss: "How to write a resume summary" scored 1.06 against the CV-tailoring task, so tier 2 alone would nag on-topic pages; the gap between 0.85 and 1.0 goes to tier 3 or to a one-tap "this is on topic" that teaches tier 1.

**Anger stages (D12 strict, D13 siren):** off-topic 10 s grace → hmmph at 30 s → simmer at 1 min → boil at 90 s → **siren at 2.5 min** (60 s of boil ignored). Not working: hmmph at 3 min → boil at 6 → siren at 9. Back on topic: calms at once with a happy hop. A one-tap "on topic" button on the bubble calms it and adds the site to the session's on-topic list. Jev (the user's private TypeSafe classifier, `api.typesafe.ai`, 15 s timeout in jev_classify.py) can only be an optional tier-3 plugin.

## 11. Not-working check (designed, not built; decisions pending)

Requirement: "tomo should also notice if im not actually working or recording or doing the task at hand. and then hmmmph and get angry".

Signals, cheapest and most reliable first: (1) app progress from contract v2 `activity`; (2) the focused app (already watched); (3) seconds since the last keyboard or mouse input (`CGEventSourceSecondsSinceLastEventType`, which reads a timestamp, not keystrokes; permission to be confirmed in the build). Progress beats raw input because reading a lesson produces no input for minutes.

Proposed thresholds (to confirm): HackerSolve no progress for 8 min and no input for 4 → hmmph; SpeakFit no recording started 5 min into a session → hmmph; Viewer no edit or save for 10 min → hmmph. Then the same simmer and boil ladder as section 10, calming instantly on any activity.

## 12. Open-source product and MCP connector (designed, not built; decisions pending)

the user chose both: an app anyone can install and plug their own apps into, and an MCP connector so AI tools can read focus status and start or end sessions. Nothing gets published, pushed or posted without his direct OK in this chat.

- **Config, not code:** apps, bundle ids, allowlists, session length and count, break rules, idle thresholds and the ideas file move to `config.json` plus a Settings screen. His three apps ship as `examples/aniket.json`.
- **Public contract:** a product-neutral notification name (after the product is named) documented with a 5-line Swift snippet and a CLI one-liner; `com.aniket.focus` stays as a permanent alias.
- **Bring your own key:** the AI check's key lives in the macOS Keychain, never in files or the repo. Providers are pluggable (Anthropic, OpenAI-compatible, or a local model server); with no key, tiers 1 and 2 still work.
- **MCP:** a local stdio server run by the AI client as a child process, which inherits the user's account, so it needs no key ([transport comparison](https://moltchat-agent-commons.onrender.com/wiki/MCP_streamable_HTTP_vs_stdio_transport)). Remote HTTP would need tokens and is not planned. Tools: `get_status`, `start_session`, `end_session`, `park_idea`, `today_summary`. First real client: an AI chat logging work done outside the tracked apps (for example, tailoring a CV in a chat).
- **Release readiness:** README with a demo GIF, CONTRIBUTING, a privacy section (what is watched, what stays local, screenshots off), no personal paths or data in the repo, tests in CI.
- **Name:** "Tomo" is taken by two focus timers on the App Store ([1](https://apps.apple.com/app/id6747645980), [2](https://apps.apple.com/us/app/id1552819174)), so the product needs another name; the character can stay Tomo.

## 13. 0.3 behaviour (23 Oct 2026 live fix)

**The incident.** the user's real use of 0.1.0: it did hide the Viewer and Safari, but it also hid SpeakFit four times in six seconds while he tried to open it (the session was locked to the first study app), and nothing measured whether he was working. He saw no reaction to working, idling or switching.

**Rules now (from his words, relayed 23 Oct):**
- **The clock starts with the task, not the app.** Opening HackerSolve, SpeakFit or the Viewer only *arms* Tomo; the clock starts on the app's `phase=start` (a lesson, a job, a SpeakFit session opens), on Other, or on "Start now" in the launcher.
- **Only active seconds count**, for the session (45 min = 45 *active* minutes) and the day's harvest. Each second: on task (the session's app or its allowed helpers is in front) AND working (input in the last 60 s or a progress ping in the last 3 min) AND on topic (Chrome watcher). Elapsed, idle, off-task and paused seconds are stored too.
- **Switching study apps follows the task**: same tomato, a new task segment in the store. Study apps are never hidden.
- **Auto-size:** after 6 s of calm, active work Tomo shrinks to 62% (anchored at its feet); any trouble and it grows back, then reacts.
- **Ladder:** off task: 10 s grace, nudge, hmmph 30 s, simmer 1 min, boil 90 s, siren 2.5 min. Not working: hmmph, simmer +90 s, boil +3 min, siren +6 min. Back on track or a tap calms it at once.
- **Launcher** (tap Tomo when idle): HackerSolve, SpeakFit, Northstar, Other (type the task), session length 25/30/45/60, Insights.
- **Harvest by minutes:** one tomato = 45 active minutes, whatever the session lengths; 5/5 at 225 active minutes.
- **Breaks** scale with the session (10 min after 45, 7 after 30, at least 3): first half guided breathing, Tomo swelling on the inhale, cyclic sighing by default (Balban et al. 2023, [PMC9873947](https://pmc.ncbi.nlm.nih.gov/articles/9873947/): 5 minutes a day improved mood more than mindfulness; one trial, a co-author is the lab head), box breathing in Settings; tap to skip; second half real rest while the next tomato ripens.
- **Store:** `sessions.sqlite` (sessions and events) in Application Support, CSV export from Insights. No network.
- **Insights:** white, Tomo's palette: active time, tomatoes, focus quality (active ÷ time in sessions), full harvests; per task and per app, today, week, month.

**Defaults chosen tonight without asking (override any):**

| Default | Rejected, and why |
|---|---|
| Compact size 62% | Hiding Tomo while working (loses the "alive" presence); 50% (expressions unreadable at 12 px eyes) |
| Break = 10/45 of the session, min 3 min | A fixed 10 min (a 25-minute session would get a 40% break) |
| Not working = no input 60 s AND no progress 3 min | Input only (reading a slide would count as idle) |
| Another study app's task start retags the session | Ending the session (loses the tomato); hiding the app (the incident) |
| Claude counts as on task for Northstar only | Always on task (it would hide HackerSolve drift into Claude) |
| Siren stays on Tomo | Centre-screen or screen-edge flash (he didn't choose; the evidence favours a visible way out over a trap) |
| Chrome: rules + on-device check every 2 s | An AI key or screenshots (D11) |
| Outcomes in insights (lessons, takes, applications) | Next version: needs each app's outcome extras |

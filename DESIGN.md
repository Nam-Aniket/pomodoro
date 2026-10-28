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

**Rules now (from the user's words, 23 Oct):**
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
| Siren stays on Tomo | Centre-screen or screen-edge flash (the user didn't choose; the evidence favours a visible way out over a trap) |
| Chrome: rules + on-device check every 2 s | An AI key or screenshots (D11) |
| Outcomes in insights (lessons, takes, applications) | Next version: needs each app's outcome extras |

## 6c. Tomo's voice (23 Oct 2026, replaces 6b's set)

Feedback on 0.2: the sounds were "not original nor cute". Redesigned as one character voice, the way loved game characters get theirs: Animal Crossing's Animalese strings tiny sped-up syllables, pitches them per character, and moves the pitch with mood (happy higher, cross lower), chosen over random "beep speech" because it feels "foreign yet familiar" ([Nookipedia](https://nookipedia.com/wiki/Animalese)).

- **Identity:** pitch centred near 520 Hz (a small creature, above a human voice), soft rounded timbre, ~80 ms syllables, rising contours for happy or curious, falling for grumpy or sleepy, a little different every play.
- **Palette (chosen 23 Oct: "mix a and c"):** A, babble voice, for how Tomo feels (rising "ta-da", curious "oo?", "hm-mph", a grumbly "grrr", giggles), layered over C, juicy foley, for what physically happens (pops, squelches, bubbles, the splash, leaf rustles). B, musical boops, stays available. Setting: `soundPalette` = mix | voice | boops | juicy.
- **Siren:** a real siren's continuous wail (pitch sliding 640 to 1160 Hz and back every 2.4 s), made cute with a round tone, light vibrato and Tomo's "ooo" an octave below, looped seamlessly for as long as the siren stage lasts and stopped the instant it ends ("it buzzes constantly rather than vivu and stop in between").
- **Every rung has a sound:** nudge "oo?", hmmph, simmer (a kettle starting to grumble), boil, siren.

## 14. 0.4: profiles, any app, websites in any browser

**Profiles.** A session belongs to a profile: a target (an app, a website, or Other) plus the apps allowed to stay visible and a default length. Setup (first run) and Edit share one window: pick any installed app (icons, search); if the app is a browser, an "Add links" box appears: paste URLs, the registered domain is kept (github.com/you/repo → github.com), any page on it counts, subdomains optional (default on). Allowed apps are suggested from the browsers and AI apps on the Mac. Apps that post the focus contract (presets for the three apps Pomodoro was built with) are only offered when installed; a fresh Mac starts with Other and the setup window.

**When the clock starts.** Apps that post the contract: on their task start. Other apps: when picked in the launcher. Websites: the first time one of the profile's pages is the front tab. Other: when the task is typed.

**Recognising apps (no permission).** A browser is any app Launch Services registers to open https links, except AI apps that also do (ChatGPT). Groups (browser, AI, code, chat, notes) come from a small known list, then the app's App Store category.

**Browser support tiers**, read from each browser's own scripting dictionary without running anything:

| Tier | Browsers | What Tomo knows |
|---|---|---|
| Full | Chromium family (Chrome, Brave, Edge, Vivaldi, Arc, Opera, Comet) and Safari family (Safari, Orion) | the front tab's address and title; asks once per browser for Automation permission |
| Title only | Firefox, Zen and other browsers without tab scripting | nothing yet: reading another app's window title needs Screen Recording (window names via CGWindowList) or Accessibility, so it stays off until the user grants one |
| Unsupported | anything that isn't a browser | treated as a plain app |

Tested on this Mac (23 Oct 2026, from the dictionaries): Chrome full (Chromium), Safari full (Safari), Comet full (Chromium).

**How Tomo knows what you're doing (layers).** Every session is labelled with the richest layer that applied.

| Layer | Works for | What it uses | Permission |
|---|---|---|---|
| L0 | any app, zero setup | which app is in front (NSWorkspace) and seconds since the last key or mouse event (CGEventSource; never the keys) | none |
| L1 | websites in browsers | the front tab's address and title (tiers above) | Automation, per browser |
| L2 | richer task names | another app's window title | Screen Recording or Accessibility; off unless granted |
| L3 | apps and tools that report | the focus notification (`pomodoro.focus`, alias `com.aniket.focus`), the `tomo` command line, the MCP server | none |
| L4 | anything else | Other: the task you type | none |

**What is stored** (all in `~/Library/Application Support/Pomodoro/`, nothing sent anywhere): `state.json` (today: phase, profile, task, seconds), `sessions.sqlite` (each task segment: day, profile, task, start, end, active, elapsed, idle, off-task and paused seconds; and events: stage changes, hidden apps by bundle id, contract events), `profiles.json`, `full-harvests.json` (dates), `sessions.jsonl` (a debug log). Never stored: keystrokes, page contents, screenshots, full URLs (only the host is kept in memory for matching).

**`tomo` and MCP.** `tomo start "task" [--app NAME]`, `end`, `activity`, `idea "..."`, `status`, `today`, and `tomo mcp`, a local stdio MCP server (tools: get_status, start_session, end_session, park_idea, today_summary). It runs as the user's own process, so it needs no key; nothing listens on the network.

**Works on other Macs.** Minimum macOS 14 (Sonoma): the two-argument `onChange` and `NSApp.activate()` set the floor. Universal binary (Apple silicon and Intel). Ad-hoc signed, not notarized (notarization needs a paid Apple Developer ID), so first launch is right-click → Open.

## 15. Design system (23 Oct 2026 redesign)

Feedback: "Really need to work on the UI... modern and good feel... a light-coloured theme... UX, UI and arrangement of things, sizing, text, everything." His screenshot of Profiles showed a dark system title bar over a white window, sidebar icons that read as empty checkboxes, grey system checkboxes and a clipped "Change" button, a dial whose handle hid a label, clipped help text, dead space, and no type hierarchy.

**Research used.** Apple: a macOS sidebar runs the full window height with a rounded selection; content can run under a transparent title bar (full-size content view) while the traffic lights stay put ([WWDC20 10104](https://developer.apple.com/videos/play/wwdc2020/10104/), [HIG sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)). Things 3: white space, bold type and small splashes of colour carry the look ([MacStories review](https://www.macstories.net/reviews/things-3-beauty-and-delight-in-a-task-manager/)). Design-system practice: an 8-point grid, a short type scale, neutrals tinted with the brand hue, dark themes tuned per token rather than inverted.

**Tokens** (Theme.swift; every text colour computed against its background: body text ≥ 4.5:1 in both themes, `ink3` 3.5:1 in light so only for large text and decoration):

| Token | Light | Dark | Use |
|---|---|---|---|
| paper | #FBF7F2 | #1A1513 | window background |
| surface | #FFFFFF | #241D1B | cards |
| fill | #F4EEE7 | #2E2624 | chips, fields, rows |
| line | #EAE1D7 | #3A302D | hairlines |
| ink / ink2 / ink3 | #2B1A17 / #6B5B54 / #8E827B | #F6EEE8 / #C2B5AE / #978A84 | text |
| tomato | #C8372B | #FF7B6B | accent, primary buttons (white text 5.2:1) |
| blush | #FFE9E3 | #3A2420 | selection, soft accents |
| leaf | #2F7A33 | #7BC86A | switches on, positive notes |

Spacing 4 (icon to text only), 8, 12, 16, 24, 32, 48. Type (SF Rounded): display 26 bold, title 20 bold, headline 15 semibold, body 13.5, callout 12.5, caption 11.5, overline 11 bold caps. Radii: controls 8, rows 10, cards 16, panels 20.

**Components:** Card, Overline, PButton (primary, secondary, ghost), PToggle (switch with a leaf-green track), PCheck (rounded tomato check), PChip (pill choice; rows of chips replace every pop-up menu), PField (search and text fields), AppIcon (the app's real icon from Launch Services; a symbol in a blush circle for websites and Other), WindowHeader (title inside the content, below the traffic lights). Windows use `Chrome.style`: full-size content, transparent title bar, hidden title, drag by background, paper background. Appearance is the app's own setting (Match Mac, Light, Dark); Pomodoro never changes the Mac's setting.

**Dial (fixed):** quarter numbers 15, 30, 45 and 60 in a ring outside the rim, so the leaf handle (on the arc, inside the face) can never cover one; a single tomato arc on a quiet track instead of red on pink; ticks pulled to the face edge so "min" never touches them; sideways calyx leaves only, so "60" stays clear.

**Rejected:** keeping system Form controls with a tint (the grey widgets were the complaint); a custom-drawn title bar with fake traffic lights (Apple's guidance is to keep the real ones); a dark-only theme (he asked for light first); a sidebar `List` (its row icons rendered as outlined squares and its selection colour is the system accent, not Tomo's).

## 16. Creating and editing a profile (23 Oct 2026)

Feedback: "No save button if creating a new profile - it hides in plain sight at the bottom." Root cause: New profile wrote a blank "New profile" straight into the list, so there was nothing to save or cancel, and a half-made profile reached the launcher.

**Create is a guided flow; the draft lives only in the window until Save.**
- Steps: 1 What will you focus on (app, or a browser for websites, then a name) -> 2 Which sites count (browsers only) -> 3 What else may stay open (the focus app shown ticked and locked) -> 4 How long (the dial). Sites come right after the browser because they are part of defining the target, and Save needs at least one; asking for them at step 3 would leave Save disabled for a reason the user has not reached yet.
- A fixed footer, never in the scroll: Cancel on step 1, Back after it (Apple: Cancel and Back are the leading buttons of a multi-step sheet, and all three of Cancel, Back and Done together should be avoided). Esc cancels at any step. "Save profile" is the primary button on every step, Return triggers it, and while it is disabled a one-line reason sits beside it ("Pick what to focus on first", "Add at least one site", "Give it a name"). Next walks through; every step after 1 has a sensible default, so Save works early.
- The sidebar dims and locks while a draft is open. On Save the profile is inserted before Other, selected in the sidebar, and appears in the launcher (both read the same list). Zero own profiles shows "No focus profiles yet" with a New profile button.
- Presented in the window, not a sheet: Apple suggests a separate window rather than a sheet for longer flows on the Mac, and the Profiles window already is that window.

**Edit saves as you go** and says so: a green "Saved" for 2 s after each change. Mac settings apply immediately by convention (Apple's older guidelines: most control panel changes apply immediately); an explicit Save on edits would be the odd one out. Create is explicit because a draft is incomplete by nature.

**Window fix found on the way:** every page window ran its SwiftUI content inside the title bar's safe area while also forcing the window's minimum height, so the bottom 28 pt clipped at minimum size (the new footer was cut in half). Page windows now ignore the safe area and their headers pad for the traffic lights, as section 15 intended.

Sources: Apple HIG Sheets (developer.apple.com/design/human-interface-guidelines/sheets, button roles, multi-step placement, macOS alternatives), Apple HIG Buttons (primary role and Return), Apple HIG Settings (macOS settings windows), Mac OS 8 HIG (control panel changes apply immediately; Escape maps to Cancel).

## 17. Contrast, first open, and the 23 Oct "Tomo disappeared" bug

**Contrast (WCAG 2 AA: 4.5:1 normal text, 3:1 large text and non-text icons).** Feedback: "number color too light". The dial face is always white, but its number used the theme ink, which turns near-white in dark mode (1.15:1). Text on a fixed surface now uses fixed colours. Every pair, computed with the WCAG relative-luminance formula; disabled buttons (45% opacity) are exempt by WCAG and are not listed.

| Colour | Use | On | Light | Dark | Needs |
|---|---|---|---|---|---|
| ink | body text | paper | 15.6 | 15.8 | 4.5 |
| ink | body text | surface | 16.6 | 14.5 | 4.5 |
| ink | body text | fill | 14.4 | 12.9 | 4.5 |
| ink | body text | blush | 14.3 | 12.6 | 4.5 |
| ink2 | secondary text | paper | 6.1 | 9.1 | 4.5 |
| ink2 | secondary text | surface | 6.5 | 8.3 | 4.5 |
| ink2 | secondary text | fill | 5.6 | 7.4 | 4.5 |
| ink2 | secondary text | blush | 5.5 | 7.2 | 4.5 |
| tomato | links, ghost buttons, icons | paper | 4.9 | 7.1 | 4.5 |
| tomato | links, ghost buttons, icons | surface | 5.2 | 6.6 | 4.5 |
| tomato | links, ghost buttons, icons | blush | 4.5 | 5.7 | 4.5 |
| leaf | "Saved", notes | paper | 5.0 | 8.9 | 4.5 |
| leaf | "Saved", notes | surface | 5.3 | 8.1 | 4.5 |
| ink3 | search icons, decoration (non-text) | surface | 3.7 | 5.0 | 3.0 |
| ink3 | search icons, decoration (non-text) | fill | 3.2 | 4.4 | 3.0 |
| onTomato | primary button label | tomato | 5.2 | 7.1 | 4.5 |
| dial number 0x3A1512 | large numeral | white face | 16.2 | 16.2 | 3.0 |
| dial "min" 0x6B5B54 | label | white face | 6.5 | 6.5 | 4.5 |
| dial quarter numbers (ink2) | labels | panel paper | 6.1 | 9.1 | 4.5 |
| old dial number (ink, dark theme) | was | white face | - | 1.15 | 3.0 |

**First open.** Without a session nothing is tracked, so every launch opens the launcher (profiles plus Other, then the dial); the first launch ever (no profiles.json) opens the create-first-profile flow (section 16). Tapping Tomo with no session already opens the launcher. While idle or armed and the person is using the Mac, Tomo says "Not tracking yet. Tap me to pick what you're focusing on." at most every 5 minutes and logs an `untracked` event with the front app (an L0 record). It does not start a session by itself: a session hides other apps, which must stay a choice.

**Live bug: "clicked the lesson, and it jumped to a corner and disappeared".** Evidence: Pomodoro's process was hidden with no on-screen window, Stage Manager is on (`com.apple.WindowManager GloballyEnabled = 1`), and Pomodoro runs as a regular Dock app. Using the 0.5 launcher made Pomodoro the active app; when HackerSolve came forward, Stage Manager swept Pomodoro's window set, Tomo included, into the side strip. Neither Pomodoro's guard nor HackerSolve hides it (checked: self is always allowed; no hide call in HackerSolve). Fix: Tomo's panel has `canJoinAllApplications` (Apple's AppKit header: "commonly used for floating windows and system overlays"), so it joins every app's set. Also: starting a session always fronts Tomo, pulled back onto a screen if it is off every screen, and the start says "Started: <task>, <n> min". Auto-shrink scales Tomo to 62% around its feet inside a panel that never moves.

**Reaction ladder, faster (23 Oct: "reduce the timeline to angry and siren... by 5 to 10 seconds").** Seconds since the trouble began. The reading allowance is unchanged: not working is declared only after 60 s with no input and 180 s with no progress.

| Off task | nudge | hmmph | simmer | boil | siren |
|---|---|---|---|---|---|
| Before | 10 | 30 | 60 | 90 | 150 |
| Now | 10 (glance grace, kept) | 22 | 44 | 66 | 116 |

| Not working (after the allowance) | hmmph | simmer | boil | siren |
|---|---|---|---|---|
| Before | 0 | 90 | 180 | 360 |
| Now | 0 | 80 | 160 | 330 |

## 18. Live-bug pass for 0.5.1 (23 Oct 2026, night)

**No silent starts ("it auto started another session for 45 mins").** Log: emergency exit at 23:35:19; HackerSolve posted `phase=start` for the same lesson at 23:35:43, and Pomodoro started a 45-minute session because any study-app start began a session whenever none was running; the 5-minute pick had been used by the first session. Rule (`Policy.contractStart`, regression checks for each path): a study app's start begins a session only if that profile was picked in the launcher. Otherwise (after an exit, after a break, after just opening the app, day done) Tomo opens the launcher pre-filled with that app and waits for one tap; Start then begins the already-open task at the chosen length. After a break, the tap keeps the last session's length. Every start says "Started: <task>, <n> min".

**A session is locked to its profile (reverses 0.3's "study apps are never hidden; switching retags").** Feedback: "when I open SpeakFit it jumps to that, and then on Northstar it jumps to Northstar." Now another study app is hidden like any app the profile does not allow, its focus events are logged and ignored, and Tomo asks "SpeakFit isn't in this focus. Switch focus to SpeakFit?" with Switch (ends this session, saved, and opens the picker on SpeakFit) or Stay (it stays hidden). Allow a study app in the profile to keep it open.

**Hides that did not stick ("the app hides don't work always").** The log had 11 `hide-retry` entries (Safari, WhatsApp): the first hide, 0.15 s after activation, did not hold, and nothing checked afterwards. Now the front app is checked every second during a session; a non-allowed app is re-hidden and logged as `hide-poll` with the likely cause ("came back after a hide" or "no activation seen"). The safety list (Claude, Terminal, Finder, System Settings and the rest) is never hidden.

**Performance (23 Oct: "when blocking it shouldn't hang the Mac").** Measured with `tools/perf_check.sh` (the real Tomo panel in a click-through window at 1% opacity, release build, this MacBook Air) and `top` on the installed app.

| | Before (0.5.0) | After (0.5.1) |
|---|---|---|
| Installed app, paused session, a page window closed earlier | 31-39% CPU | not yet measured live |
| Tomo panel, calm focus | 7.0% (15 fps), 10.5% (30 fps) | 1.2-1.7% |
| Tomo panel, idle | about 7% | 0.5-0.7% |
| An empty animated shape (harness baseline) | 3.4% | 0.6% |

Causes and fixes: (1) closed page windows stayed alive and re-laid themselves out on every model change: they now drop their view on close. (2) SwiftUI `TimelineView` kept the display link awake, about 3% even at 4 fps: a plain timer (`TomoClock`) now drives frames. (3) Tomo drew 15 to 30 frames a second all the time, about 0.35% CPU per frame per second: it now draws only when something moves (30 fps for big moments; 15 for hover, nudges, breaks and speech; in calm focus a still frame plus a 1.2 s burst every 8 s; idle stays still until hovered). (4) The once-a-second tick republished unchanged state, redrawing Tomo every second: it now publishes only on change. Escalation (nudge to siren) still animates at 15 to 30 fps, about 5%, while it lasts. Browser tab reads already ran off the main thread. An app that comes back after 3 re-hides is let be for the session ("hide-gave-up" in the log) instead of a flicker loop. Not yet measured: memory over an hour, and main-thread stalls during a real hide.

**Live drive, 24 Oct 00:12 (0.5.1 installed, recorded to renders/live/051).** Passed: launch opens the picker; HackerSolve plus 5 min armed it; opening a lesson started it with "Started: Lesson 101..., 5 min" and a 300 s target; Tomo stayed visible above HackerSolve with Stage Manager on; SpeakFit, the Viewer and others were hidden at start; opening SpeakFit and then the Viewer mid-session hid each and offered Switch or Stay, and the session stayed HackerSolve; after an emergency exit, reopening the lesson opened the picker instead of starting; live CPU in focus 1.4-5.4% (about 3% average, start bubble included; was 31-39%), memory 36 MB (was 93 MB). Found and fixed after the drive: focus fell to Finder instead of HackerSolve after a hide (macOS 14 cooperative activation: the session app is now brought forward through Launch Services); the picker offered 45 min after a 5-min session (the last length is now remembered per profile); "Nice, Lesson done" was said when no session was running; the pending-task bubble and the Start label were cut off. Breathing: it moved in one-second steps because it ran off the once-a-second tick (now interpolated, with the breath sound fired from the frame clock), cycled every 8 s (now 6 s, 10 breaths a minute), and inflated the whole tomato by 23% (now a 4-6% rise from its base).

## 19. Shipping: updates, help, the installer (24 Oct 2026)

**Updates: notify and download, never replace.** At launch (at most once a day, Settings switch, on by default) and on demand (Help → Check for Updates, the menu bar menu, Settings → Check now), one GET to GitHub's latest-release record; `Update.outcome` reads the tag, notes and `.dmg` asset (offline checks in pomodoro-check). A newer version shows a seed packet with a swaying sprout and a "new" tag beside Tomo, only when no focus session is running; it opens a card with the notes and "Get the new version", which downloads the disk image to Downloads and opens it at the drag step, or opens the release page if the download fails. No silent replacement: the app is not notarised, and a self-replacing unsigned app is what macOS is right to distrust. Copies older than the first release with the checker (0.4.x, 0.5.0, 0.5.1) never learn about updates; their users are told in the release notes.

**Notarisation (the owner's call, later).** Apple's notary service would remove the first-open warning: a notarised app opens with a plain "downloaded from the internet" confirmation, and updates need no Privacy & Security step. It needs a paid Apple Developer Program membership and a Developer ID certificate. Until then the README gives both first-open routes: macOS 15 and later, System Settings → Privacy & Security → Open Anyway (the Control-click shortcut no longer skips it, per Apple's "Safely open apps on your Mac" and reports of the Sequoia change); macOS 14, Control-click → Open.

**Installer.** `RELEASE=1 tools/make_app.sh` builds the release disk image: a 640 x 420 window, the app on the left, Applications on the right, a dashed tomato arrow between, and the first-open step written along the bottom; the background is drawn by the app itself (`--dmg-background`, 1x and 2x) and laid out by Finder on a writable image, then compressed.

**Help.** Shortcuts & Help (menu bar menu, Help menu ⌘?, Settings, `?` on Tomo) lists only controls that exist, the way out first. The first-run profile flow shows ⌃⌥⌘E; the first time a session hides apps, Tomo says "Need out? ⌃⌥⌘E brings every app back." Settings had listed a "⌘S" that never existed; removed.

## 20. Insights, one question per card (24 Oct 2026)

Feedback: "Insights are not at all clear." What made it unclear, on the user's real data: 14 session rows, most "0 active min" (every 2-second retitle was its own row); "Focus quality: active ÷ time in sessions" and "Full harvests" as headline numbers; a 10-hour timeline of unreadable slivers; an empty Outcomes card; and no answer to "what pulled me away?" although the hide log had it. Rule now: each card answers one question, and the answer comes before the chart.

| Card | Question it answers |
|---|---|
| Answer line | How did it go? One sentence: active minutes against the goal (or the daily average and the change on the period before), where most went, the biggest leak |
| Harvest, Active time, Kept on task (Full days on week and month) | How much real work? "Kept on task" says "14 min of 34 min was real work" instead of a ratio |
| What you worked on | On what? Tasks of a minute or more, top 6; shorter ones counted in the note |
| Where session time went | What leaked? Working, off task and idle in minutes and percent (paused is not a leak: noted, not barred), the apps Tomo had to hide most, and how often it nudged and sirened |
| Sessions today (today) | When? Segments of one task under 2 minutes apart joined into one session; under a minute not listed |
| Active minutes per day (week, month), Last 30 days (month) | Which days? |

Removed: the day timeline strip, the Outcomes placeholder, per-task session counts. Checked on real data (today, week) and an empty folder.

## 21. 0.5.3: the breathing-break crash (24 Oct 2026)

Every breathing break with sound on crashed, from 0.3 to 0.5.2: `Sound.render` wrote the breath sounds (2.4 s in, 4.6 s out) into a buffer sized for 1.9 s, and Swift traps on an out-of-range write. Evidence: a 0.3.0 crash report (23 Oct 15:36, `Model.breathCue` → `Sound.render`, "Index out of range"); the installed 0.5.2's `--sounds` stopped at the inhale with a trap; found by the ad session rendering sounds. Fix: the buffer is sized per cue, and the breath sounds fit the 6 s cycle (in 2.4 s, out 3.4 s). Check: `--sound-check` renders every sound in every palette with 20 random seeds (production seeds are random, so a seed-dependent overrun would show), run by `tools/check.sh` with the logic and performance checks.


## 22. 0.5.4: one-click install (24 Oct 2026)

Feedback after updating by hand: the app is open, so dragging it to Applications is refused, and closing, dragging and reopening is friction; "can it not auto install? like when i click on get the new version". This reverses section 19's "never replace": the replace is still never silent, it happens on the click. **Install and restart** downloads the release's disk image, mounts it, and checks the new app with `codesign --verify --strict --deep -R=<this app's designated requirement>`: the same identifier and the same leaf certificate, so only a build signed with the owner's key passes (a copy re-signed by anyone else is refused, checked). It copies the app out, starts a small shell helper that waits for Pomodoro to quit, moves the old app aside, puts the new one in place (restoring the old one if the copy fails) and opens it, then Pomodoro quits (the mid-session "Quit?" question is skipped for this). If the folder isn't writable, the copy isn't signed in a checkable way, or the check fails, nothing is replaced and the card shows the manual steps. Rejected: Sparkle (its own EdDSA keys and appcast feed for the same result). Tested: a copy labelled 0.5.2 in a temporary folder installed the real 0.5.3 release over itself (`--update-test`). Copies before 0.5.4 still update by hand once.

## 23. Smart tracking: start when you get going, count only engaged time (24 Oct 2026)

Feedback: "For northstar it waits for us to do jobs - which is not right - sending emails and reading other things should also be a part of it. Also for other apps - It starts after a few actions... rather if it starts when we are interacting with app - and then lets say if we keep the same window open with no interaction then it is counted as not a great progress since we didnt do anything - but if we interact lets say 4 pages in a chapter then that's counted."

- **Start on interaction.** Ten seconds of real input (keys, clicks, scrolls) with a profile's app in front starts tracking at that profile's last length, with the usual "Started: ..., n min". A study app's own task start does the same. This narrows section 18's "nothing starts unless picked": the 45-minute incident was a start right after an emergency exit, at the wrong length. So an exit blocks auto-start for 10 minutes (a launcher pick or a Switch lifts it), lengths come from the last session of that profile, a break still ends on a tap, and a finished day stays finished.
- **Count only engaged time.** A second is active when the session's app (or an allowed one) is in front and there was input in the last 20 s or a progress ping (a page, a slide, an item) in the last 2 minutes. An untouched window open for 10 minutes now adds about 20 seconds, not 3 minutes. Scolding is unchanged: "not working" still needs 60 s without input and 3 minutes without progress, so reading is not punished, only not padded. Time on task but not engaged is recorded as idle.
- **Northstar includes email.** Apple Mail and Outlook are allowed in the Northstar profile; Gmail, Outlook web and Google Calendar count as on topic in the browser, with the job sites. Job-related reading elsewhere is judged by the on-device topic check against the task.

## 24. 0.5.6 and 0.5.7: allowed pages, real breathing, one-tap starts (26 Oct 2026)

- **No "go back" on an unknown page.** Live case: Chrome allowed in Northstar, on acme.com reading the exact job, Tomo said "That's not Reviewing Data Scientist at Acme". The tab title scored 1.107 on the sentence model, past the old 1.02 off-topic cut; the careers page scores 1.27 and cat videos 1.12, so distance can't tell work from play. Now distance only promotes a page to on topic (`TopicRules.resolve`); off topic needs the distraction list or a video title that doesn't fit, and a page on or titled with the task's company is on topic. Re-driven on the installed app: 0.5.5 nudged, 0.5.6 did not.
- **Breathing reads as breathing.** "The shrinking and upsizing should have a proper difference so small to big with proper breathing sound inhale and exhale." Body 0.78 to 1.12 (was 4 to 6%); inhale a rising nose hiss plus a top-up sniff (1.8 + 0.7 s), exhale a 3.4 s mouth "haaah" fading out.
- **Opening an app never starts a session (0.5.7).** "It still starts automatically once i open northstar or any other for which the rule is set"; asked, he chose "Ask, one tap starts". This reverses section 23's start on interaction: a task start or input starts the clock only for the profile picked in Tomo; otherwise Tomo opens the picker once, pre-filled with the app's latest task, and nothing is hidden until Start. Engaged-only counting from section 23 stays.
- **Pages open in front (0.5.8).** "When I click on profiles or analytics, it doesn't always work properly." Tomo's app is almost never active (its panels are non-activating), and since macOS 14 `NSApp.activate()` is a request the front app may refuse; then `makeKeyAndOrderFront` ordered the page front only within Tomo's own app, behind everything else. Measured with `POMODORO_OPEN=insights|profiles` on a test copy (opens the page 4 s after launch with another app in front and logs active/key/visible): 6 of 8 hidden before, 15 of 16 in front after. Fix: one `present(_:)` used by every page window: `activate(ignoringOtherApps:)`, `makeKeyAndOrderFront`, `orderFrontRegardless`. Stale "starts when you get going" labels now say "tap Tomo to start" unless the profile was picked.

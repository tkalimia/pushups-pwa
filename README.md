# Pushups

An installable iPhone web app that counts pushups with the camera and keeps your progress for years.
No App Store, no build step, no backend (until the optional push phase). Plain HTML, CSS and ES
modules served as static files over HTTPS.

Phase 1 is the counter: setup screen, set lifecycle, correction, local saving, voice, offline,
and a hidden counter lab for tuning.

## Install it on your iPhone

```bash
cd ~/Projects/pushups
./scripts/deploy.sh -m "phase 1: counter core"
```

That creates the GitHub repo, enables Pages, pushes, and prints the live URL
(`https://<you>.github.io/pushups-pwa/`). Then, on the phone:

1. Open that URL in **Safari** (Chrome on iOS cannot install PWAs).
2. Share ▸ **Add to Home Screen**.
3. Launch it from the icon — not from a Safari tab. The camera only works in the standalone window.
4. Allow the camera when asked. First launch downloads ~20 MB of model and WASM, so let it finish
   before you go offline.

Everything after that is on the phone: IndexedDB holds your sets, the service worker holds the code,
the pose model and the wasm, so the app counts with the laptop shut and the phone in airplane mode.

## Everyday use

- **Train** — set the phone on the floor, 1.5–2.5 m away, side-on to you. Fix the four checklist
  lines, tap Start set, hold the plank, count. `−` / `+` correct mid-set, End finishes it, and the
  summary lets you rewrite the number before saving. The saved record keeps both
  `repsDetected` (what the camera saw) and `repsFinal` (what you kept).
- **Today** — total for the day and the list of sets, with delete.
- **Settings** — depth preset, threshold sliders, clean-reps-only, auto-start, voice, camera,
  model, export/import, and diagnostics.
- **Counter lab** (Settings ▸ Counter lab, or `#/debug`) — live angles and state-machine state,
  threshold sliders you can move mid-set, and video-file replay so you can tune the counter while
  lying on the sofa instead of doing pushups.

## Backup

Sets live in the phone's IndexedDB, which iOS can wipe if storage pressure gets bad and you have
never opened the app. Settings ▸ Data ▸ **Export JSON** writes a file to Share — keep one in Files
or iCloud Drive. Import merges, it does not overwrite.

## Update

Change the code on the Mac, run `./scripts/deploy.sh -m "…"`. The next time the app is opened with
a network connection the service worker finds the new build and shows
*“Update available — tap to reload”*. Data survives; the database schema is versioned and
migrations run on open.

## Development

```bash
./scripts/dev.sh              # http://localhost:8080 — desktop only, the camera works there
./scripts/dev.sh --tunnel     # prints a trycloudflare.com URL an iPhone can reach
```

iOS refuses the camera on plain `http://` LAN addresses, so a phone needs real HTTPS. The tunnel is
fine for a quick check but the URL changes every restart, which resets the camera permission and the
offline cache. Test properly from the Pages URL.

```bash
bash tools/build-stamp.sh     # rewrite sw.js: new cache version + precache list
bash tools/fetch-assets.sh    # re-download MediaPipe wasm, models, fonts, regenerate icons
node tests/counter.test.mjs   # counter engine regression tests
```

## Layout

```
index.html            app shell, tab bar, service-worker registration
manifest.webmanifest  name, icons, standalone display
sw.js                 generated: versioned cache + precache list + update flow
css/app.css           palette, safe-area insets, dark and light
css/today.css         goal ring, streak line, missed-day sheet
css/progress.css      heatmap grid, chart axes, range switcher
js/main.js            hash router, update prompt, wake-lock and storage sentinels
js/camera.js          getUserMedia lifecycle + human recovery copy
js/pose.js            MediaPipe landmarker, gpu→cpu fallback, 15–30 fps, skeleton overlay
js/counter.js         state machine: hysteresis, arm gate, flags, presets, one-tap debounce
js/one-euro.js        smoothing for elbow angle
js/workout.js         set lifecycle helpers (modes arrive in phase 3)
js/db.js              IndexedDB v1: sets, reps, meta + export/import
js/stats.js           day/week/month/year buckets, streaks, records, estimates, heatmap
js/goals.js           daily/weekly/yearly goals, streak mode, rest passes (stored in db meta)
js/badges.js          rule engine (phase 3)
js/plans.js           progression plans (phase 3)
js/reminders.js       due-today card, Badging API, .ics (phase 3)
js/feedback.js        voice, beeps, haptics
js/upgrade.js         update prompt, wake lock, persistent storage, badging
js/util.js            small DOM/format helpers
js/views/*            today, train, progress, badges, settings, debug
vendor/mediapipe/     tasks-vision bundle + wasm, self-hosted
models/               pose_landmarker_lite.task, pose_landmarker_full.task
fonts/                Barlow Semi Condensed (the rep number), IBM Plex Sans (everything else)
icons/                generated app icons
tools/                asset fetcher, icon generator, sw stamper, dev server,
                      shots.mjs (headless iPhone screenshot harness), seed.js (fixture data)
scripts/              dev.sh, deploy.sh
```

## Roadmap

| phase | what |
|---|---|
| 1 | counter core, setup, lifecycle, correction, saving, voice, offline, counter lab |
| 2 | ✅ Today with goal ring, history heatmap, charts, records, goals, streaks, export/import of goals |
| 3 | badge engine, workout modes, plans, Layer A reminders (in-app card, icon badge, `.ics`) |
| 4 | threshold tuning from your detected-vs-corrected data, performance, accessibility |
| 5 | optional Layer B Web Push via a Cloudflare Worker with VAPID + cron |

## Known limits in this build

- The counter reads a 2D skeleton. A side view in normal light is the reliable case; heavy shadows,
  a cluttered background behind your arms, or the phone closer than ~1.2 m will cost accuracy.
- `navigator.vibrate` is not exposed to iOS Safari, so haptics stay off on the phone even when
  enabled. Beeps and voice carry the feedback.
- The Badging API is used when present; in a plain Safari tab iOS ignores it, so the icon badge only
  appears for a Home Screen install.
- Offline is proven after a first successful load with the model fetched. Clearing Safari website
  data, or iOS deciding the app is stale, drops the cache — reopen it online once and it rebuilds.
- The Badges tab is still a placeholder (phase 3). Today, Progress and Settings are live.
- Charts only ever show what is on this phone. Export after every meaningful session — a cleared
  Safari website-data drops both the history and the offline cache.
- `estimatedMax` is a floor plus a documented allowance (+12% of your best recent set, capped at
  +10), not a measurement. The milestone date is a least-squares fit over your last 12 weekly best
  sets and moves as soon as you log one real set.
- Tempo and depth consistency need per-rep rows, which only sets saved by the camera have. Manual
  sets and anything imported from an older export show as unmeasured.

<p align="center"><img src="app/Resources/AppIcon-1024.png" width="160" alt="zeroCortisol icon: an eye over a pyramid"></p>

# zeroCortisol

zeroCortisol is a small macOS menu bar app that pairs a daily quote from classical philosophy and literature with a one-line daily check-in. Everything stays on your Mac: a local SQLite file, a native dashboard, and a local HTML page that shows your pinned quotes as a constellation.

- **Truth of the Day.** Each day shows one quote from a corpus of 407 verbatim, public-domain passages (Epictetus, Marcus Aurelius, Plato, Dostoevsky, Tolstoy, Kierkegaard, Kafka, Machiavelli, Nietzsche and others). You can pin it.
- **Archive.** Pinned quotes can be tagged. Filter by tag, "All pins" or "Untagged", add or remove tags, and unpin.
- **Tracker.** A strict four-step check-in: mood → sleep → strength → stillness, each scored 1–9. The fourth choice locks the day in with a haptic tap and a spring animation, and the row collapses to `M:x Sl:x St:x Sti:x`, with `Streak: N | Total: N` below it.
- **Dashboard.** Swift Charts in three tabs: composite score, split scores, and a lenient trajectory with a 7-day projection.
- **Web Node.** A dark "sea" constellation linking authors → works → pinned quotes, plus a sidebar of recommended works shown as posters.

## Requirements

- macOS 14 or later, on Apple Silicon or Intel.
- Swift 6 toolchain. The **Command Line Tools are enough**; Xcode is not required.

## Build and run

```bash
scripts/build_app.sh          # release build → dist/ZeroCortisol.app (ad-hoc signed)
open dist/ZeroCortisol.app    # the eye-over-pyramid icon appears in the menu bar
```

`build_app.sh` runs `swift build -c release` in `app/`. It then assembles the bundle with an `Info.plist` (`LSUIElement`, bundle id `com.gigacook.zerocortisol`, minimum macOS 14), the icon, the seed data, the schema, the web page and the menu bar images, and finishes with an ad-hoc `codesign`. The icons are committed under `app/Resources/`. To redraw them, run `scripts/build_app.sh --icons` or `swift scripts/make_icon.swift app/Resources`.

The ad-hoc signature is not a Developer ID signature. If Gatekeeper blocks a copy downloaded from elsewhere, right-click the app and choose **Open**.

For development, run `swift run --package-path app ZeroCortisol`. Without a bundle, resources are read from the repository (`data/`, `web/`, `app/Resources/`).

### Command-line flags

| Flag | Effect |
|---|---|
| `--export-web [--open]` | Writes `data.js` and `index.html` to the web folder and exits. |
| `--snapshot-charts <dir>` | Renders the three dashboard charts to PNG files, in light and dark, and exits. |
| `ZC_HOME=<dir>` (environment) | Uses another data directory instead of Application Support, for example for a throwaway test database. |

## Tests

```bash
scripts/test.sh
```

The suite uses **Swift Testing** (`import Testing`). With full Xcode installed, `swift test` in `app/` works directly. With only the Command Line Tools, `Testing.framework` sits outside SwiftPM's default search paths, so `scripts/test.sh` adds the `-F` and rpath flags. Every test uses a temporary database.

The tests cover:

- the composite formula
- asymmetric smoothing
- projection damping, clamping and the 30-day window
- streak and total counts
- idempotent seeding
- pins and tags
- recommendation rules
- deterministic Truth of the Day
- the web export

`python3 scripts/verify_quotes.py` re-checks every quote against its source text. The raw texts are not part of this repository, so this check only runs where they are present locally.

## Architecture

```
app/
  Package.swift
  Sources/ZeroCortisolCore/   library: all logic, no UI
    Models.swift              Quote, Pin, Tag, DailyLog, Poster
    DayKey.swift              YYYY-MM-DD keys and time-zone-safe day arithmetic
    Scoring.swift             Metric weights, composite, streaks, Truth of the Day
    Trajectory.swift          asymmetric EMA + damped projection
    Store.swift               SQLite3 store (schema, seeding, pins, tags, logs, recommendations)
    ResourcePaths.swift       bundle vs. repository resource lookup; Application Support paths
    WebExport.swift           window.ZC_DATA payload → data.js
  Sources/ZeroCortisol/       SwiftUI app (MenuBarExtra .window + Dashboard Window scene)
  Tests/ZeroCortisolCoreTests Swift Testing suite
  Resources/                  AppIcon.icns, menu bar template PNGs
data/                         quotes.json, corpus_meta.json, schema.sql (+ Markdown views)
web/index.html                constellation page (vanilla JS, no dependencies, works from file://)
scripts/                      build_app.sh, test.sh, make_icon.swift, verify_quotes.py
```

- **Storage.** The database is `~/Library/Application Support/ZeroCortisol/zc.sqlite`. On every launch, the app applies `schema.sql` (`CREATE … IF NOT EXISTS`) and seeds authors and works from `corpus_meta.json`, then quotes from `quotes.json`. Seeding uses `INSERT OR IGNORE` on natural keys, so it is idempotent and never touches your pins or logs.
- **Menu bar.** A `MenuBarExtra` uses the `.window` style. Its label is a template image: a closed eye over a pyramid, which switches to an open eye while the panel is shown.
- **Recommendations.** For each author with at least one pin, ordered by that author's pin count (highest first), every work of theirs with no pins becomes a poster: `{author, work, authorPinCount, teaserQuote}`. The teaser is the quote with the lowest id in that work.
- **Truth of the Day.** `index = (dayNumber · stride + 17) mod N`, where `stride` is coprime with `N`. The pick is deterministic per calendar day, visits every quote once per `N`-day cycle, and never steps to a neighbouring quote on consecutive days.
- **Web Node.** The browser blocks `fetch` from `file://`, so the app writes the data as a script: `web/data.js` (`window.ZC_DATA = {pins, authors, works, recommendations}`). It copies `index.html` next to that file in Application Support and opens it. The page runs a small force layout on a canvas, with hover tooltips, click-for-details, drag, pan and zoom. If there is no data, it shows an empty-state message instead.

## Composite score

```
Composite = Mood×1 + Sleep×1 + Strength×2 + Stillness×2        (each metric 1–9 → range 6–54)
```

Strength and Stillness count double.

## Trajectory algorithm

The trajectory is meant to be lenient: it responds quickly to improvement and resists reading a bad day as a trend.

1. **Window.** Only logs within the 30 calendar days that end at the most recent log are used, which is at most 30 points.
2. **Asymmetric EMA** of the composite. The first value seeds the average. For each later value `x`:
   `α = 0.6` if `x > s` (rising), otherwise `α = 0.1` (falling); `s ← s + α·(x − s)`.
   For example, a rise from 30 to 40 moves the average to 36, while an equal drop from 40 to 30 only moves it to 39.
3. **Slope.** This is the least-squares slope, in points per day, of the last ≤7 smoothed values. A negative slope is multiplied by **0.25**; a positive slope is used as is.
4. **Projection.** For `d = 1…7`: `clamp(s_last + slope·d, 6, 54)`.

The chart shows the actual points, the smoothed line and the dashed 7-day projection.

## Data

The quotes are verbatim excerpts from public-domain translations. See `data/README_data.md` for the JSON shape, the theme vocabulary and the verbatim-matching rules. Local-only working folders (`source/`, `private/`, `build/`) are git-ignored.

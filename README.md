# Yearwall

A macOS menu bar app that generates a wallpaper every day and sets it as the desktop
background. The wallpaper draws one mark per day of the current year, as a grid.

No analytics. No accounts. The only network request is a daily update check against this
repository's GitHub releases.

## Build and run

```sh
swift build && swift run          # development: menu bar app, no Dock icon
./Scripts/make-app.sh && open build/Yearwall.app   # bundled app (Launch at Login, updates)
swift test                        # 134 tests
swift Scripts/make-icon.swift     # redraw Resources/AppIcon.icns
```

Development helpers, neither of which touches the desktop:

```sh
swift run Yearwall --report        # screen geometry + what wallpaper each screen shows
swift run Yearwall --preview --pattern phyllotaxis --appearance light --out /tmp/p.png
```

Logs go to stderr and to `~/Library/Logs/Yearwall.log`.

## Releases and updates

Pushing a `v*` tag runs `.github/workflows/release.yml`: tests, a universal (arm64 + x86_64)
build stamped with the tag's version, and a GitHub release carrying `Yearwall-<version>.zip`.

```sh
git tag v0.2.0 && git push origin v0.2.0
```

The bundled app checks `releases/latest` of the repository named by
`YearwallUpdateRepository` in `Info.plist` once a day (looking every hour whether a day has
passed, so sleep does not skip a check), plus "Check for Updates…" in the menu. A newer
release is downloaded, checked against the SHA-256 digest GitHub publishes for the asset,
unpacked, checked for the same bundle identifier and the expected version, `codesign
--verify`'d, swapped in place of the running bundle, and relaunched. The install waits while
the settings bar is open.

Releases are ad-hoc signed, not notarized. The first download from the browser needs
right-click → Open (or `xattr -dr com.apple.quarantine Yearwall.app`); updates fetched by the
app itself carry no quarantine flag. The app must sit in a folder the user can write to,
such as `/Applications` on an admin account.

## Architecture

Four modules. The pattern engine knows nothing about AppKit, files, or the desktop.

| Module | Depends on | Responsibility |
| --- | --- | --- |
| `TimeModel` | — | `ProgressCalculator` turns a `Date` into a `Progress`. Pure values, explicit `Calendar` and `TimeZone`. |
| `PatternEngine` | `TimeModel`, CoreGraphics | `WallpaperConfig`, `Theme`, `CompositionBudget`, `CanvasSpec`, `Composition`, `SeededRNG`, the `Pattern` protocol and the patterns. |
| `Renderer` | `PatternEngine` | `render(config:progress:canvas:)` → `CGImage` → PNG on disk. Pure function of its three arguments. |
| `WallpaperService` | `Renderer`, AppKit | `ConfigStore`, screens, scheduling, `NSWorkspace`, the file cache. |

Adding a pattern means adding one file in `PatternEngine` and one line in
`PatternLibrary.all`. Nothing else changes.

### Configuration

`WallpaperConfig` is the one persisted object: birth date, lifespan,
`Theme`, `CompositionBudget` and the install seed. It is stored as a single JSON blob under
the `wallpaperConfig` key, and every field decodes leniently — a missing, malformed or
unknown field falls back to its default instead of throwing away the whole config (and with
it the install seed, which would change every wallpaper the user has).

Rendering is a pure function of `(config, progress, canvas)`. `Composition` combines a
config with a canvas and precomputes the derived geometry and colours; it is the single
argument a pattern draws against.

### Type names worth knowing about

`Progress` and `Pattern` both collide with system types (`Foundation.Progress`, and a
`Pattern` visible in some import combinations). Inside this package they are spelled
`TimeModel.Progress` and `PatternEngine.Pattern` where the context is ambiguous. The
calculator is called `ProgressCalculator` rather than `TimeModel` so that the module name
stays available for qualification. Likewise the light/dark enum is `Appearance`, not
`ColorScheme`, because SwiftUI owns that name and the settings UI imports both.

## Determinism

`SeededRNG` is splitmix64, written out in full in `SeededRNG.swift` so its output cannot
drift with a toolchain update. `Int.random` and `arc4random` are not used anywhere.
Hashing is FNV-1a, never `Hasher` — Swift's hasher is seeded randomly per process and
would produce a different wallpaper on every launch.

Two levels of seeding:

* **Install seed** — generated once, stored inside the persisted config. Fixes the
  `PatternCharacter` (base density, orientation, where the composition sits).
* **Day seed** — `splitmix64(installSeed, FNV1a("yyyy-MM-dd"))`. Drives per-day variation.

Same date + same install seed + same settings produce a byte-identical PNG. This is
asserted directly on the encoded bytes in `Tests/RendererTests`, for both patterns, across
repeated renders. `CGImageDestination` turned out to be byte-stable for identical pixel
buffers, so no hand-written PNG encoder was needed.

## Composition budget

The output is a wallpaper, not a poster. `CompositionBudget` holds every number that
enforces that, and nothing is hardcoded outside it.

* **Grid size** — the grid is exactly as big as its marks and gaps make it:
  `maxMarkSizePoints` (10pt) per mark, `columnGapPoints` (6pt) and `rowGapPoints` (16pt)
  between them, centred on the canvas. It shrinks, marks and gaps together, only when it
  would not fit inside the safe rect. `contentScale` now only bounds Phyllotaxis.
* **Contrast cap** — `Composition.mark(_:)` is the only way a pattern can produce a
  colour. It blends along the theme's contrast ramp, which is itself clamped by
  `maxPatternContrast` (0.55). A pattern cannot exceed the cap even by passing an absurd
  intensity. The v0 brief set this at 0.20; 20% of the way from black to white is `#333`
  on `#000`, which reads as almost nothing, so it was raised on the owner's call. The
  mechanism is unchanged — only the number.
* **Safe insets** — 40pt for the menu bar (covers notched Macs), 100pt for the Dock,
  5% side margins. Expressed in points and multiplied by the canvas scale.

Two things from the original spec were removed on the owner's instruction, and their
absence is deliberate rather than an oversight:

* **The "today" accent mark.** Today is drawn as an ordinary filled mark.
  `ResolvedTheme.accent` and `CompositionBudget.accentContrast` remain in the API for the
  modes that will want them.
* **The quiet zone.** The rightmost slice of the canvas used to have its contrast faded so
  desktop icon labels stayed readable. It is gone — contrast is now uniform across the
  canvas, and nothing in the pattern depends on where a mark sits horizontally. Keeping
  icon labels readable is now a matter of the contrast cap and the palette alone. If it
  comes back it should come back as a single falloff parameter on `CompositionBudget`.

## Scheduling

The app is always running and schedules its own work. It never shells out and never
installs a LaunchAgent — a background process cannot reach the display session on recent
macOS (`Could not switch to audit session`), and AppleScript via System Events no-ops.

Triggers: launch, local midnight, `NSWorkspace.didWakeNotification`,
`NSApplication.didChangeScreenParametersNotification`, `AppleInterfaceThemeChangedNotification`,
`NSWorkspace.activeSpaceDidChangeNotification`, and "Refresh Now".

Midnight is re-scheduled after each fire from `Calendar.nextDate(after:matching:)` rather
than by a 24-hour repeating timer, so DST and sleep cannot make it drift.

All triggers funnel through `requestRefresh(reason:)`, which coalesces on an 0.8s timer and
then compares a fingerprint of `(settings, day, appearance, screens)`. A wake at 00:00:05
and the midnight timer collapse into one render. If nothing changed, the cached files are
re-applied instead of being re-rendered.

## What was actually observed on macOS 26.2

### Path caching is real

`NSWorkspace.setDesktopImageURL` caches by URL. Every render goes to
`yearwall-<yyyy-MM-dd>-<display>-<pixels>-<scheme>-<content hash>.png`, so new bytes always
arrive at a new path.

### Spaces

Measured by diffing `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`
before and after a single `setDesktopImageURL` call and decoding the nested binary plists
inside `Configuration`. On macOS 26.2 one call wrote our path into **four** places:

| Key | Meaning |
| --- | --- |
| `SystemDefault/Desktop` | template inherited by **newly created** Spaces |
| `Spaces/""/Default/Desktop` | the current Space |
| `Spaces/""/Displays/<display-uuid>/Desktop` | the current Space on that display |
| `Displays/<display-uuid>/Desktop` | that display's default |

Roughly fifty other remembered `Spaces/<UUID>` entries were **not** touched: they keep
whatever wallpaper they had. So the documented "current Space only" limitation still holds
for existing Spaces, but in a milder form than older reports suggest — a Space created
after Yearwall runs inherits the generated wallpaper through `SystemDefault`.

The app therefore also listens for `activeSpaceDidChangeNotification` and re-applies the
cached image, which costs nothing when the Space already shows it (the URL is compared
first).

Not reproduced: the "Show on all Spaces" toggle turning itself off after an automation run,
reported by Shortcuts-based generators. There is no such toggle in the macOS 26 wallpaper
settings pane.

**Still unverified:** a live Space switch was not observed, because the test machine has a
single Space. The `Index.plist` evidence above is what this section is based on. The app
logs `space changed, observed: display N -> <file>` on every switch, so the check is one
Mission Control gesture away.

### Display geometry

The test machine reports a **framebuffer of 4112×2658 on a 3456×2234 panel** (a scaled
HiDPI mode). `CGDisplayMode.pixelWidth/pixelHeight` returns the framebuffer, not the panel;
`NSScreen.frame × backingScaleFactor` returns the same. The panel size is not reachable
through either.

Yearwall renders at the framebuffer size, which is the resolution the window server
composites the desktop at — any other size adds a resample. `scale` is derived as
`pixelWidth / frame.width` rather than taken from `backingScaleFactor`, because on
non-integral scaled modes the two disagree and the point-based insets would land in the
wrong place.

**Still unverified:** two displays of different resolutions. The code iterates
`NSScreen.screens`, renders per display and puts the display ID and pixel size in each file
name, but only one display was attached.

### The wallpaper cache grows without bound

`~/Library/Application Support/com.apple.wallpaper` was already **457 MB** on the test
machine before Yearwall ran. macOS keeps a copy of every image ever set and does not prune
it.

Yearwall prunes its own output: the newest 7 days survive, and within a kept day only the
newest render per surface (display × resolution × appearance), so a day of fiddling with
settings does not leave a file per change. Files it did not generate are never parsed and
never deleted.

`WallpaperCache` carries a `TODO` about offering to clean the system cache. It is
deliberately not implemented in v0: it needs proof that a file is unreferenced by the
current configuration plus an explicit opt-in.

## Acceptance criteria

| # | Criterion | Status |
| --- | --- | --- |
| 1 | `swift build && swift run` launches a menu bar app with no Dock icon | Verified. `LSUIElement` is embedded as a `__TEXT,__info_plist` section of the bare binary (`otool -l` confirms), plus `setActivationPolicy(.accessory)`. |
| 2 | Wallpaper changes within 2s of launch | Verified: 92–130 ms end to end on a 4112×2658 canvas. |
| 3 | Rendered at the display's true pixel dimensions | Verified — see the display geometry note above for what "true" resolves to. |
| 4 | Two displays of different resolutions | **Not verified**, one display available. |
| 5 | Next day + Refresh now → one more filled element | Covered by `testEachDayAddsInk`, which measures ink coverage on the rendered bitmap. Not exercised by moving the system clock. |
| 6 | Same date → byte-identical PNG | Verified on encoded bytes, both patterns, repeated renders. |
| 7 | Desktop icon labels stay legible on the right | The quiet zone was removed on the owner's instruction; legibility now rests on the 20% contrast cap. |
| 8 | Unit tests for `TimeModel` and RNG determinism | Leap years, year rollover, both DST boundaries, a full DST year, time-zone-dependent day keys, future birth date, exceeded lifespan, missing birth date, splitmix64 golden vectors, FNV-1a stability. |
| 9 | ≤ 7 PNGs after 10 day changes | Verified by test, and by the same-day pruning rule. |
| 10 | README documents observed Spaces behaviour | This section. |

## Non-goals in v0

Goal countdown and journey modes, sandboxing and App Store packaging, iCloud sync,
export, animated wallpapers, and any platform other than macOS.

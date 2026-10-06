# Architecture

Five modules. The pattern engine knows nothing about AppKit, files, or the desktop.

| Module | Depends on | Responsibility |
| --- | --- | --- |
| `TimeModel` | — | `ProgressCalculator` turns a `Date` into a `Progress`. Pure values, explicit `Calendar` and `TimeZone`. |
| `PatternEngine` | `TimeModel`, CoreGraphics | `WallpaperConfig`, `Theme`, `CompositionBudget`, `CanvasSpec`, `Composition`, `SeededRNG`, the `Pattern` protocol and the patterns. |
| `Renderer` | `PatternEngine` | `render(config:progress:canvas:)` → `CGImage` → PNG on disk. Pure function of its three arguments. |
| `WallpaperService` | `Renderer`, AppKit | `ConfigStore`, screens, scheduling, `NSWorkspace`, the file cache. |
| `Updater` | — | Daily check of GitHub releases, download, verification, in-place install. |

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
  intensity. Anything under about 0.2 reads as nothing: `#333` on `#000`.
* **Safe insets** — 40pt for the menu bar (covers notched Macs), 100pt for the Dock,
  5% side margins. Expressed in points and multiplied by the canvas scale.

Today is drawn as an ordinary filled mark. `ResolvedTheme.accent` and
`CompositionBudget.accentContrast` stay in the API for modes that will want a highlight.
Contrast is uniform across the canvas: desktop icon labels stay readable through the
contrast cap and the palette alone.

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

Cleaning the system cache is not implemented: it needs proof that a file is unreferenced
by the current configuration plus an explicit opt-in.

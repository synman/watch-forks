# watch-forks

Live fork & thread monitor for macOS — both a terminal app and a menu bar widget.

`watch-forks` groups every running process by parent PID, surfaces which ancestors are doing the most forking (or burning the most CPU), and gives you a fork-bomb early-warning signal right in your menu bar.

Two tools ship together, sharing one data-collection core:

- **`watch-forks`** — a terminal app, like `top` but for fork counts and per-PID thread counts. Refreshes in place using an alternate screen buffer (same approach as `top` / `htop` / `less`), so it never pollutes scrollback no matter how many rows you ask for.
- **`watch-forks-menubar`** — a macOS menu bar widget that surfaces the same data live in the status bar. The title shows total processes, total CPU, and a trend arrow; the drop-down lists the top-N offenders with per-process actions (SIGTERM, SIGKILL, Copy PID, Show in Activity Monitor).

The menubar dynamically imports the CLI's helpers via `importlib.machinery.SourceFileLoader`, so a change in `watch-forks` propagates to both.

## Why?

macOS's launchd sits at PID 1 as the ancestor of every user process. When something is misbehaving — runaway shell loops, a fork bomb, a node process leaking workers — the symptoms surface as "huh, I have 800 processes now" without an obvious culprit. `watch-forks` rolls children up by parent PID so you can spot the offender at a glance.

## Features

### `watch-forks` (CLI)

- Top-N rows by fork count, refreshed every N seconds
- Smart process names — strips `python3` / `node` interpreter prefixes, surfaces `npm exec` / `npx` package names, resolves `claude --name <scope>`
- tmux session names appended to the tmux row (when tmux is installed)
- Alternate screen buffer in loop mode → no scrollback pollution, header always visible, terminal contents restored on exit
- Auto-caps displayed rows to `terminal_lines - 2` in loop mode so the header stays pinned
- `--once` mode for piping / scripting

### `watch-forks-menubar` (macOS menu bar)

A first-class status-bar app built on `NSPopover` + a custom `NSViewController`. The dropdown is a hand-rolled view hierarchy, not an `NSMenu` — so every row carries real graphics: SF Symbol severity glyphs, the process's actual app icon (via `NSWorkspace.iconForFile:`), a live anti-aliased sparkline of fork history, a heat-graded fill gauge, and a CPU percentage. The header is a three-panel multi-sparkline overview of total CPU, total processes, and fork rate over the rolling window.

#### Menu bar title

`❄️ 1234 / 567% ↑` — severity emoji · total procs · total CPU% · trend arrow. The status item is pinned to a fixed width so it doesn't reflow as the digits change.

- **Rate-based severity** with hysteresis (❄️ cold / 🌡️ warm / 🔥 hot) — driven by the process-count rate of change over a 5-minute rolling window; `hot` can only fall to `warm`, never directly to `cold`.
- **CPU trend indicator** (↑ ↓ →) with asymmetric hysteresis — enters rising/falling on a 15% sample-to-sample delta, exits only on an 8% opposite-direction reversal, so noise doesn't flap the icon.

#### Popover content

- **Three-panel header overview** — CPU, PROCS, and RATE side by side, each with a big current value, a tinted SF Symbol severity glyph, and a real `NSBezierPath` sparkline of the metric's last ~48 samples.
- **Per-row rich view** — SF Symbol severity badge · process app icon · name · live per-PID sparkline · heat-graded colored gauge (blue → orange → red) · subtree-accumulated CPU%.
- **Hover state** — rows tint with the system accent color on mouseover via `NSTrackingArea`.
- **Light/dark mode reactive** — all colors are dynamic `NSColor.system*Color` semantics; `NSApplicationDidChangeEffectiveAppearanceNotification` triggers a redraw of all custom-drawn views.
- **Live gauge updates** — `HeatGaugeView` repaints its heat-graded fill in the same tick the data changes (negligible deltas are skipped to avoid pointless repaints).
- **Right-click context menu per row** — Copy PID, Show in Activity Monitor, Send SIGTERM (15), Send SIGKILL (9) with floating confirmation dialogs.
- **Header row** shows live PID 1 (launchd) stats — `🔥 launchd · 824 forks · 8 threads · 1234.5% CPU`. PID 1 is always filtered from the process rows below so the bar scale isn't dominated by launchd's enormous fork count.
- **Subtree-accumulated CPU%** on every row (each row's CPU = its own + all descendants), computed via iterative post-order traversal of the ppid tree.
- **Auto-sizing popover** — height snaps to the active row count, capped at ~26 rows; scroll if more.
- **Scroll-to-top on every open** — the row list always starts at row 1, no matter where it was when last closed.
- **Outside-click dismisses** the popover. Click in any other app or the desktop and the popover closes.
- **Drag-to-detach** — grab any non-control region of the popover and drag away from the menu bar to morph it into a floating window that survives outside clicks. Close the window's red dot to return to popover mode.

#### Settings + lifecycle

- **Configurable refresh interval** — `Manual` (no timer, refresh-on-demand) / `0.25s` / `0.5s` / `1s` / `2s` / `5s` / `10s` / `30s`.
- **Top N** — `5` / `10` / `15` / `20` / `25` / `50` / `Max` rows (`Max` = every process, no cap; the popover scrolls).
- **Sort dimension** — by forks, CPU%, name, or tree (descendancy order: DFS of the ppid tree, siblings by PID, names indented by depth).
- **Settings persisted atomically** to `~/Library/Application Support/watch-forks-menubar/settings.json` (tempfile + rename).
- **Start-at-login toggle** writes a LaunchAgent plist to `~/Library/LaunchAgents/com.shellware.watch-forks-menubar.plist`.
- **"Open full table in Terminal…"** launches `watch-forks` in a new Terminal window.

## Install

### Prerequisites

- macOS (no Linux support — `watch-forks` uses BSD-style `ps -eM` and the menubar requires AppKit / PyObjC)
- Python 3.10+
- Optional: `tmux` (when installed, the menubar will append session names to the tmux row)

### Clone and link

```bash
git clone https://github.com/synman/watch-forks.git
cd watch-forks

# Install Python deps for the menubar (rumps + pyobjc).
# watch-forks (the CLI) is stdlib-only and needs nothing.
pip install -r requirements.txt

# Symlink into ~/bin (or copy if you prefer).
mkdir -p ~/bin
ln -s "$PWD/watch-forks"          ~/bin/watch-forks
ln -s "$PWD/watch-forks-menubar"  ~/bin/watch-forks-menubar
```

### A note on the Python environment

`watch-forks-menubar` needs the [`rumps`](https://github.com/jaredks/rumps) + PyObjC stack. The default shebang is `#!/usr/bin/env python3`, so a **foreground** launch (`~/bin/watch-forks-menubar &`) picks up whichever `python3` is on your `PATH`. If you keep `rumps` in a virtualenv (recommended), launch it from a shell where that venv is active / on `PATH` (or replace the shebang with the venv's absolute path, e.g. `#!/Users/you/.virtualenvs/yourenv/bin/python3`).

**Start at login just works regardless of your `PATH`.** When you toggle "Start at login", the widget pins the exact interpreter currently running it (`sys.executable`) into the LaunchAgent's `ProgramArguments` — so launchd invokes that same rumps-capable interpreter directly, no shell or shebang editing needed. Toggle it from a running instance that already has the deps and it carries over to every login.

`watch-forks` (the CLI) is stdlib-only and runs under any Python 3.10+.

### Running as a macOS `.app`

The menubar widget can be packaged as a standard macOS application bundle, which unlocks:

- **Real `CFBundleIdentifier`** — enables `rumps.notification` (currently guarded behind bundle identity)
- **LaunchServices integration** — "Open" from Finder, "Open at Login" Dock integration
- **Dock-hidden by default** — status-bar-only apps have `LSUIElement=true`
- **Foundation for custom icons** — bundle structure supports `AppIcon.icns` in Resources/

#### Build the app bundle

```bash
./build-app-bundle.sh           # Creates build/watch-forks-menubar.app/
./build-app-bundle.sh --install # Build and install to /Applications/
```

#### Launch from the bundle

```bash
# Open with the default launcher
open build/watch-forks-menubar.app

# Launch directly (same as menu bar symlink, but runs under the bundle identity)
./build/watch-forks-menubar.app/Contents/MacOS/watch-forks-menubar

# If installed to /Applications
open /Applications/watch-forks-menubar.app
```

`build-app-bundle.sh` auto-detects a `python3` that can `import rumps` and bakes its **absolute path** into the bundle's `Contents/MacOS/watch-forks-menubar` wrapper at build time — so the bundle launches correctly under LaunchServices regardless of `PATH`. Build it from a shell where your rumps-capable interpreter is on `PATH`, or point at one explicitly:

```bash
WATCH_FORKS_PYTHON=/Users/you/.virtualenvs/yourenv/bin/python3 ./build-app-bundle.sh --install
```

The build fails fast with an explanatory message if no rumps-capable interpreter is found.

## Usage

### CLI

```bash
watch-forks                  # default: top-25, every 5s
watch-forks -n 50 -i 1       # top-50, every 1 second
watch-forks --once           # one-shot render (no loop, no alt-screen)
```

`Ctrl+C` exits. In loop mode the terminal is restored to whatever was on screen before launch — alt-screen buffer in use.

### Menu bar

Foreground launch (logs to `~/Library/Logs/watch-forks-menubar.log`, rotated at 5 MB × 3):

```bash
~/bin/watch-forks-menubar &
```

Click the menu bar item to open the drop-down. Pick "Start at login" to drop a LaunchAgent into `~/Library/LaunchAgents/com.shellware.watch-forks-menubar.plist` for auto-start at next login.

#### Stopping / restarting

```bash
# Stop a foreground launch
pkill -f watch-forks-menubar

# If running under launchd (Start-at-login enabled):
launchctl kickstart -k "gui/$(id -u)/com.shellware.watch-forks-menubar"   # restart
launchctl bootout    "gui/$(id -u)/com.shellware.watch-forks-menubar"     # unload
```

## Architecture notes

A few details worth flagging if you're reading the source:

### CLI

- **Alternate screen buffer (`\x1b[?1049h`)** is critical for the CLI loop mode. Without it, `\x1b[2J\x1b[H` only clears the visible viewport — when the frame exceeds the terminal's row count, excess rows scroll into scrollback every iteration, the header is permanently scrolled off-screen, and the in-place refresh appears broken. With alt screen, the refresh works cleanly no matter how many rows you ask for.

- **Auto-cap to terminal height** in loop mode — displayed rows are clamped to `terminal_lines - 2` so the header stays pinned. `--once` and non-TTY (pipe/file) cases get the full `-n` rows.

- **`tmux` resolution under launchd** explicitly looks in `/opt/homebrew/bin` and `/usr/local/bin` before falling back to `PATH`. LaunchAgents inherit only `/usr/bin:/bin:/usr/sbin:/sbin`, so a naive `subprocess.run(["tmux", ...])` raises `FileNotFoundError` and the tmux row drops its session-name suffix when running under "Start at login".

### Menubar widget

- **`NSPopover` + custom `NSViewController`** is the architectural backbone. `NSMenu` would constrain rows to text-only items inside the system's menu font — `NSPopover` hosts a hand-rolled view hierarchy where every row is a custom composite `NSView` with full graphics primitives, animation, and per-row hover state. The status item still uses `NSStatusItem` (rumps gives us this); clicking it toggles the popover via `togglePopover_`.

- **Fixed `NSStatusItem` width** (`setLength_(175.0)`) — without this, the menu bar button reflows by 1–2 pixels every time digits or the trend arrow change in the title. `NSPopover` anchors to the button, so any shift dragged the entire popover left or right per refresh — visible as a horizontal "shutter." Pinning the width holds the anchor stable.

- **`NSTimer` in `NSRunLoopCommonModes`** for the popover refresh. `NSRunLoopDefaultMode` is suspended while menu tracking is active; common modes cover both default and `NSEventTrackingRunLoopMode`, so the tick keeps firing whether the popover is open or closed. Implementation drops out of rumps's `Timer` to a raw `NSTimer` with a small `NSObject` subclass as target.

- **Custom NSView subclasses** drive the rich rendering: `RichRowView` (composite row), `SparklineView` (per-row fork-history sparkline), `HeatGaugeView` (heat-graded colored gauge), `HeaderOverviewView` (the three-panel header container), `SparklinePanelView` (one panel: caption + big value + glyph + sparkline). All use semantic `NSColor.system*Color` so dark mode just works.

- **`intrinsicContentSize` on `RichRowView`** is required because `NSStackView` ignores `initWithFrame_` and uses Auto Layout — without an intrinsic size override, rows collapse to zero height and pile at the bottom of the scroll view.

- **Auto-collapsing scroll view** — when the row count is less than the cap, `syncRowCount_` recomputes the scroll view height and the popover's `contentSize` so the popover snaps to fit content. Forced overlay scroller style (`NSScrollerStyleOverlay`) so the vertical scroller doesn't reserve content width.

- **Outside-click dismissal** uses an `NSEvent` global mouse-down monitor installed when the popover shows. The monitor checks `popover.isShown() and not popover.isDetached()` so clicks aren't propagated to detached-window state.

- **Drag-to-detach** uses Apple's default `NSPopoverBehaviorSemitransient` + `popoverShouldDetach_` returning `True`. Tried implementing a custom `detachableWindowForPopover_` for a properly-titled window (avoiding AppKit's translucent-X-overlay-content default), but every variant fought AppKit's internal popover-detach state machine — content view transfer broke the reopen path. Settled on the default; the popover root has 30pt of top inset so AppKit's overlay traffic-light buttons sit over empty space instead of the CPU sparkline.

- **Subtree-accumulated CPU%** is computed via iterative post-order traversal of the ppid tree (no recursion — depth-safe). The accumulator value for launchd (PID 1) equals Σ all `pcpu` by construction, since launchd is the ancestor of every user process on macOS.

- **Severity hysteresis** is rate-based, not absolute. The process-count severity reflects rolling rate of change over a 5-minute window with sticky transitions. The CPU trend uses asymmetric thresholds (15% to enter, 8% reverse to exit) — picked after sub-second refresh rates exposed every smaller pair as producing a transition on every tick.

- **Lifetime CPU caveat (`ps` limitation)** — `pcpu` from `ps -eo pcpu` is the lifetime average since process start, not current usage. Long-running daemons that occasionally burst (CrowdStrike Falcon, etc.) appear idle at 0.0% even when Activity Monitor shows real usage. Matching Activity Monitor for those processes requires either elevated privileges or Apple's private coalition APIs, neither of which is in reach for a user-space tool.

- **PyObjC bridge gotcha** — methods like `update_` on an `NSView` subclass get auto-bridged to ObjC selectors (`update:` expects 1 arg). Helper methods need to either be renamed without leading/trailing underscores or carry the `@objc.python_method` decorator to opt out of bridging. Several latent bugs surfaced once the bundle started actually loading the classes under launchd (the earlier `ast.parse` validation didn't catch them).

## License

MIT — see [LICENSE](LICENSE).

## Author

Shell Shrader · [@synman](https://github.com/synman)

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

Title format: `❄️ 1234 / 567% ↑` — severity emoji · total procs · total CPU · trend.

- **Rate-based severity** with hysteresis (❄️ cold / 🌡️ warm / 🔥 hot) — driven by process-count rate-of-change over a 30s window; `hot` can only fall to `warm`, never directly to `cold`
- **CPU trend indicator** (↑ ↓ →) with asymmetric hysteresis — enters rising/falling on a 3% delta, exits only on a 1% reversal, so noise doesn't flap the icon
- **Live refresh while the menu is open** — uses `NSTimer` in `NSRunLoopCommonModes` so the timer fires during menu tracking
- Per-process submenu: PID, forks, threads, self-CPU, subtree-CPU, decoded ps STAT, plus actions (Copy PID, Show in Activity Monitor, SIGTERM, SIGKILL with confirmation)
- Header shows live PID 1 (launchd) stats — `🔥 launchd · 824 forks · 8 threads · 1234.5% CPU`
- Subtree-accumulated CPU% on every row (each row's CPU = its own + all descendants)
- Discrete log-scaled bar showing each row's contribution to the active sort dimension
- Configurable refresh interval (Manual / 1s / 2s / 5s / 10s / 30s), top-N (5–50), sort by forks or CPU%
- Settings persisted atomically to `~/Library/Application Support/watch-forks-menubar/settings.json`
- Start-at-login toggle (writes a LaunchAgent plist to `~/Library/LaunchAgents/`)
- "Open full table in Terminal…" launches `watch-forks` in a new Terminal window

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

`watch-forks-menubar` needs the [`rumps`](https://github.com/jaredks/rumps) + PyObjC stack. Default shebang is `#!/usr/bin/env python3`, so it picks up whichever `python3` is on your `PATH` at launch.

If you keep `rumps` in a virtualenv (recommended), either activate the venv before launching, or replace the shebang with the venv's absolute path:

```python
#!/Users/you/.virtualenvs/yourenv/bin/python3
```

Doing the latter also makes "Start at login" work without venv activation — the LaunchAgent invokes the script directly, with no shell to activate anything.

`watch-forks` (the CLI) is stdlib-only and runs under any Python 3.10+.

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

- **Alternate screen buffer (`\x1b[?1049h`)** is critical for the CLI loop mode. Without it, `\x1b[2J\x1b[H` only clears the visible viewport — when the frame exceeds the terminal's row count, excess rows scroll into scrollback every iteration, the header is permanently scrolled off-screen, and the in-place refresh appears broken. With alt screen, the refresh works cleanly no matter how many rows you ask for.

- **`NSTimer` in `NSRunLoopCommonModes`** for the menubar refresh. `NSRunLoopDefaultMode` is *suspended* while a menu is being tracked (open), which means rumps's built-in `Timer` freezes the moment you click the menu bar item. Common modes covers both default mode and `NSEventTrackingRunLoopMode`, so the refresh keeps firing while the menu is open. This required dropping out of rumps's `Timer` to a raw `NSTimer` with a small NSObject subclass as target.

- **Menu items mutate in place** rather than clear-and-rebuild. NSMenu reflects the same NSMenuItem instances live; clearing the menu during a refresh would close it mid-open. The widget allocates a fixed pool of 50 row items (max `top` value) and `setHidden_` the spare slots.

- **NSMenu state-column suppression** (`setShowsStateColumn_(False)`) collapses the fixed-width checkmark gutter on the top-level menu so rows render flush against the popup's left edge. Submenus (which need radio dots for Interval / Top N / Sort by) are separate `NSMenu` instances, so they keep their state column.

- **Subtree-accumulated CPU%** is computed via iterative post-order traversal of the ppid tree (no recursion — depth-safe). The accumulator value for launchd (PID 1) equals Σ all `pcpu` by construction, since launchd is the ancestor of every user process on macOS.

- **Severity hysteresis** is rate-based, not absolute. The icon reflects the rolling rate of change over a 30-second window with sticky transitions. The CPU trend uses asymmetric thresholds (3% to enter, 1% reverse to exit) for the same anti-flap reason.

- **`tmux` resolution under launchd** explicitly looks in `/opt/homebrew/bin` and `/usr/local/bin` before falling back to `PATH`. LaunchAgents inherit only `/usr/bin:/bin:/usr/sbin:/sbin`, so a naive `subprocess.run(["tmux", ...])` raises `FileNotFoundError` and the tmux row drops its session-name suffix when running under "Start at login".

## License

MIT — see [LICENSE](LICENSE).

## Author

Shell Shrader · [@synman](https://github.com/synman)

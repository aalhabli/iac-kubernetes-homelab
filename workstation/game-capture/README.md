# Game Capture

Captures screenshots from strategy games on the workstation so an agent can review a session afterwards and talk through what happened. This half runs entirely on the workstation and has no homelab dependency; the push to Hermes is wired separately once the agent host exists.

## How it works

A systemd user timer fires every two minutes. Each run asks Hyprland for the focused window, matches its class and title against a list of games, and captures a frame only if one matches. Frames are downscaled to 1920 px wide and written as JPEG, roughly 300 KB each.

A keybinding captures on demand for the moments that matter — the decision you were unsure about, the battle that went wrong. Those frames are marked in the filename and are never deduplicated. They are the most useful input to a review, because they are the ones you flagged yourself.

Alongside each day's frames is a `session.jsonl` recording the timestamp, window class, and window **title** for every capture. The title is worth having: grand strategy games put the in-game date or turn number there, which gives a review chronology without the model having to read it off the pixels.

```
~/Pictures/game-captures/
└── hoi4/
    └── 2026-08-15/
        ├── 201134.jpg
        ├── 201334.jpg
        ├── 201412-marked.jpg
        └── session.jsonl
```

### Frames that do not change are dropped

A game left paused or sitting behind another window would otherwise produce a wall of identical frames. Each capture is compared against the last kept one and discarded if it is visually unchanged.

The comparison is on pixels, not bytes. Hashing the file does not work here — a clock in the status bar or a single animated sprite changes the hash while the frame is, for review purposes, the same picture. Measured on this machine, a status bar clock tick alone produces an RMSE of about 0.036, so the default threshold of `0.01` sits well below it. The intent is to catch a genuinely frozen screen rather than to judge whether a change was interesting. Set `GAME_CAPTURE_MIN_CHANGE=0` to keep everything.

## Install

```bash
./install.sh
```

Symlinks the script into `~/.local/bin`, copies `games.conf` to `~/.config/game-capture/` if it is not already there, links the units into `~/.config/systemd/user/`, and enables the timer. Re-running it will not overwrite local edits to `games.conf`.

Add the keybinding to `~/.config/hypr/bindings.lua`:

```lua
-- Mark the current moment for the game review
o.bind("SUPER + SHIFT + M", "Mark game moment", "game-capture --now")
```

`SUPER + SHIFT + M` is unbound in the stock Omarchy set. A SUPER combination is deliberate — games grab plain and function keys, and `PRINT` is already Omarchy's screenshot and `F12` is Steam's. Validate with `hyprctl reload && hyprctl configerrors`.

## Adding a game

Proton titles present a window class of `steam_app_<appid>`, which is the stable identifier. To find it, focus the game and run:

```bash
game-capture --which
```

Then add a line to `~/.config/game-capture/games.conf`. Each line is a slug and an extended regex, matched case-insensitively against both the class and the title:

```
hoi4    hoi4|hearts.?of.?iron
```

The slug becomes the output directory name.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `GAME_CAPTURE_CONFIG` | `~/.config/game-capture/games.conf` | game list |
| `GAME_CAPTURE_DIR` | `~/Pictures/game-captures` | output root |
| `GAME_CAPTURE_WIDTH` | `1920` | downscale width |
| `GAME_CAPTURE_QUALITY` | `85` | JPEG quality |
| `GAME_CAPTURE_MIN_CHANGE` | `0.01` | RMSE below which a frame is dropped; `0` disables |

Set these in `~/.config/systemd/user/game-capture.service.d/override.conf` to change them for the timer.

## Cost and volume

A two hour session at one frame per two minutes is about 60 frames, roughly 18 MB. That is negligible on disk and the reason the interval is not tighter is the review, not the storage: every frame sent to a vision model is billed, and 60 frames is already a substantial prompt. The review job samples rather than sending everything, and always includes the marked frames.

## Checks

Verified on 2026-08-15:

- Capture produces a 1920x1080 JPEG at about 300 KB from a 3840x2160 display.
- A visually unchanged frame is dropped; a changed frame is kept; `--now` overrides the drop.
- `GAME_CAPTURE_MIN_CHANGE=0` disables dropping.
- Two captures within the same second do not overwrite each other.
- Every `file` path in `session.jsonl` exists on disk.
- A non-matching focused window produces no capture on the timer, and lands under `unsorted/` for `--now`.

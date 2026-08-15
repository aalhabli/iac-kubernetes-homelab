#!/usr/bin/env bash
#
# Symlink the capture pipeline into the user session. Symlinks rather than
# copies, so a `git pull` updates the installed version and the repo stays the
# single source of truth.
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
CFG="$HOME/.config/game-capture"
UNITS="$HOME/.config/systemd/user"

mkdir -p "$BIN" "$CFG" "$UNITS"

chmod +x "$SRC/game-capture"
ln -sfn "$SRC/game-capture" "$BIN/game-capture"

# The game list is config the user edits, so it is copied once and then left
# alone. Re-running this script will not clobber local edits.
if [ -e "$CFG/games.conf" ]; then
  echo "keeping existing $CFG/games.conf"
else
  cp "$SRC/games.conf" "$CFG/games.conf"
  echo "installed $CFG/games.conf"
fi

ln -sfn "$SRC/game-capture.service" "$UNITS/game-capture.service"
ln -sfn "$SRC/game-capture.timer"   "$UNITS/game-capture.timer"

systemctl --user daemon-reload
systemctl --user enable --now game-capture.timer

echo
systemctl --user status game-capture.timer --no-pager | head -5
echo
echo "Next: focus a game and run 'game-capture --which' to confirm its window class."

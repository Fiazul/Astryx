#!/usr/bin/env bash
# Build a DOUBLE-PRECISION (64-bit world coordinates) Godot editor for Astryx.
#
# Why: double precision is a COMPILE-TIME engine flag (`precision=double`) — it is
# NOT a project setting. The project runs unchanged under it, but every world
# coordinate becomes a 64-bit float, so the "warp wall" jitter that appears millions
# of units from the origin disappears. That's what makes a TRUE-scale solar system
# (real Earth size, real AU/ly distances, free-flight interstellar) actually stable.
#
# Usage:   tools/build_godot_double.sh [godot-tag]
#   e.g.   tools/build_godot_double.sh 4.6.3-stable
#
# Takes ~20-40 min on first build. Re-running is incremental (fast).
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_TAG="${1:-4.6.3-stable}"
SRC="${GODOT_SRC:-$HOME/godot-src}"
JOBS="$(nproc)"

echo "==> [1/4] Build deps (sudo apt)…"
sudo apt-get update
sudo apt-get install -y scons pkg-config build-essential \
  libx11-dev libxcursor-dev libxinerama-dev libgl1-mesa-dev libglu1-mesa-dev \
  libasound2-dev libpulse-dev libudev-dev libxi-dev libxrandr-dev libwayland-dev

echo "==> [2/4] Clone Godot $GODOT_TAG -> $SRC …"
if [ ! -d "$SRC" ]; then
  git clone --depth 1 --branch "$GODOT_TAG" https://github.com/godotengine/godot.git "$SRC"
fi

echo "==> [3/4] Compile editor with precision=double (~20-40 min)…"
( cd "$SRC" && scons platform=linuxbsd target=editor precision=double -j"$JOBS" )

BIN="$(ls -1 "$SRC"/bin/godot.linuxbsd.editor.*double* 2>/dev/null | head -1)"
echo "==> [4/4] Done."
echo
echo "Double-precision editor:  $BIN"
echo "Run Astryx under it:      \"$BIN\" --path \"$PROJECT_DIR\""
echo
echo "Tip: once it runs cleanly, start ratcheting the scale toward real —"
echo "see SCALE_64BIT_PLAN.md for the exact dials to turn."

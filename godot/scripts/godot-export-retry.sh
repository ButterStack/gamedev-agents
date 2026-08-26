#!/usr/bin/env bash
#
# Bounded-retry wrapper around a Godot export. Mobile exports fail on transient
# dependency resolution often enough to be worth retrying, and rarely enough
# that an unbounded loop just hides a real failure - so this retries a fixed
# number of times with backoff and then gives up loudly.
#
#   godot-export-retry.sh <preset> <output-path> [--debug] [--attempts N]
#
# GODOT may be set to the engine binary; defaults to `godot` on PATH.
set -uo pipefail

GODOT="${GODOT:-godot}"
ATTEMPTS=3
MODE="--export-release"
PRESET=""
OUT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --debug)    MODE="--export-debug"; shift ;;
    --attempts) ATTEMPTS="${2:?--attempts needs a number}"; shift 2 ;;
    -h|--help)  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "unknown flag: $1" >&2; exit 2 ;;
    *)          if [ -z "$PRESET" ]; then PRESET="$1"; else OUT="$1"; fi; shift ;;
  esac
done

[ -n "$PRESET" ] && [ -n "$OUT" ] || { echo "usage: godot-export-retry.sh <preset> <output-path> [--debug] [--attempts N]" >&2; exit 2; }
[ -f project.godot ] || { echo "no project.godot in $(pwd) - run from the project root" >&2; exit 1; }

command -v "$GODOT" >/dev/null 2>&1 || { echo "engine binary not found: $GODOT (set GODOT=)" >&2; exit 1; }
echo "engine : $("$GODOT" --version 2>/dev/null | head -1)"
echo "preset : $PRESET"
echo "mode   : $MODE"
echo "output : $OUT"

mkdir -p "$(dirname "$OUT")"

attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
  echo "--- attempt $attempt/$ATTEMPTS ---"
  # NB: no `| tee` here. A pipe would make the exit status tee's, not Godot's,
  # which is exactly the trap that made a whole CI gate suite unfailable.
  if "$GODOT" --headless "$MODE" "$PRESET" "$OUT"; then
    echo "EXPORT OK -> $OUT"
    echo "NOTE: this export is the only evidence that packing is correct; an editor or headless run against the project directory does not prove it."
    exit 0
  fi
  code=$?
  echo "attempt $attempt failed (exit $code)"
  attempt=$((attempt + 1))
  [ "$attempt" -le "$ATTEMPTS" ] && sleep $(( attempt * 5 ))
done

echo "EXPORT FAILED after $ATTEMPTS attempts" >&2
exit 1

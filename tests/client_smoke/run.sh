#!/usr/bin/env bash
# Client smoke test: boots a server, then the real desktop client under a virtual display,
# logs in, and takes screenshots of the login screen and the world at noon and at midnight
# (AIMMO_TIME_OF_DAY pins the sky). Fails on any script error in either process, or if the
# night shot is not clearly darker than the day shot (tests/client_smoke/image_stats.gd).
# Then two shots from the action camera (tests/client_smoke/camera_shots.gd): reticle centred and
# your character left of centre, and backed against a hill without clipping into the ground.
# Needs xvfb-run and Mesa (software OpenGL).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${1:-$REPO/build/client-smoke}"
GODOT="${GODOT:-godot}"
PORT="${AIMMO_SMOKE_PORT:-7801}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)" # Godot changes into the project folder, so every path it gets must be absolute
export AIMMO_PORT="$PORT" AIMMO_DATA_DIR="$OUT/data" AIMMO_STOP_FILE="$OUT/stop"
rm -f "$AIMMO_STOP_FILE"

"$GODOT" --headless --path "$REPO/game" -- --server > "$OUT/server.log" 2>&1 &
SERVER=$!
stop_server() {
  touch "$AIMMO_STOP_FILE"
  for _ in $(seq 1 60); do kill -0 "$SERVER" 2>/dev/null || return 0; sleep 0.5; done
  echo "server did not stop within 30s, killing it"; kill -9 "$SERVER" 2>/dev/null || true
}
trap stop_server EXIT
for _ in $(seq 1 100); do grep -q "listening" "$OUT/server.log" && break; sleep 0.2; done

run_client() {
  local label="$1"; shift
  timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
    --path "$REPO/game" -- "$@" > "$OUT/client-$label.log" 2>&1 || true
}
run_client login --screenshot="$OUT/login.png" --quit-after=5
AIMMO_TIME_OF_DAY=0.5 run_client world --screenshot="$OUT/world.png" --quit-after=8 --name=SmokeTester --password=smoke123 --address=127.0.0.1:$PORT --autoconnect
AIMMO_TIME_OF_DAY=0.0 run_client night --screenshot="$OUT/world-night.png" --quit-after=8 --name=SmokeTester --password=smoke123 --address=127.0.0.1:$PORT --autoconnect
camera_fail=0
AIMMO_TIME_OF_DAY=0.5 timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
  --path "$REPO/game" -s tests/client_smoke/camera_shots.gd -- --shots="$OUT" --name=SmokeCamera --password=smoke123 \
  --address=127.0.0.1:$PORT --autoconnect > "$OUT/client-camera.log" 2>&1 || camera_fail=1

fail=$camera_fail
[ $camera_fail -eq 0 ] || { echo "camera shots FAILED:"; grep "\[camera\]" "$OUT/client-camera.log" || true; }
for f in login.png world.png world-night.png camera.png camera-hill.png; do
  [ -s "$OUT/$f" ] || { echo "missing screenshot $f"; fail=1; }
done
if [ $fail -eq 0 ]; then
  "$GODOT" --headless --path "$REPO/game" -s tests/client_smoke/image_stats.gd -- \
    --day="$OUT/world.png" --night="$OUT/world-night.png" > "$OUT/brightness.log" 2>&1 || fail=1
  cat "$OUT/brightness.log"
fi
if grep -hE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT"/*.log; then fail=1; fi
[ "$(grep -c "SmokeTester logged in" "$OUT/server.log")" -ge 2 ] || { echo "client did not log in for both world shots"; fail=1; }
# The camera run walks its character to a slope, so it plays a separate character and the
# day/night shots above always start at spawn, even when a local run reuses the data folder.
grep -q "SmokeCamera logged in" "$OUT/server.log" || { echo "client did not log in for the camera shots"; fail=1; }
[ $fail -eq 0 ] && echo "client smoke test passed, screenshots in $OUT" || { echo "client smoke test FAILED"; cat "$OUT"/*.log; }
exit $fail

#!/usr/bin/env bash
# Client smoke test: boots a server, then the real desktop client under a virtual display,
# logs in, and takes screenshots of the login screen and the world. Fails on any script
# error in either process. Needs xvfb-run and Mesa (software OpenGL).
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
run_client world --screenshot="$OUT/world.png" --quit-after=8 --name=SmokeTester --password=smoke123 --address=127.0.0.1:$PORT --autoconnect

fail=0
for f in login.png world.png; do
  [ -s "$OUT/$f" ] || { echo "missing screenshot $f"; fail=1; }
done
if grep -hE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT"/*.log; then fail=1; fi
grep -q "SmokeTester logged in" "$OUT/server.log" || { echo "client never logged in"; fail=1; }
[ $fail -eq 0 ] && echo "client smoke test passed, screenshots in $OUT" || { echo "client smoke test FAILED"; cat "$OUT"/*.log; }
exit $fail

#!/usr/bin/env bash
# Client smoke test: boots a server, then the real desktop client under a virtual display,
# logs in, and takes screenshots of the login screen and the world at noon and at midnight
# (AIMMO_TIME_OF_DAY pins the sky). Fails on any script error in either process, or if the
# night shot is not clearly darker than the day shot (tests/client_smoke/image_stats.gd).
# Then two shots from the action camera (tests/client_smoke/camera_shots.gd): reticle centred and
# your character left of centre, and backed against a hill without clipping into the ground.
# Then the render budget (tests/client_smoke/render_stats.gd + render_budget.py, art bible
# section 7): draw calls, primitives, world materials and texture memory at the noon and night
# spawn shots, written to render_stats.json and failed over the ceilings or the 20% ratchet in
# tests/client_smoke/render_baseline.json.
# The Low Graphics preset is measured too (with the Low settings.cfg below), and must be cheaper
# than noon on Medium: a lighter world, fewer primitives, no more draw calls.
# Then the Emberlight style check (tests/client_smoke/style_check.gd, art bible "Colour"): ember
# share, neon, warm/cool and a not-black, not-grey night on the noon and night shots, against
# tests/client_smoke/style_baseline.json, written to style_stats.json, plus contact_sheet.html
# of every screenshot for the CI artifact.
# The F1 controls, a haul toast with its XP floater, and the Low Graphics preset are shot too
# (client's test hooks): Low is styled against the noon baseline (the look must hold on Low),
# and the two HUD shots get the hard rules only (ember stays rare, the frame is not black).
# Then the feedback check (tests/client_smoke/feedback_check.gd, design bible "Fun comes first"):
# a fresh character presses E on an ash and a stone, then crafts a stone axe at the workbench,
# and every press must show its bar, toast or window within 100 ms (plus the two frames any
# client needs to draw a server's answer); the times go to feedback.json.
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
# The client's own shot hooks, so the contact sheet and the style check cover them: the F1
# controls overlay, a haul toast with its "+10 Felling" XP floater, and the world on the Low
# Graphics preset. Low is a saved setting, so that run gets its own user folder (XDG_DATA_HOME)
# with a settings.cfg as the Settings window writes it when you pick Low, and never touches
# the developer's own settings.
AIMMO_TIME_OF_DAY=0.5 run_client controls --screenshot="$OUT/controls.png" --quit-after=8 --open-controls --name=SmokeTester --password=smoke123 --address=127.0.0.1:$PORT --autoconnect
AIMMO_TIME_OF_DAY=0.5 run_client toast --screenshot="$OUT/toast-xp.png" --quit-after=8 --show-toast=ash_wood --show-xp --name=SmokeTester --password=smoke123 --address=127.0.0.1:$PORT --autoconnect
LOW_HOME="$OUT/xdg-low"
rm -rf "$LOW_HOME"; mkdir -p "$LOW_HOME/godot/app_userdata/AiMMO"
printf '[settings]\n\ngraphics_quality=0\nshadow_quality=1\ndraw_distance=400.0\n' > "$LOW_HOME/godot/app_userdata/AiMMO/settings.cfg"
XDG_DATA_HOME="$LOW_HOME" AIMMO_TIME_OF_DAY=0.5 run_client low --screenshot="$OUT/world-low.png" --quit-after=8 --name=SmokeTester --password=smoke123 --address=127.0.0.1:$PORT --autoconnect
camera_fail=0
feedback_fail=0
AIMMO_TIME_OF_DAY=0.5 timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
  --path "$REPO/game" -s tests/client_smoke/camera_shots.gd -- --shots="$OUT" --name=SmokeCamera --password=smoke123 \
  --address=127.0.0.1:$PORT --autoconnect > "$OUT/client-camera.log" 2>&1 || camera_fail=1

# Render budget: its own character, so the camera walk above never moves the spawn view.
for shot in noon:0.5 night:0.0; do
  AIMMO_TIME_OF_DAY="${shot#*:}" timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
    --path "$REPO/game" -s tests/client_smoke/render_stats.gd -- --stats-out="$OUT/render-${shot%%:*}.json" --name=SmokeRender \
    --password=smoke123 --address=127.0.0.1:$PORT --autoconnect > "$OUT/client-render-${shot%%:*}.log" 2>&1 || true
done
# ...and on the Low preset (same noon spawn, Low's own user folder), so "Low is cheaper" has a number.
XDG_DATA_HOME="$LOW_HOME" AIMMO_TIME_OF_DAY=0.5 timeout 120 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
  --path "$REPO/game" -s tests/client_smoke/render_stats.gd -- --stats-out="$OUT/render-low.json" --name=SmokeRender \
  --password=smoke123 --address=127.0.0.1:$PORT --autoconnect > "$OUT/client-render-low.log" 2>&1 || true

# Feedback: a fresh character every run (it must start with an empty pack and no axe),
# after the render shots so the nodes it empties never change what they measure.
AIMMO_TIME_OF_DAY=0.5 timeout 150 xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" --rendering-driver opengl3 --audio-driver Dummy \
  --path "$REPO/game" -s tests/client_smoke/feedback_check.gd -- --out="$OUT/feedback.json" --name="Feel$(date +%s | tail -c 9)" \
  --password=smoke123 --address=127.0.0.1:$PORT --autoconnect > "$OUT/client-feedback.log" 2>&1 || feedback_fail=1

fail=$camera_fail
[ $camera_fail -eq 0 ] || { echo "camera shots FAILED:"; grep "\[camera\]" "$OUT/client-camera.log" || true; }
grep "\[feedback\]" "$OUT/client-feedback.log" || true
[ $feedback_fail -eq 0 ] || { echo "feedback check FAILED"; fail=1; }
for f in login.png world.png world-night.png controls.png toast-xp.png world-low.png camera.png camera-hill.png; do
  [ -s "$OUT/$f" ] || { echo "missing screenshot $f"; fail=1; }
done
if [ $fail -eq 0 ]; then
  "$GODOT" --headless --path "$REPO/game" -s tests/client_smoke/image_stats.gd -- \
    --day="$OUT/world.png" --night="$OUT/world-night.png" > "$OUT/brightness.log" 2>&1 || fail=1
  cat "$OUT/brightness.log"
  "$GODOT" --headless --path "$REPO/game" -s tests/client_smoke/style_check.gd -- \
    --shot=noon="$OUT/world.png" --shot=night="$OUT/world-night.png" --shot=low="$OUT/world-low.png" \
    --shot=controls="$OUT/controls.png" --shot=toast="$OUT/toast-xp.png" \
    --out="$OUT/style_stats.json" --sheet="$OUT/contact_sheet.html" > "$OUT/style.log" 2>&1 || fail=1
  grep "\[style\]" "$OUT/style.log" || true
fi
python3 "$REPO/tests/client_smoke/render_budget.py" --shot noon="$OUT/render-noon.json" \
  --shot night="$OUT/render-night.json" --shot low="$OUT/render-low.json" --out "$OUT/render_stats.json" || fail=1
if grep -hE "SCRIPT ERROR|Parse Error|Compile Error" "$OUT"/*.log; then fail=1; fi
[ "$(grep -c "SmokeTester logged in" "$OUT/server.log")" -ge 5 ] || { echo "client did not log in for all five world shots"; fail=1; }
# The camera run walks its character to a slope, so it plays a separate character and the
# day/night shots above always start at spawn, even when a local run reuses the data folder.
# Godot logs to user://logs, so a log in the Low folder proves that run read its settings there.
ls "$LOW_HOME"/godot/app_userdata/AiMMO/logs/godot*.log > /dev/null 2>&1 || { echo "the Low run did not use its own user folder (no Godot log in $LOW_HOME)"; fail=1; }
grep -q "SmokeCamera logged in" "$OUT/server.log" || { echo "client did not log in for the camera shots"; fail=1; }
[ $fail -eq 0 ] && echo "client smoke test passed, screenshots in $OUT" || { echo "client smoke test FAILED"; cat "$OUT"/*.log; }
exit $fail

#!/bin/sh
# Runs the AiMMO dedicated server. Godot does not handle SIGTERM, so we trap it here and
# ask the server to stop via a stop file; it then saves every character and exits.
set -eu
STOP_FILE="${AIMMO_STOP_FILE:-/tmp/aimmo-stop}"
export AIMMO_STOP_FILE="$STOP_FILE"
rm -f "$STOP_FILE"

godot --headless --path /app/game -- --server &
PID=$!

graceful() {
  echo "[entrypoint] stop requested, asking server to save and exit"
  touch "$STOP_FILE"
  wait "$PID" || true
  exit 0
}
trap graceful TERM INT

wait "$PID"

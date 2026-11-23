#!/bin/bash
# Runs the AiMMO dedicated server.
#
# Shutdown: Godot does not handle SIGTERM, so we trap it here and ask the server to stop via
# a stop file; it then saves every character and exits.
#
# Watchdog: Railway restarts the container only when the process exits, so a server that
# freezes without crashing would stay down until someone noticed. Every few seconds the
# watchdog checks the server still answers a WebSocket handshake (docker/probe.sh). After
# several misses in a row it asks the server to save and stop, then kills it if it can't,
# and the entrypoint exits non-zero so Railway's ON_FAILURE policy starts a fresh one.
#
# Settings (environment):
#   AIMMO_WATCHDOG=off              disable it (it is also off for the ENet transport)
#   AIMMO_WATCHDOG_STARTUP=180      seconds the server may take to start answering at boot
#   AIMMO_WATCHDOG_INTERVAL=20      seconds between probes once it is up
#   AIMMO_WATCHDOG_TIMEOUT=5        seconds one probe waits for an answer
#   AIMMO_WATCHDOG_FAILURES=3       misses in a row before acting
#   AIMMO_WATCHDOG_STOP_WAIT=20     seconds to let it save and stop before killing it
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME_DIR="${AIMMO_GAME_DIR:-/app/game}"
PROBE="${AIMMO_PROBE:-$HERE/probe.sh}"
STOP_FILE="${AIMMO_STOP_FILE:-/tmp/aimmo-stop}"
export AIMMO_STOP_FILE="$STOP_FILE"
rm -f "$STOP_FILE"
WD_FIRED="$STOP_FILE.watchdog"
rm -f "$WD_FIRED"

TRANSPORT="${AIMMO_TRANSPORT:-enet}"
WD_PORT="${AIMMO_PORT:-${PORT:-7777}}"
WD_ON="${AIMMO_WATCHDOG:-on}"
WD_STARTUP="${AIMMO_WATCHDOG_STARTUP:-180}"
WD_INTERVAL="${AIMMO_WATCHDOG_INTERVAL:-20}"
WD_TIMEOUT="${AIMMO_WATCHDOG_TIMEOUT:-5}"
WD_FAILURES="${AIMMO_WATCHDOG_FAILURES:-3}"
WD_STOP_WAIT="${AIMMO_WATCHDOG_STOP_WAIT:-20}"

godot --headless --path "$GAME_DIR" -- --server &
PID=$!
echo "[entrypoint] server pid $PID"

# Asks a stuck server to save and stop; kills it if it can't. Runs inside the watchdog.
restart_stuck_server() {
  echo "[watchdog] $1, asking it to save and stop"
  touch "$WD_FIRED" "$STOP_FILE"
  local waited=0
  while kill -0 "$PID" 2>/dev/null && [ "$waited" -lt "$WD_STOP_WAIT" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  if kill -0 "$PID" 2>/dev/null; then
    echo "[watchdog] server did not stop within ${WD_STOP_WAIT}s, killing it (progress since the last autosave is lost)"
    kill -KILL "$PID" 2>/dev/null || true
  fi
}

watchdog() {
  local started=$SECONDS misses=0
  until "$PROBE" 127.0.0.1 "$WD_PORT" "$WD_TIMEOUT"; do
    kill -0 "$PID" 2>/dev/null || return 0
    if [ $((SECONDS - started)) -ge "$WD_STARTUP" ]; then
      restart_stuck_server "server never answered on port $WD_PORT within ${WD_STARTUP}s of starting"
      return 0
    fi
    sleep 1
  done
  echo "[watchdog] server answering on port $WD_PORT, checking every ${WD_INTERVAL}s"
  while kill -0 "$PID" 2>/dev/null; do
    sleep "$WD_INTERVAL"
    [ -e "$STOP_FILE" ] && return 0   # a normal shutdown is under way
    if "$PROBE" 127.0.0.1 "$WD_PORT" "$WD_TIMEOUT"; then
      [ "$misses" -gt 0 ] && echo "[watchdog] server answering again after $misses missed check(s)"
      misses=0
    else
      kill -0 "$PID" 2>/dev/null || return 0
      misses=$((misses + 1))
      echo "[watchdog] no answer from the server ($misses of $WD_FAILURES)"
      if [ "$misses" -ge "$WD_FAILURES" ]; then
        restart_stuck_server "server stopped answering for $misses checks in a row"
        return 0
      fi
    fi
  done
}

WD_PID=""
if [ "$WD_ON" = "off" ]; then
  echo "[watchdog] off (AIMMO_WATCHDOG=off)"
elif [ "$TRANSPORT" != "websocket" ]; then
  echo "[watchdog] off: it probes WebSocket and this server uses $TRANSPORT"
else
  watchdog &
  WD_PID=$!
fi

stop_watchdog() {
  [ -n "$WD_PID" ] && kill "$WD_PID" 2>/dev/null || true
}

graceful() {
  echo "[entrypoint] stop requested, asking server to save and exit"
  touch "$STOP_FILE"
  wait "$PID" || true
  stop_watchdog
  exit 0
}
trap graceful TERM INT

CODE=0
wait "$PID" || CODE=$?
if [ -e "$WD_FIRED" ]; then
  wait "$WD_PID" 2>/dev/null || true
  echo "[entrypoint] server was restarted by the watchdog (exit $CODE), exiting 70 so Railway starts a fresh one"
  exit 70
fi
stop_watchdog
exit "$CODE"

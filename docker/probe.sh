#!/bin/bash
# Is the AiMMO server's main loop alive? Opens a WebSocket handshake to it and waits for
# "101 Switching Protocols". Godot only answers a handshake from its main loop, so a server
# that is frozen (deadlock, infinite loop, stuck on I/O) times out here even though the
# kernel still accepts the TCP connection.
#
# Usage: probe.sh [host] [port] [timeout_seconds]   exit 0 = answered, 1 = did not
# The server logs one "peer N connected" / "disconnected before logging in" pair per probe.
HOST="${1:-127.0.0.1}"
PORT="${2:-${AIMMO_PORT:-${PORT:-7777}}}"
TIMEOUT="${3:-5}"

timeout "$TIMEOUT" bash -c '
  exec 3<>"/dev/tcp/$0/$1" || exit 1
  printf "GET / HTTP/1.1\r\nHost: %s:%s\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: YWltbW8td2F0Y2hkb2cxMg==\r\nSec-WebSocket-Version: 13\r\n\r\n" "$0" "$1" >&3 || exit 1
  IFS= read -r line <&3 || exit 1
  exec 3>&-
  case "$line" in "HTTP/1.1 101"*) exit 0 ;; *) exit 1 ;; esac
' "$HOST" "$PORT" 2>/dev/null

#!/usr/bin/env python3
"""AiMMO protocol-mismatch test.

Starts the dedicated server and connects clients that have not updated: one for every frozen
copy of an older net.gd in tests/protocol/net_v<N>.gd (with that old protocol number), plus
the current net.gd with a wrong protocol number in both directions. Each must get a clear
"please update" reply within a few seconds, never a hang and never a login. Then a current
client must still log in, and the server must stop cleanly.

Fails on: no reply, a reply that lets an old client in or doesn't say to update, any server
ERROR line other than Godot's own "rpc node checksum failed" notice (expected when the RPC
sets differ), or a server that crashes or doesn't stop cleanly.

Usage:
  python3 tests/protocol/run_protocol_test.py [--transport websocket] [--timeout 8]

Uses $DATABASE_URL when set; otherwise a temp JSON store. Needs `godot` on PATH (or $GODOT).
"""
import argparse
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GAME = REPO / "game"
HERE = Path(__file__).resolve().parent
GODOT = os.environ.get("GODOT", "godot")
ERROR_MARKERS = ("ERROR:", "SCRIPT ERROR", "Segmentation fault", "Aborted", "Parse Error", "FATAL")
# Godot logs this (plus an "at:" line) on the server when an old client's RPC list differs.
# It is harmless as long as the login still gets through, which this test checks.
ALLOWED_ERRORS = ("The rpc node checksum failed",)
UPDATE_WORDS = ("out of date", "update", "latest")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def current_protocol() -> int:
    text = (GAME / "shared" / "game_config.gd").read_text()
    m = re.search(r"const PROTOCOL_VERSION\s*:?=\s*(\d+)", text)
    if not m:
        raise SystemExit("could not read PROTOCOL_VERSION from game/shared/game_config.gd")
    return int(m.group(1))


def log_problems(path: Path, label: str) -> list:
    problems = []
    for line in path.read_text(errors="replace").splitlines():
        if any(m in line for m in ERROR_MARKERS) and not any(a in line for a in ALLOWED_ERRORS):
            problems.append(f"{label}: {line.strip()}")
    return problems


def run_client(work: Path, port: int, transport: str, timeout: float, name: str, net: str, protocol: int) -> dict:
    result = work / f"{name}.json"
    log = work / f"{name}.log"
    cmd = [GODOT, "--headless", "--path", str(GAME), "-s", "tests/protocol/old_client.gd", "--",
           f"--net={net}", f"--protocol={protocol}", f"--name={name}", f"--password=pw-{name}",
           f"--address=127.0.0.1:{port}", f"--transport={transport}", f"--timeout={timeout}",
           f"--result={result}"]
    try:
        subprocess.run(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, timeout=timeout + 60)
    except subprocess.TimeoutExpired:
        return {"hung": True, "log": log}
    r = json.loads(result.read_text()) if result.exists() else {"no_result": True}
    r["log"] = log
    return r


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--transport", default=os.environ.get("AIMMO_TRANSPORT", "websocket"), choices=["enet", "websocket"])
    ap.add_argument("--timeout", type=float, default=8.0, help="seconds an old client waits for its reply")
    ap.add_argument("--keep", action="store_true", help="keep the work directory")
    a = ap.parse_args()

    proto = current_protocol()
    work = Path(tempfile.mkdtemp(prefix="aimmo-protocol-test-"))
    port = free_port()
    stop_file = work / "stop"
    env = dict(os.environ)
    env.update({"AIMMO_PORT": str(port), "AIMMO_TRANSPORT": a.transport,
                "AIMMO_STOP_FILE": str(stop_file), "AIMMO_DATA_DIR": str(work / "data")})

    tag = str(int(time.time()))[-5:]
    cases = []  # (name, net script, protocol number, what it stands for)
    for f in sorted(HERE.glob("net_v*.gd")):
        v = int(f.stem[len("net_v"):])
        if v < proto:
            cases.append((f"old{tag}_v{v}", f"res://tests/protocol/{f.name}", v, f"a v{v} client"))
    cases.append((f"old{tag}_num", "res://shared/net.gd", proto - 1, f"current RPCs, protocol {proto - 1}"))
    cases.append((f"new{tag}_num", "res://shared/net.gd", proto + 1, f"current RPCs, protocol {proto + 1}"))
    print(f"[protocol-test] server protocol v{proto} over {a.transport}, {len(cases)} out-of-date clients, work={work}")

    server_log = work / "server.log"
    t0 = time.time()
    server = subprocess.Popen([GODOT, "--headless", "--path", str(GAME), "--", "--server"],
                              stdout=open(server_log, "w"), stderr=subprocess.STDOUT, env=env)
    deadline = time.time() + 60
    while "[server] listening" not in server_log.read_text(errors="replace"):
        if server.poll() is not None or time.time() > deadline:
            print(server_log.read_text(errors="replace"))
            print("[protocol-test] FAIL: server did not start")
            return 1
        time.sleep(0.2)

    problems = []
    for name, net, protocol, what in cases:
        r = run_client(work, port, a.transport, a.timeout, name, net, protocol)
        problems += log_problems(r["log"], name)
        if r.get("hung") or r.get("no_result"):
            problems.append(f"{what}: the test client itself hung or wrote no result")
            continue
        verdict = "ok"
        if not r["connected"]:
            verdict = f"never connected ({r['message']})"
        elif not r["got_reply"]:
            verdict = f"HANGS at login: {r['message']}"
        elif r["ok"]:
            verdict = "was let in"
        elif not any(w in r["message"].lower() for w in UPDATE_WORDS):
            verdict = f"rejected without saying to update: {r['message']!r}"
        elif r["rpcs_before_reply"]:
            verdict = f"got game traffic before the rejection: {r['rpcs_before_reply']}"
        print(f"[protocol-test] {what}: {verdict}"
              + (f" ({r['reply_seconds']:.2f}s, {r['message']!r})" if r["got_reply"] else ""))
        if verdict != "ok":
            problems.append(f"{what}: {verdict}")
        if server.poll() is not None:
            problems.append(f"server exited after {what} with code {server.returncode}")
            break

    # The server must still let a current client in after all that.
    if server.poll() is None:
        r = run_client(work, port, a.transport, a.timeout, f"cur{tag}", "res://shared/net.gd", proto)
        problems += log_problems(r["log"], "current client")
        if not r.get("ok"):
            problems.append(f"a current client could not log in afterwards: {r.get('message', r)}")
        else:
            print(f"[protocol-test] current client: logged in ({r['reply_seconds']:.2f}s)")

    stop_file.write_text("stop")
    try:
        server.wait(timeout=30)
    except subprocess.TimeoutExpired:
        server.kill()
        problems.append("server did not shut down within 30s of the stop request")
    slog = server_log.read_text(errors="replace")
    if server.returncode not in (0, None):
        problems.append(f"server exit code {server.returncode}")
    if "[server] stopped cleanly" not in slog:
        problems.append("server did not report a clean stop")
    for name, _, _, what in cases:
        if f"[server] {name} logged in" in slog:
            problems.append(f"{what}: the server logged it in")
    problems += log_problems(server_log, "server")

    took = time.time() - t0
    if problems:
        print(f"[protocol-test] FAILED after {took:.0f}s with {len(problems)} problem(s):")
        for p in problems:
            print("  - " + p)
        print(f"[protocol-test] logs kept in {work}")
        return 1
    print(f"[protocol-test] PASSED in {took:.0f}s")
    if not a.keep:
        for f in work.rglob("*"):
            if f.is_file():
                f.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())

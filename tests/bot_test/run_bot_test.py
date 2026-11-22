#!/usr/bin/env python3
"""AiMMO bot test.

Starts the dedicated server, connects N simulated players that log in, walk, chat,
disconnect, reconnect, and verify their position persisted. Then it stops the server
cleanly, boots storage again, and checks every bot's final position was saved.

Fails on: any bot failure, any server/bot crash, any ERROR line in a log, a desync
(position off the shared terrain), or data loss (saved position missing or wrong).

Usage:
  python3 tests/bot_test/run_bot_test.py [--bots 8] [--duration 180] [--transport enet]

Uses $DATABASE_URL when set (CI uses a real Postgres); otherwise a temp JSON store.
Needs `godot` on PATH (or $GODOT).
"""
import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
GAME = REPO / "game"
GODOT = os.environ.get("GODOT", "godot")
ERROR_MARKERS = ("ERROR:", "SCRIPT ERROR", "Segmentation fault", "Aborted", "Parse Error", "FATAL")


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def scan_log(path: Path, label: str) -> list:
    problems = []
    for line in path.read_text(errors="replace").splitlines():
        if any(m in line for m in ERROR_MARKERS):
            problems.append(f"{label}: {line.strip()}")
    return problems


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bots", type=int, default=8)
    ap.add_argument("--duration", type=float, default=180.0, help="seconds each bot plays")
    ap.add_argument("--transport", default=os.environ.get("AIMMO_TRANSPORT", "enet"), choices=["enet", "websocket"])
    ap.add_argument("--keep", action="store_true", help="keep the work directory")
    a = ap.parse_args()

    work = Path(tempfile.mkdtemp(prefix="aimmo-bot-test-"))
    port = free_port()
    stop_file = work / "stop"
    env = dict(os.environ)
    env.update({"AIMMO_PORT": str(port), "AIMMO_TRANSPORT": a.transport,
                "AIMMO_STOP_FILE": str(stop_file), "AIMMO_DATA_DIR": str(work / "data")})
    storage = "postgres" if env.get("DATABASE_URL") else "json"
    print(f"[bot-test] {a.bots} bots x {a.duration:.0f}s over {a.transport}, storage={storage}, port={port}, work={work}")

    server_log = work / "server.log"
    t0 = time.time()
    server = subprocess.Popen([GODOT, "--headless", "--path", str(GAME), "--", "--server"],
                              stdout=open(server_log, "w"), stderr=subprocess.STDOUT, env=env)
    deadline = time.time() + 60
    while "[server] listening" not in server_log.read_text(errors="replace"):
        if server.poll() is not None or time.time() > deadline:
            print(server_log.read_text(errors="replace"))
            print("[bot-test] FAIL: server did not start")
            return 1
        time.sleep(0.2)

    bots = []
    run_tag = str(int(t0))[-5:]
    for i in range(a.bots):
        name = f"bot{run_tag}_{i + 1}"
        result = work / f"{name}.json"
        log = work / f"{name}.log"
        cmd = [GODOT, "--headless", "--path", str(GAME), "--", "--bot", f"--name={name}",
               f"--password=pw-{name}", f"--address=127.0.0.1:{port}", f"--transport={a.transport}",
               f"--duration={a.duration}", f"--result={result}", f"--expect-peers={a.bots - 1}"]
        p = subprocess.Popen(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env)
        bots.append((name, p, result, log))
        time.sleep(0.3)

    problems = []
    hard_deadline = time.time() + a.duration + 120
    for name, p, _, _ in bots:
        try:
            p.wait(timeout=max(1, hard_deadline - time.time()))
        except subprocess.TimeoutExpired:
            p.kill()
            problems.append(f"{name}: hung and was killed")
        if server.poll() is not None:
            problems.append(f"server exited early with code {server.returncode}")
            break

    stop_file.write_text("stop")
    try:
        server.wait(timeout=30)
    except subprocess.TimeoutExpired:
        server.kill()
        problems.append("server did not shut down within 30s of the stop request")
    if server.returncode not in (0, None):
        problems.append(f"server exit code {server.returncode}")
    if "[server] stopped cleanly" not in server_log.read_text(errors="replace"):
        problems.append("server did not report a clean stop")
    problems += scan_log(server_log, "server")

    expected = {}
    for name, p, result, log in bots:
        problems += scan_log(log, name)
        if p.returncode not in (0, None) and not result.exists():
            problems.append(f"{name}: exited with code {p.returncode} and no result")
        if not result.exists():
            problems.append(f"{name}: no result file")
            continue
        r = json.loads(result.read_text())
        for f in r["failures"]:
            problems.append(f"{name}: {f}")
        s = r["stats"]
        print(f"[bot-test] {name}: ok={r['ok']} logins={s['logins']} snapshots={s['snapshots']} "
              f"walked={s['distance_walked']:.1f}m chats_in={s['chats_from_others']} peers_seen={s['max_peers_seen']} "
              f"restored={s['position_restored']}")
        if "final_position" in s:
            expected[name] = s["final_position"]

    # Data-loss check: boot storage in a fresh process and compare saved positions.
    if expected:
        exp_file = work / "expected.json"
        exp_file.write_text(json.dumps(expected))
        vlog = work / "verify.log"
        v = subprocess.run([GODOT, "--headless", "--path", str(GAME), "-s", "tests/bot_test/verify_store.gd",
                            "--", f"--expected={exp_file}"], stdout=open(vlog, "w"), stderr=subprocess.STDOUT, env=env, timeout=120)
        print(vlog.read_text(errors="replace").strip().splitlines()[-1] if vlog.read_text().strip() else "")
        if v.returncode != 0:
            problems.append("persistence check failed:\n" + vlog.read_text(errors="replace"))
        problems += scan_log(vlog, "verify")

    took = time.time() - t0
    if took < a.duration:
        problems.append(f"test ran only {took:.0f}s")
    if problems:
        print(f"[bot-test] FAILED after {took:.0f}s with {len(problems)} problem(s):")
        for pr in problems:
            print("  - " + pr)
        print(f"[bot-test] logs kept in {work}")
        return 1
    print(f"[bot-test] PASSED in {took:.0f}s")
    if not a.keep:
        for f in work.rglob("*"):
            if f.is_file():
                f.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""AiMMO bot test.

Starts the dedicated server, connects N simulated players that log in, walk, chat,
disconnect, reconnect, and verify their position persisted. Then it stops the server
cleanly, boots storage again, and checks every bot's final position was saved.

Fails on: any bot failure, any server/bot crash, any ERROR line in a log, a desync
(position off the shared terrain), or data loss (saved position missing or wrong).

Long runs (>= 120 s) also check real gathering as a whole (tests/bot_test/gather_report.py)
and then run the respawn probe: one fresh bot, only the qa_gather_ledger behaviour, logs in
while a node the bots emptied is still empty, waits for it to come back and gathers it.
Alongside the probe, two more fresh bots gather one node together on purpose (the pair
check, qa_gather_ledger's pair mode), so "two players on one node" never depends on where
the 8 bots happen to walk. Every saved character must hold exactly the pack the server last
sent its bot.

Every run also prints the fun metrics (tests/bot_test/fun_report.py) and writes
fun_metrics.json into the work directory, which is kept for the CI artifact. With
--fun-check the run also fails when they break the limits or got worse than
tests/bot_test/fun_baseline.json allows.

Usage:
  python3 tests/bot_test/run_bot_test.py [--bots 8] [--duration 180] [--transport enet] [--fun-check]

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

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fun_report  # noqa: E402
import gather_report  # noqa: E402

# The respawn probe waits at most this long after the bots for its node to come back.
MAX_PROBE_WAIT = 150.0
# Probe run length past its node's due time: respawn slack, walk, gather, reconnect.
PROBE_PLAY = 36.0
# Pair bots' run length: pick, walk ~35 m, wait for each other, gather, reconnect.
PAIR_PLAY = 50.0

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


def _ledger(stats: dict) -> dict:
    return stats.get("behaviours", {}).get("qa_gather_ledger", {}) or {}


def bot_cmd(name: str, port: int, transport: str, duration: float, result: Path, *extra: str) -> list:
    return [GODOT, "--headless", "--path", str(GAME), "--", "--bot", f"--name={name}",
            f"--password=pw-{name}", f"--address=127.0.0.1:{port}", f"--transport={transport}",
            f"--duration={duration:.1f}", f"--result={result}", *extra]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bots", type=int, default=8)
    ap.add_argument("--duration", type=float, default=180.0, help="seconds each bot plays")
    ap.add_argument("--transport", default=os.environ.get("AIMMO_TRANSPORT", "enet"), choices=["enet", "websocket"])
    ap.add_argument("--keep", action="store_true", help="keep the work directory")
    ap.add_argument("--fun-check", action="store_true",
                    help="fail on fun-metric limits and regressions against the baseline")
    ap.add_argument("--fun-baseline", default=str(fun_report.BASELINE), help="baseline JSON for --fun-check")
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

    # Real gathering across the run, then the respawn probe while the server is still up.
    rows = {}
    for name, _, result, _ in bots:
        try:
            rows[name] = json.loads(result.read_text())["stats"]
        except (OSError, ValueError, KeyError):
            pass
    if rows:
        print("[bot-test] gathering: " + gather_report.summary(rows))
    problems += [f"gathering: {g}" for g in gather_report.check(rows, a.duration, a.bots)]
    pair_bots = []
    if a.duration >= gather_report.LONG_RUN and server.poll() is None and rows:
        pick = gather_report.pick_probe(rows, time.time())
        # The pair goes first and never touches the probe's node; it plays while the probe waits.
        avoid = [f"--pair-avoid={pick[0]}"] if pick else []
        lead = f"bot{run_tag}_pairA"
        for name, extra in ((lead, ["--gather-pair=lead", *avoid]),
                            (f"bot{run_tag}_pairB", ["--gather-pair=follow", f"--pair-leader={lead}"])):
            result = work / f"{name}.json"
            log = work / f"{name}.log"
            cmd = bot_cmd(name, port, a.transport, PAIR_PLAY, result, "--expect-peers=0",
                          "--only-behaviour=qa_gather_ledger", *extra)
            pair_bots.append((name, subprocess.Popen(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env), result, log))
            time.sleep(1.0)
        if pick is None:
            if any(_ledger(s).get("depleted") for s in rows.values()):
                problems.append("gathering: every emptied node came back during the run, none left for the respawn probe")
        else:
            node, due = pick
            wait = due - gather_report.PROBE_LEAD - time.time()
            if wait > MAX_PROBE_WAIT:
                problems.append(f"gathering: the next node back (#{node}) is {wait:.0f}s away, over the probe's {MAX_PROBE_WAIT:.0f}s limit")
            else:
                print(f"[bot-test] respawn probe: node {node} due back in {due - time.time():.0f}s, probe starts in {max(0, wait):.0f}s")
                time.sleep(max(0.0, wait))
                name = f"bot{run_tag}_probe"
                result = work / f"{name}.json"
                log = work / f"{name}.log"
                dur = due - time.time() + PROBE_PLAY
                cmd = bot_cmd(name, port, a.transport, dur, result, "--expect-peers=0",
                              "--only-behaviour=qa_gather_ledger", f"--gather-probe={node}", f"--probe-due={due:.3f}")
                p = subprocess.Popen(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env)
                try:
                    p.wait(timeout=dur + 90)
                except subprocess.TimeoutExpired:
                    p.kill()
                    problems.append(f"{name}: hung and was killed")
                bots.append((name, p, result, log))
        pair_rows = {}
        for name, p, result, log in pair_bots:
            try:
                p.wait(timeout=PAIR_PLAY + 90)
            except subprocess.TimeoutExpired:
                p.kill()
                problems.append(f"{name}: hung and was killed")
            bots.append((name, p, result, log))
            try:
                pair_rows[name] = json.loads(result.read_text())["stats"]
            except (OSError, ValueError, KeyError):
                pass
        problems += [f"gathering: {g}" for g in gather_report.check_pair(pair_rows)]
        print("[bot-test] pair: " + ", ".join(f"{n} {_ledger(s).get('pair')}" for n, s in sorted(pair_rows.items())))

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
    fun_rows = {}
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
        for bname, bstats in sorted(s.get("behaviours", {}).items()):
            if bstats:
                print(f"[bot-test]   {bname}: " + " ".join(f"{k}={v}" for k, v in sorted(bstats.items())))
        if "qa_fun_metrics" in s.get("behaviours", {}):
            fun_rows[name] = s["behaviours"]["qa_fun_metrics"]
        if "final_position" in s:
            ledger = _ledger(s)
            expected[name] = {"pos": s["final_position"]}
            if "final_pack" in ledger:
                expected[name].update({"pack": ledger["final_pack"], "running_node": ledger.get("running_node", -1),
                                       "running_amount": ledger.get("running_amount", 0)})
            if "skills_floor" in ledger:
                expected[name]["skills_floor"] = ledger["skills_floor"]

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

    if fun_rows:
        summary = fun_report.summarise(fun_rows)
        print(fun_report.table(fun_rows, summary))
        baseline = fun_report.load_baseline(Path(a.fun_baseline))
        verdict = fun_report.check(summary, baseline)
        (work / "fun_metrics.json").write_text(json.dumps(
            {"bots": a.bots, "duration_s": a.duration, "transport": a.transport, "summary": summary,
             "per_bot": fun_rows, "baseline": baseline, "problems": verdict}, indent=2))
        for v in verdict:
            print(f"[bot-test] fun: {v}" + ("" if a.fun_check else " (not checked: no --fun-check)"))
        if a.fun_check:
            problems += [f"fun metrics: {v}" for v in verdict]
    elif a.fun_check:
        problems.append("fun metrics: no bot reported qa_fun_metrics")

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
            if f.is_file() and f.name != "fun_metrics.json":
                f.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())

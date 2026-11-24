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

Long runs also run the level-gate check (behaviour qa_level_gate, tests/bot_test/level_gate.gd)
next to the pair check: before the server starts, seed_veteran.gd saves a character at exactly
the level the tier-2 node nearest spawn needs, a few metres from it. A fresh bot walks to that
node and must be refused ("level", the "Needs <Skill> 5" line, nothing paid); the veteran then
works it until it is empty (every charge pays, so the refusal took none); both reconnect, the
veteran keeps its level and XP (checked in the save too) and the fresh bot is still refused.
Skip it with --no-level-gate.

Long runs also run the craft-haul check (behaviour client_craft_window with --craft-haul,
tests/bot_test/craft_haul.gd): seed_crafter.gd saves a character at the workbench holding
exactly a campfire's and a torch's inputs; it presses Craft on the real client window and must
make both, earn Toolcraft XP for each, and end with the goods and none of the inputs (also
checked in the save). Skip it with --no-craft-haul.

Every run also prints the fun metrics (tests/bot_test/fun_report.py) and writes
fun_metrics.json into the work directory, which is kept for the CI artifact. With
--fun-check the run also fails when they break the limits or got worse than
tests/bot_test/fun_baseline.json allows.

The main server runs with `--dev-commands`, so behaviours may type slash commands. Afterwards
the chat-gate phase boots a second server with `--dev-commands=0`, the way the public server
runs, and two bots (behaviour qa_chat_gate) type /gather, /bag and /who: each line must get
the "Chat is for talking" hint, change nothing, never be broadcast, and plain talk must still
reach the other bot. Skip it with --no-chat-gate.

Every run also samples the server process while the bots play (tests/bot_test/perf_report.py):
CPU milliseconds per tick, ticks per second the bots saw, peak memory and its growth, and on
WebSocket runs the bytes per second to and from each player, measured on the wire with `ss`.
It prints them and writes perf_metrics.json; with --perf-check the run fails when they break
tests/bot_test/perf_budget.json.

Usage:
  python3 tests/bot_test/run_bot_test.py [--bots 8] [--duration 180] [--transport enet] [--fun-check] [--perf-check]

Uses $DATABASE_URL when set (CI uses a real Postgres); otherwise a temp JSON store.
Needs `godot` on PATH (or $GODOT).
"""
import argparse
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fun_report  # noqa: E402
import gather_report  # noqa: E402
import perf_report  # noqa: E402

# The respawn probe waits at most this long after the bots for its node to come back.
MAX_PROBE_WAIT = 150.0
# Probe run length past its node's due time: respawn slack, walk, gather, reconnect.
PROBE_PLAY = 36.0
# Pair bots' run length: pick, walk ~35 m, wait for each other, gather, reconnect.
PAIR_PLAY = 50.0
# Level-gate bots' run length (cut short by qa_level_gate once both checks are done): walk
# ~50 m, refuse, hold, reconnect / walk 10 m, wait for the refusal, empty a 4-charge node, reconnect.
LEVEL_GATE_PLAY = 90.0
# Craft-haul bot's run length: two crafts at the bench in ~6 s, wander, reconnect, a refused press.
CRAFT_HAUL_PLAY = 40.0
# Chat-gate bots' run length: three commands per login, a reconnect, a couple of talk lines.
GATE_PLAY = 30.0

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


def start_server(env: dict, log: Path, *extra: str):
    """Starts a dedicated server; returns the process, or None (log printed) if it didn't listen in 60 s."""
    server = subprocess.Popen([GODOT, "--headless", "--path", str(GAME), "--", "--server", *extra],
                              stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env)
    deadline = time.time() + 60
    while "[server] listening" not in log.read_text(errors="replace"):
        if server.poll() is not None or time.time() > deadline:
            server.kill()
            print(log.read_text(errors="replace"))
            return None
        time.sleep(0.2)
    return server


def stop_server(server, log: Path, stop_file: Path, label: str) -> list:
    stop_file.write_text("stop")
    problems = []
    try:
        server.wait(timeout=30)
    except subprocess.TimeoutExpired:
        server.kill()
        problems.append(f"{label} did not shut down within 30s of the stop request")
    if server.returncode not in (0, None):
        problems.append(f"{label} exit code {server.returncode}")
    if "[server] stopped cleanly" not in log.read_text(errors="replace"):
        problems.append(f"{label} did not report a clean stop")
    return problems + scan_log(log, label)


class PerfSampler(threading.Thread):
    """Samples the server once a second (perf_report.sample) until stop() is called."""

    def __init__(self, pid: int, port: int, with_net: bool):
        super().__init__(daemon=True)
        self.pid, self.port, self.with_net = pid, port, with_net
        self.samples = []
        self._stop_event = threading.Event()

    def run(self):
        t0 = time.time()
        while not self._stop_event.is_set():
            self.samples.append([time.time() - t0, perf_report.sample(self.pid, self.port, self.with_net)])
            self._stop_event.wait(1.0)

    def stop(self) -> list:
        self._stop_event.set()
        self.join(timeout=10)
        return self.samples


def seed_crafter(env: dict, work: Path, name: str) -> list:
    """Saves the craft-haul bot (at the workbench, a campfire's and a torch's inputs) before the server starts."""
    log = work / "seed_crafter.log"
    r = subprocess.run([GODOT, "--headless", "--path", str(GAME), "-s", "tests/bot_test/seed_crafter.gd", "--",
                        f"--name={name}", f"--password=pw-{name}"],
                       stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env, timeout=120)
    text = log.read_text(errors="replace")
    seeded = [l for l in text.splitlines() if l.startswith("seed: crafter")]
    if r.returncode != 0 or not seeded:
        return [f"craft haul: could not seed the crafter:\n{text}"]
    print("[bot-test] " + seeded[0])
    return scan_log(log, "seed_crafter")


def seed_veteran(env: dict, work: Path, name: str):
    """Saves the level-gate veteran before the server starts. Returns (node id, problems)."""
    log = work / "seed_veteran.log"
    r = subprocess.run([GODOT, "--headless", "--path", str(GAME), "-s", "tests/bot_test/seed_veteran.gd", "--",
                        f"--name={name}", f"--password=pw-{name}"],
                       stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env, timeout=120)
    text = log.read_text(errors="replace")
    m = re.search(r"^seed: node=(\d+)$", text, re.M)
    if r.returncode != 0 or m is None:
        return -1, [f"level gate: could not seed the veteran:\n{text}"]
    print("[bot-test] " + next(l for l in text.splitlines() if l.startswith("seed: ")))
    return int(m.group(1)), scan_log(log, "seed_veteran")


def gate_log_problems(text: str) -> list:
    """What the chat-gate server's log must (not) say: commands off, and no command ran."""
    problems = []
    if "[server] dev commands: off" not in text:
        problems.append("the chat-gate server did not start with dev commands off")
    for line in text.splitlines():
        # "[chat] <name> ran /x" is a command; talk is "[chat] <name>: text".
        if re.match(r"\[chat\] [^:\s]+ ran /", line):
            problems.append("a command ran with dev commands off: " + line.strip())
    return problems


def run_chat_gate(base_env: dict, transport: str, work: Path, run_tag: str) -> list:
    """The chat-gate phase: a server without dev commands, two bots typing commands into chat."""
    gate = work / "chat_gate"
    gate.mkdir()
    port = free_port()
    stop_file = gate / "stop"
    env = dict(base_env)
    env.update({"AIMMO_PORT": str(port), "AIMMO_STOP_FILE": str(stop_file), "AIMMO_DATA_DIR": str(gate / "data")})
    log = gate / "server.log"
    server = start_server(env, log, "--dev-commands=0")
    if server is None:
        return ["chat gate: server did not start"]
    procs = []
    for i in (1, 2):
        name = f"bot{run_tag}_gate{i}"
        result, blog = gate / f"{name}.json", gate / f"{name}.log"
        cmd = bot_cmd(name, port, transport, GATE_PLAY, result, "--expect-peers=1",
                      "--only-behaviour=qa_chat_gate", "--chat-gate")
        procs.append((name, subprocess.Popen(cmd, stdout=open(blog, "w"), stderr=subprocess.STDOUT, env=env), result, blog))
        time.sleep(0.3)
    problems = []
    for name, p, _, _ in procs:
        try:
            p.wait(timeout=GATE_PLAY + 90)
        except subprocess.TimeoutExpired:
            p.kill()
            problems.append(f"{name}: hung and was killed")
    problems += stop_server(server, log, stop_file, "chat-gate server")
    problems += gate_log_problems(log.read_text(errors="replace"))
    for name, _, result, blog in procs:
        problems += scan_log(blog, name)
        try:
            r = json.loads(result.read_text())
        except (OSError, ValueError):
            problems.append(f"{name}: no result file")
            continue
        problems += [f"{name}: {f}" for f in r["failures"]]
        g = r["stats"].get("behaviours", {}).get("qa_chat_gate", {})
        print(f"[bot-test] chat gate {name}: typed={g.get('sent')} hints={g.get('hints')} "
              f"leaked={g.get('leaked')} talk_heard={r['stats'].get('chats_from_others')}")
    return [f"chat gate: {p}" for p in problems]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bots", type=int, default=8)
    ap.add_argument("--duration", type=float, default=180.0, help="seconds each bot plays")
    ap.add_argument("--transport", default=os.environ.get("AIMMO_TRANSPORT", "enet"), choices=["enet", "websocket"])
    ap.add_argument("--keep", action="store_true", help="keep the work directory")
    ap.add_argument("--fun-check", action="store_true",
                    help="fail on fun-metric limits and regressions against the baseline")
    ap.add_argument("--fun-baseline", default=str(fun_report.BASELINE), help="baseline JSON for --fun-check")
    ap.add_argument("--perf-check", action="store_true",
                    help="fail when server CPU, tick rate, memory or bandwidth break perf_budget.json")
    ap.add_argument("--perf-budget", default=str(perf_report.BUDGET), help="budget JSON for --perf-check")
    ap.add_argument("--no-level-gate", action="store_true", help="skip the tier-2 level-gate check")
    ap.add_argument("--no-craft-haul", action="store_true", help="skip the craft-haul check (crafting at the bench)")
    ap.add_argument("--no-chat-gate", action="store_true", help="skip the chat-gate phase (dev commands off)")
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
    run_tag = str(int(t0))[-5:]
    gate_node = -1
    problems = []
    level_gate = a.duration >= gather_report.LONG_RUN and not a.no_level_gate
    if level_gate:
        # Seeded while nothing else has storage open (the JSON store keeps the file in memory).
        gate_node, seed_problems = seed_veteran(env, work, f"bot{run_tag}_vet")
        problems += seed_problems
    craft_haul = a.duration >= gather_report.LONG_RUN and not a.no_craft_haul
    if craft_haul:
        problems += seed_crafter(env, work, f"bot{run_tag}_crafter")
    # Behaviours type slash commands (dev tools); the public server runs without the flag.
    server = start_server(env, server_log, "--dev-commands")
    if server is None:
        print("[bot-test] FAIL: server did not start")
        return 1

    # The server's own resources while the main bots play (not the probe/pair/gate phases after).
    sampler = PerfSampler(server.pid, port, a.transport == "websocket")
    sampler.start()
    bots = []
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

    perf_samples = sampler.stop()

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
        gate_bots = []
        if gate_node >= 0:
            fresh = f"bot{run_tag}_gate"
            for name, extra in ((fresh, ["--level-gate=fresh"]),
                                (f"bot{run_tag}_vet", ["--level-gate=veteran", f"--gate-partner={fresh}"])):
                result = work / f"{name}.json"
                log = work / f"{name}.log"
                cmd = bot_cmd(name, port, a.transport, LEVEL_GATE_PLAY, result, "--expect-peers=0",
                              "--only-behaviour=qa_level_gate", f"--gate-node={gate_node}", *extra)
                gate_bots.append((name, subprocess.Popen(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env), result, log))
                time.sleep(0.5)
        haul_bots = []
        if craft_haul:
            name = f"bot{run_tag}_crafter"
            result = work / f"{name}.json"
            log = work / f"{name}.log"
            cmd = bot_cmd(name, port, a.transport, CRAFT_HAUL_PLAY, result, "--expect-peers=0",
                          "--only-behaviour=client_craft_window", "--craft-haul")
            haul_bots.append((name, subprocess.Popen(cmd, stdout=open(log, "w"), stderr=subprocess.STDOUT, env=env), result, log))
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
        for name, p, result, log in gate_bots:
            try:
                p.wait(timeout=LEVEL_GATE_PLAY + 90)
            except subprocess.TimeoutExpired:
                p.kill()
                problems.append(f"{name}: hung and was killed")
            bots.append((name, p, result, log))
            try:
                g = json.loads(result.read_text())["stats"]["behaviours"]["qa_level_gate"].get("gate")
                print(f"[bot-test] level gate (node {gate_node}): {name} {g}")
            except (OSError, ValueError, KeyError):
                pass
        for name, p, result, log in haul_bots:
            try:
                p.wait(timeout=CRAFT_HAUL_PLAY + 90)
            except subprocess.TimeoutExpired:
                p.kill()
                problems.append(f"{name}: hung and was killed")
            bots.append((name, p, result, log))
            try:
                h = json.loads(result.read_text())["stats"]["behaviours"]["client_craft_window"]
                print(f"[bot-test] craft haul: {name} made={h.get('made')} pack={h.get('haul_pack')}")
            except (OSError, ValueError, KeyError):
                pass
        print("[bot-test] pair: " + ", ".join(f"{n} {_ledger(s).get('pair')}" for n, s in sorted(pair_rows.items())))

    problems += stop_server(server, server_log, stop_file, "server")
    if "[server] dev commands: on (--dev-commands)" not in server_log.read_text(errors="replace"):
        problems.append("server did not start with --dev-commands")

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
            haul = s.get("behaviours", {}).get("client_craft_window", {}) or {}
            if "haul_pack" in haul and "pack" not in expected[name]:
                expected[name]["pack"] = haul["haul_pack"]  # the crafted goods must be saved too
            if "skills_floor" in ledger:
                expected[name]["skills_floor"] = ledger["skills_floor"]
            gate = s.get("behaviours", {}).get("qa_level_gate", {}) or {}
            if "skills_floor" in gate:
                expected[name]["skills_floor"] = gate["skills_floor"]

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

    if not a.no_chat_gate:
        problems += run_chat_gate(env, a.transport, work, run_tag)

    if fun_rows:
        summary = fun_report.summarise(fun_rows)
        print(fun_report.table(fun_rows, summary))
        # One machine-readable line for tools/fun_trend.py (the director reads CI job logs, not artifacts).
        print("[bot-test] fun summary: " + json.dumps(summary, separators=(",", ":")))
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

    tick_rates = []
    for name, _, result, _ in bots[:a.bots]:
        try:
            r = json.loads(result.read_text())["stats"]["behaviours"]["qa_snapshot_flow"]["tick_rate"]
            tick_rates.append(r if r > 0 else None)
        except (OSError, ValueError, KeyError, TypeError):
            pass
    perf = perf_report.summarise(perf_samples, perf_report.server_tick_rate(), tick_rates)
    print(perf_report.table(perf))
    print("[bot-test] perf summary: " + json.dumps(perf, separators=(",", ":")))
    budget = perf_report.load_budget(Path(a.perf_budget))
    perf_problems, perf_notes = perf_report.check(perf, budget, a.transport == "websocket")
    if a.duration < budget.get("min_duration_s", 120):
        perf_notes += [f"(short run, not checked) {p}" for p in perf_problems]
        perf_problems = []
    (work / "perf_metrics.json").write_text(json.dumps(
        {"bots": a.bots, "duration_s": a.duration, "transport": a.transport, "summary": perf,
         "budget": budget, "problems": perf_problems, "notes": perf_notes, "samples": perf_samples}, indent=1))
    for n in perf_notes:
        print(f"[bot-test] perf note: {n}")
    for v in perf_problems:
        print(f"[bot-test] perf: {v}" + ("" if a.perf_check else " (not checked: no --perf-check)"))
    if a.perf_check:
        problems += [f"server performance: {v}" for v in perf_problems]

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
            if f.is_file() and f.name not in ("fun_metrics.json", "perf_metrics.json"):
                f.unlink()
    return 0


if __name__ == "__main__":
    sys.exit(main())

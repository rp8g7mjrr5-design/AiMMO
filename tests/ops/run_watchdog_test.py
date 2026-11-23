#!/usr/bin/env python3
"""AiMMO hung-server watchdog test.

Runs the real container entrypoint (docker/entrypoint.sh) against the real server, with short
watchdog timings, and checks each way it can end:

  healthy   the watchdog finds the server, never complains, and SIGTERM still saves and
            exits 0 (Railway's normal redeploy path).
  recovers  the server freezes (SIGSTOP), the watchdog notices and asks it to save and stop;
            it thaws (SIGCONT), saves everyone, and the entrypoint exits 70 so Railway
            restarts it. Nothing is killed.
  frozen    the server freezes for good: the watchdog kills it and the entrypoint exits 70.
  enet      the watchdog stays off for the ENet transport (it only speaks WebSocket).
  probe     docker/probe.sh fails fast when nothing is listening.

Fails on: a wrong exit code, the watchdog firing on a healthy server, a server ERROR line,
a server that wasn't stopped cleanly when it could have been, or anything taking far longer
than the timings allow.

Usage:
  python3 tests/ops/run_watchdog_test.py [--only healthy,frozen]

Uses $DATABASE_URL when set; otherwise a temp JSON store. Needs `godot` on PATH and bash.
"""
import argparse
import os
import signal
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ENTRYPOINT = REPO / "docker" / "entrypoint.sh"
PROBE = REPO / "docker" / "probe.sh"
ERROR_MARKERS = ("ERROR:", "SCRIPT ERROR", "Segmentation fault", "Parse Error", "FATAL")

# Short timings so a frozen server is caught in about 10 s instead of about a minute.
FAST = {
    "AIMMO_WATCHDOG_STARTUP": "60",
    "AIMMO_WATCHDOG_INTERVAL": "2",
    "AIMMO_WATCHDOG_TIMEOUT": "2",
    "AIMMO_WATCHDOG_FAILURES": "3",
    "AIMMO_WATCHDOG_STOP_WAIT": "4",
}
# Interval + timeout per miss, times the misses, plus the stop wait, plus slack.
DETECT_BUDGET = 3 * (2 + 2) + 4 + 15


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Run:
    """One entrypoint process with its own port, data dir and log."""

    def __init__(self, work: Path, name: str, transport: str = "websocket"):
        self.name = name
        self.dir = work / name
        self.dir.mkdir()
        self.log_path = self.dir / "entrypoint.log"
        self.port = free_port()
        env = dict(os.environ)
        env.update(FAST)
        env.update({
            "AIMMO_GAME_DIR": str(REPO / "game"),
            "AIMMO_TRANSPORT": transport,
            "AIMMO_PORT": str(self.port),
            "AIMMO_STOP_FILE": str(self.dir / "stop"),
            "AIMMO_DATA_DIR": str(self.dir / "data"),
            "AIMMO_MIGRATIONS_DIR": str(REPO / "db" / "migrations"),
        })
        self.proc = subprocess.Popen(["bash", str(ENTRYPOINT)], stdout=open(self.log_path, "w"),
                                     stderr=subprocess.STDOUT, env=env, cwd=str(REPO))
        self.server_pid = None

    def log(self) -> str:
        return self.log_path.read_text(errors="replace")

    def wait_for(self, text: str, timeout: float) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            if text in self.log():
                return True
            if self.proc.poll() is not None:
                return text in self.log()
            time.sleep(0.2)
        return False

    def find_server_pid(self) -> int:
        if not self.wait_for("[entrypoint] server pid ", 10):
            raise AssertionError("entrypoint never printed the server pid")
        for line in self.log().splitlines():
            if line.startswith("[entrypoint] server pid "):
                self.server_pid = int(line.split()[-1])
                return self.server_pid
        raise AssertionError("could not parse the server pid")

    def exit_code(self, timeout: float):
        try:
            return self.proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return None

    def server_alive(self) -> bool:
        if self.server_pid is None:
            return False
        try:
            os.kill(self.server_pid, 0)
        except ProcessLookupError:
            return False
        # A zombie still answers kill(0); check /proc for its state.
        try:
            stat = Path(f"/proc/{self.server_pid}/stat").read_text()
            return stat.split(")")[-1].split()[0] != "Z"
        except OSError:
            return False

    def cleanup(self):
        if self.server_pid and self.server_alive():
            for sig in (signal.SIGCONT, signal.SIGKILL):
                try:
                    os.kill(self.server_pid, sig)
                except ProcessLookupError:
                    pass
        if self.proc.poll() is None:
            self.proc.kill()
            self.proc.wait()

    def server_errors(self) -> list:
        return [l.strip() for l in self.log().splitlines() if any(m in l for m in ERROR_MARKERS)]


def scenario_healthy(work: Path) -> list:
    r = Run(work, "healthy")
    problems = []
    try:
        r.find_server_pid()
        if not r.wait_for("[watchdog] server answering", 60):
            return ["the watchdog never saw the server answer:\n" + r.log()]
        time.sleep(10)  # about four probes
        if "[watchdog] no answer" in r.log():
            problems.append("the watchdog missed a check on a healthy server")
        if "connected" not in r.log():
            problems.append("no probe reached the server (expected 'peer N connected' lines)")
        r.proc.send_signal(signal.SIGTERM)
        code = r.exit_code(30)
        if code != 0:
            problems.append(f"SIGTERM on a healthy server should exit 0, got {code}")
        if "[server] stopped cleanly" not in r.log():
            problems.append("SIGTERM did not stop the server cleanly")
        if "[watchdog] server stopped answering" in r.log() or "killing it" in r.log():
            problems.append("the watchdog acted during a normal shutdown")
        problems += [f"server error: {e}" for e in r.server_errors()]
    finally:
        r.cleanup()
    return [f"healthy: {p}" for p in problems]


def scenario_recovers(work: Path) -> list:
    r = Run(work, "recovers")
    problems = []
    try:
        pid = r.find_server_pid()
        if not r.wait_for("[watchdog] server answering", 60):
            return ["recovers: the watchdog never saw the server answer:\n" + r.log()]
        os.kill(pid, signal.SIGSTOP)
        t0 = time.time()
        if not r.wait_for("asking it to save and stop", DETECT_BUDGET):
            problems.append(f"the watchdog did not notice a frozen server within {DETECT_BUDGET}s")
        else:
            took = time.time() - t0
            print(f"  recovers: frozen server noticed after {took:.1f}s")
            os.kill(pid, signal.SIGCONT)
        code = r.exit_code(40)
        if code != 70:
            problems.append(f"expected exit 70 so Railway restarts it, got {code}")
        if "[server] stopped cleanly" not in r.log():
            problems.append("a server that thawed in time did not save and stop cleanly")
        if "killing it" in r.log():
            problems.append("the watchdog killed a server that was stopping on its own")
        problems += [f"server error: {e}" for e in r.server_errors()]
    finally:
        r.cleanup()
    return [f"recovers: {p}" for p in problems]


def scenario_frozen(work: Path) -> list:
    r = Run(work, "frozen")
    problems = []
    try:
        pid = r.find_server_pid()
        if not r.wait_for("[watchdog] server answering", 60):
            return ["frozen: the watchdog never saw the server answer:\n" + r.log()]
        os.kill(pid, signal.SIGSTOP)
        t0 = time.time()
        code = r.exit_code(DETECT_BUDGET)
        took = time.time() - t0
        if code is None:
            problems.append(f"the entrypoint was still running {DETECT_BUDGET}s after the server froze")
        else:
            print(f"  frozen: entrypoint exited {code} after {took:.1f}s")
            if code != 70:
                problems.append(f"expected exit 70 so Railway restarts it, got {code}")
        if "killing it" not in r.log():
            problems.append("the watchdog did not kill the frozen server")
        if r.server_alive():
            problems.append("the frozen server process is still there")
        if "[server] stopped cleanly" in r.log():
            problems.append("a frozen server cannot have stopped cleanly; the test froze nothing")
    finally:
        r.cleanup()
    return [f"frozen: {p}" for p in problems]


def scenario_enet(work: Path) -> list:
    r = Run(work, "enet", transport="enet")
    problems = []
    try:
        r.find_server_pid()
        if not r.wait_for("[server] listening", 60):
            return ["enet: the server never started:\n" + r.log()]
        if "[watchdog] off" not in r.log():
            problems.append("the watchdog should say it is off for ENet")
        time.sleep(3)
        r.proc.send_signal(signal.SIGTERM)
        code = r.exit_code(30)
        if code != 0:
            problems.append(f"SIGTERM should exit 0, got {code}")
        if "[server] stopped cleanly" not in r.log():
            problems.append("SIGTERM did not stop the server cleanly")
        problems += [f"server error: {e}" for e in r.server_errors()]
    finally:
        r.cleanup()
    return [f"enet: {p}" for p in problems]


def scenario_probe(work: Path) -> list:
    port = free_port()
    t0 = time.time()
    code = subprocess.run(["bash", str(PROBE), "127.0.0.1", str(port), "3"]).returncode
    took = time.time() - t0
    problems = []
    if code == 0:
        problems.append("probe said a closed port is answering")
    if took > 2.5:
        problems.append(f"probe took {took:.1f}s on a closed port; it should fail at once")
    # A listener that accepts but never replies (what a frozen server looks like).
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        s.listen(1)
        silent = s.getsockname()[1]
        t0 = time.time()
        code = subprocess.run(["bash", str(PROBE), "127.0.0.1", str(silent), "2"]).returncode
        took = time.time() - t0
    if code == 0:
        problems.append("probe said a silent listener is answering")
    if took > 4:
        problems.append(f"probe ignored its 2s timeout on a silent listener ({took:.1f}s)")
    return [f"probe: {p}" for p in problems]


SCENARIOS = {
    "probe": scenario_probe,
    "healthy": scenario_healthy,
    "recovers": scenario_recovers,
    "frozen": scenario_frozen,
    "enet": scenario_enet,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="", help="comma-separated scenarios: " + ",".join(SCENARIOS))
    a = ap.parse_args()
    names = [n for n in a.only.split(",") if n] or list(SCENARIOS)
    work = Path(tempfile.mkdtemp(prefix="aimmo-watchdog-test-"))
    print(f"watchdog test: logs in {work}")
    problems = []
    for n in names:
        t0 = time.time()
        got = SCENARIOS[n](work)
        print(f"  {n}: {'ok' if not got else 'FAILED'} ({time.time() - t0:.1f}s)")
        problems += got
    if problems:
        print("WATCHDOG TEST FAILED")
        for p in problems:
            print("  - " + p)
        return 1
    print("WATCHDOG TEST PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())

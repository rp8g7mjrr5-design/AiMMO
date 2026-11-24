#!/usr/bin/env python3
"""AiMMO server image test: the Docker image Railway runs, tested before Railway runs it.

The other tests run the server straight from the repo with the host's Godot. Railway builds
`Dockerfile` and runs `docker/entrypoint.sh` inside a slim Debian image, so a missing file in a
COPY, a tool the slim image doesn't have, a broken import step or a bad ENV would only show up
as a server that never comes back after a deploy. This test builds nothing itself; CI builds
the image from `Dockerfile` and hands it over with --image. Then:

  contents  the image has every tool the entrypoint and probe use, the imported script class
            cache, the migrations, and the default ENV Railway relies on.
  boots     the container starts with its own CMD (the real entrypoint) and answers a
            WebSocket handshake; with $DATABASE_URL set it runs the migrations against it.
  plays     two real bots from tests/bot_test log in to the container over WebSocket, walks,
            chat, see each other, disconnect and reconnect, and their positions are restored.
  stops     `docker stop` (what Railway does on a redeploy) saves everyone and exits 0.
  frozen    the server freezes inside the container; the watchdog kills it and the container
            exits 70, so Railway's ON_FAILURE policy starts a fresh one.

Fails on: any of the above, or a server ERROR line in the container log.

Usage:
  docker build -t aimmo-server:ci .
  python3 tests/ops/run_image_test.py --image aimmo-server:ci [--only contents,boots]

Runs containers with --network host so the container reaches the CI Postgres on 127.0.0.1
and the bot reaches the container. Needs docker, and `godot` on PATH for the bot.
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
PROBE = REPO / "docker" / "probe.sh"
GODOT = os.environ.get("GODOT", "godot")
ERROR_MARKERS = ("ERROR:", "SCRIPT ERROR", "Segmentation fault", "Parse Error", "FATAL")

# Tools docker/entrypoint.sh and docker/probe.sh call. `kill`, `wait` and `/dev/tcp` are bash
# builtins; the rest must exist in the slim image.
REQUIRED_TOOLS = ("bash", "godot", "timeout", "sleep", "touch", "rm", "dirname")
REQUIRED_FILES = (
    "/app/entrypoint.sh",
    "/app/probe.sh",
    "/app/game/project.godot",
    "/app/game/.godot/global_script_class_cache.cfg",
    "/app/CHANGELOG.md",
)
REQUIRED_ENV = {"AIMMO_TRANSPORT": "websocket", "AIMMO_PORT": "7777",
                "AIMMO_MIGRATIONS_DIR": "/app/db/migrations", "AIMMO_DATA_DIR": "/app/data",
                "MAX_PLAYERS": "8"}

FAST_WATCHDOG = {
    "AIMMO_WATCHDOG_STARTUP": "120",
    "AIMMO_WATCHDOG_INTERVAL": "2",
    "AIMMO_WATCHDOG_TIMEOUT": "2",
    "AIMMO_WATCHDOG_FAILURES": "3",
    "AIMMO_WATCHDOG_STOP_WAIT": "4",
}
DETECT_BUDGET = 3 * (2 + 2) + 4 + 20
BOT_SECONDS = 40
BOTS = 2


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def docker(*args, timeout=120, check=False) -> subprocess.CompletedProcess:
    return subprocess.run(["docker", *args], capture_output=True, text=True, timeout=timeout, check=check)


class Container:
    """One detached container of the image, running its own CMD, with its log saved."""

    def __init__(self, image: str, work: Path, name: str, extra_env=None):
        self.name = f"aimmo-image-test-{name}-{os.getpid()}"
        self.dir = work / name
        self.dir.mkdir()
        self.port = free_port()
        env = {"AIMMO_PORT": str(self.port), **FAST_WATCHDOG, **(extra_env or {})}
        if os.environ.get("DATABASE_URL"):
            env["DATABASE_URL"] = os.environ["DATABASE_URL"]
        cmd = ["run", "-d", "--name", self.name, "--network", "host"]
        for k, v in env.items():
            cmd += ["-e", f"{k}={v}"]
        r = docker(*cmd, image)
        if r.returncode != 0:
            raise AssertionError(f"docker run failed: {r.stderr.strip()}")

    def log(self) -> str:
        r = docker("logs", self.name)
        text = r.stdout + r.stderr
        (self.dir / "container.log").write_text(text)
        return text

    def wait_for(self, text: str, timeout: float) -> bool:
        end = time.time() + timeout
        while time.time() < end:
            if text in self.log():
                return True
            if not self.running():
                return text in self.log()
            time.sleep(0.5)
        return False

    def running(self) -> bool:
        r = docker("inspect", "-f", "{{.State.Running}}", self.name)
        return r.stdout.strip() == "true"

    def exit_code(self, timeout: float):
        """Waits up to `timeout` seconds for the container to exit; None if it didn't."""
        end = time.time() + timeout
        while time.time() < end:
            if not self.running():
                r = docker("inspect", "-f", "{{.State.ExitCode}}", self.name)
                return int(r.stdout.strip())
            time.sleep(0.5)
        return None

    def server_pid(self) -> int:
        """The Godot server's pid inside the container's pid namespace."""
        if not self.wait_for("[entrypoint] server pid ", 15):
            raise AssertionError("entrypoint never printed the server pid; last log lines:\n" + self.tail())
        for line in self.log().splitlines():
            if line.startswith("[entrypoint] server pid "):
                return int(line.split()[-1])
        raise AssertionError("could not parse the server pid")

    def tail(self, n: int = 30) -> str:
        return "\n".join(self.log().splitlines()[-n:])

    def errors(self) -> list:
        return [l.strip() for l in self.log().splitlines() if any(m in l for m in ERROR_MARKERS)]

    def remove(self):
        self.log()
        docker("rm", "-f", self.name, timeout=60)


def scenario_contents(image: str, work: Path) -> list:
    problems = []
    script = "; ".join(
        [f'command -v {t} >/dev/null || echo "missing tool: {t}"' for t in REQUIRED_TOOLS]
        + [f'test -f {f} || echo "missing file: {f}"' for f in REQUIRED_FILES]
        + ['ls /app/db/migrations/*.sql >/dev/null 2>&1 || echo "missing file: /app/db/migrations/*.sql"',
           'test -x /app/entrypoint.sh || echo "not executable: /app/entrypoint.sh"',
           'test -x /app/probe.sh || echo "not executable: /app/probe.sh"',
           'godot --version >/dev/null 2>&1 || echo "godot does not run in the image"']
    )
    r = docker("run", "--rm", "--entrypoint", "bash", image, "-c", script)
    if r.returncode != 0:
        problems.append(f"could not run a shell in the image: {r.stderr.strip()}")
    problems += [l for l in r.stdout.splitlines() if l.strip()]
    # Migrations in the image must be exactly the repo's, or Railway runs a different schema.
    repo_migrations = sorted(p.name for p in (REPO / "db" / "migrations").glob("*.sql"))
    r = docker("run", "--rm", "--entrypoint", "bash", image, "-c", "cd /app/db/migrations && ls *.sql")
    if sorted(r.stdout.split()) != repo_migrations:
        problems.append(f"image migrations {sorted(r.stdout.split())} differ from the repo's {repo_migrations}")
    r = docker("inspect", "-f", "{{json .Config.Env}}", image)
    env = dict(e.split("=", 1) for e in json.loads(r.stdout or "[]"))
    for k, v in REQUIRED_ENV.items():
        if env.get(k) != v:
            problems.append(f"image ENV {k}={env.get(k)!r}, expected {v!r}")
    r = docker("inspect", "-f", "{{json .Config.Cmd}}", image)
    if json.loads(r.stdout or "null") != ["/app/entrypoint.sh"]:
        problems.append(f"image CMD is {r.stdout.strip()}, expected [\"/app/entrypoint.sh\"]")
    return [f"contents: {p}" for p in problems]


def scenario_boots_plays_stops(image: str, work: Path) -> list:
    """One container for boots, plays and stops: booting it costs ~10-20 s each time."""
    # The bots type /time, /who and /skills, which are dev commands: off by default since
    # gameplay's chat gate (#139), so this one container switches them on the way an operator
    # would, with the env var (the image's CMD takes no flags). The frozen container keeps the
    # image's default.
    c = Container(image, work, "plays", extra_env={"AIMMO_DEV_COMMANDS": "1"})
    problems = []
    try:
        c.server_pid()
        t0 = time.time()
        if not c.wait_for("[watchdog] server answering", 120):
            return ["boots: the container never answered a WebSocket handshake; last log lines:\n" + c.tail()]
        print(f"  boots: answering on port {c.port} after {time.time() - t0:.1f}s")
        if subprocess.run(["bash", str(PROBE), "127.0.0.1", str(c.port), "5"]).returncode != 0:
            problems.append("boots: the host's probe got no handshake from the container")
        want = "postgres" if os.environ.get("DATABASE_URL") else "json"
        if f"[server] storage ready: {want}" not in c.log():
            problems.append(f"boots: the server did not report {want} storage ready")
        if "[server] dev commands: on (AIMMO_DEV_COMMANDS)" not in c.log():
            problems.append("boots: AIMMO_DEV_COMMANDS=1 did not switch the server's dev commands on")
        if f"[server] player cap: {REQUIRED_ENV['MAX_PLAYERS']}" not in c.log():
            problems.append("boots: the server did not pick up the image's MAX_PLAYERS cap")

        # plays: real bots from the bot test, run on the host against the container. Two, because
        # several behaviours (compass, avatars) need to see another player.
        tag = str(int(time.time()))[-5:]
        bots = []
        for i in range(BOTS):
            name = f"imgbot{tag}_{i + 1}"
            result = c.dir / f"{name}.json"
            blog = c.dir / f"{name}.log"
            cmd = [GODOT, "--headless", "--path", str(GAME), "--", "--bot", f"--name={name}",
                   f"--password=pw-{name}", f"--address=127.0.0.1:{c.port}", "--transport=websocket",
                   f"--duration={BOT_SECONDS}", f"--result={result}", f"--expect-peers={BOTS - 1}"]
            bots.append((name, subprocess.Popen(cmd, stdout=open(blog, "w"), stderr=subprocess.STDOUT), result, blog))
            time.sleep(0.3)
        for name, p, result, blog in bots:
            try:
                p.wait(timeout=BOT_SECONDS + 90)
            except subprocess.TimeoutExpired:
                p.kill()
                problems.append(f"plays: {name} hung and was killed")
            if not result.exists():
                problems.append(f"plays: {name} wrote no result:\n" + blog.read_text(errors="replace")[-3000:])
                continue
            r = json.loads(result.read_text())
            s = r["stats"]
            print(f"  plays: {name} ok={r['ok']} logins={s['logins']} snapshots={s['snapshots']} "
                  f"walked={s['distance_walked']:.1f}m peers_seen={s['max_peers_seen']} restored={s['position_restored']}")
            problems += [f"plays: {name}: {f}" for f in r["failures"]]
            if s["logins"] < 2:
                problems.append(f"plays: {name} logged in {s['logins']} time(s), expected a reconnect too")
            if not s["position_restored"]:
                problems.append(f"plays: {name}'s position was not restored after reconnecting")
            problems += [f"plays: {name} log: {l.strip()}" for l in blog.read_text(errors="replace").splitlines()
                         if any(m in l for m in ERROR_MARKERS)]

        # stops: what Railway does on every redeploy.
        if "[watchdog] no answer" in c.log():
            problems.append("stops: the watchdog missed a check on a healthy container")
        r = docker("stop", "-t", "30", c.name, timeout=60)
        code = c.exit_code(5)
        if code != 0:
            problems.append(f"stops: docker stop should exit 0, got {code} ({r.stderr.strip()})")
        if "[server] stopped cleanly" not in c.log():
            problems.append("stops: docker stop did not let the server save and stop cleanly")
        problems += [f"server error: {e}" for e in c.errors()]
    finally:
        c.remove()
    return problems


def scenario_frozen(image: str, work: Path) -> list:
    c = Container(image, work, "frozen")
    problems = []
    try:
        pid = c.server_pid()
        if not c.wait_for("[watchdog] server answering", 120):
            return ["frozen: the container never answered; last log lines:\n" + c.tail()]
        for line in c.log().splitlines():
            if line.startswith("[server] dev commands:"):
                print(f"  frozen: image default {line[len('[server] '):]}")
        r = docker("exec", c.name, "bash", "-c", f"kill -STOP {pid}")
        if r.returncode != 0:
            return [f"frozen: could not freeze the server: {r.stderr.strip()}"]
        t0 = time.time()
        code = c.exit_code(DETECT_BUDGET)
        if code is None:
            problems.append(f"the container was still running {DETECT_BUDGET}s after the server froze")
        else:
            print(f"  frozen: container exited {code} after {time.time() - t0:.1f}s")
            if code != 70:
                problems.append(f"expected exit 70 so Railway restarts it, got {code}")
        if "killing it" not in c.log():
            problems.append("the watchdog did not kill the frozen server")
    finally:
        c.remove()
    return [f"frozen: {p}" for p in problems]


SCENARIOS = {
    "contents": scenario_contents,
    "plays": scenario_boots_plays_stops,
    "frozen": scenario_frozen,
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--image", required=True, help="the image built from Dockerfile")
    ap.add_argument("--only", default="", help="comma-separated scenarios: " + ",".join(SCENARIOS))
    a = ap.parse_args()
    if docker("image", "inspect", a.image).returncode != 0:
        print(f"IMAGE TEST FAILED: no image {a.image!r}; build it first with docker build -t {a.image} .")
        return 1
    names = [n for n in a.only.split(",") if n] or list(SCENARIOS)
    work = Path(tempfile.mkdtemp(prefix="aimmo-image-test-"))
    storage = "postgres" if os.environ.get("DATABASE_URL") else "json"
    print(f"image test: {a.image}, storage={storage}, logs in {work}")
    problems = []
    for n in names:
        t0 = time.time()
        got = SCENARIOS[n](a.image, work)
        print(f"  {n}: {'ok' if not got else 'FAILED'} ({time.time() - t0:.1f}s)")
        problems += got
    if problems:
        print("IMAGE TEST FAILED")
        for p in problems:
            print("  - " + p)
        return 1
    print("IMAGE TEST PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())

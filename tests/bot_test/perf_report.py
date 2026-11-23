"""Server performance budget for the bot test (qa).

While the 8 bots play, run_bot_test.py samples the server process once a second from the
outside, so no server code changes are needed and nothing here can slow the game down:

  * CPU time  (/proc/<pid>/stat utime + stime) -> server CPU milliseconds per tick
  * memory    (/proc/<pid>/status VmRSS)       -> peak RSS and growth across the run
  * bandwidth (`ss -tin` on the server port)   -> bytes per second to and from each player,
              measured on the wire (WebSocket frames included), WebSocket runs only
  * tick rate (bots' qa_snapshot_flow stat)    -> server ticks per second the players saw

The numbers are printed as a table, written to perf_metrics.json next to fun_metrics.json,
and with --perf-check checked against tests/bot_test/perf_budget.json: hard ceilings
("budget") fail the run, and so does growing past the stored baseline by more than its
"worse_ratio" for metrics that don't depend on the machine (bandwidth). CPU and memory
drift against the baseline is printed as a note, because CI machines differ.

Everything here is plain maths on sampled numbers so tests/bot_test/test_perf_report.py can
check it without a server.
"""
import json
import os
import re
import statistics
import subprocess
from pathlib import Path

BUDGET = Path(__file__).resolve().parent / "perf_budget.json"
# Ignore the first seconds (bots logging in, server warming up) and the last ones (bots
# leaving) so the numbers describe a full server.
WARMUP_S = 30.0
COOLDOWN_S = 10.0
# A connection must live this long inside the window to count for bandwidth (reconnects
# leave short-lived sockets behind).
MIN_CONN_S = 10.0
# Peak CPU is the worst average over windows at least this long.
PEAK_WINDOW_S = 5.0
CLK_TCK = os.sysconf("SC_CLK_TCK") if hasattr(os, "sysconf") else 100


def server_tick_rate(config: Path = Path(__file__).resolve().parents[2] / "game/shared/game_config.gd") -> float:
    """GameConfig.TICK_RATE, read from the source so a change there moves the budget too."""
    m = re.search(r"^const TICK_RATE\s*:?=\s*(\d+)", config.read_text(), re.M)
    return float(m.group(1)) if m else 20.0


# ---------- parsing ----------

def parse_proc_stat(text: str, clk_tck: int = CLK_TCK) -> float:
    """CPU seconds (user + system) from the text of /proc/<pid>/stat."""
    # comm (field 2) is in parentheses and may contain spaces; fields after it are fixed.
    rest = text[text.rindex(")") + 2:].split()
    # rest[0] is field 3 (state), so utime (14) is rest[11] and stime (15) is rest[12].
    return (int(rest[11]) + int(rest[12])) / float(clk_tck)


def parse_rss_mb(text: str) -> float:
    """Resident memory in MB from the text of /proc/<pid>/status."""
    m = re.search(r"^VmRSS:\s+(\d+)\s+kB", text, re.M)
    return int(m.group(1)) / 1024.0 if m else 0.0


def parse_ss(text: str) -> dict:
    """Per-connection byte counters from `ss -tinH state established '( sport = :PORT )'`.

    Returns {peer "host:port": {"sent": bytes server -> player, "received": player -> server}}.
    ss prints each socket as an address line followed by an indented info line.
    """
    conns = {}
    peer = None
    for line in text.splitlines():
        if not line.strip():
            continue
        if not line[0].isspace():
            parts = line.split()
            # With a state filter ss drops the State column: Recv-Q Send-Q Local Peer [Process]
            addrs = [p for p in parts if ":" in p]
            peer = addrs[1] if len(addrs) >= 2 else None
            if peer is not None:
                conns[peer] = {"sent": 0, "received": 0}
            continue
        if peer is None:
            continue
        sent = re.search(r"\bbytes_sent:(\d+)", line) or re.search(r"\bbytes_acked:(\d+)", line)
        recv = re.search(r"\bbytes_received:(\d+)", line)
        if sent:
            conns[peer]["sent"] = int(sent.group(1))
        if recv:
            conns[peer]["received"] = int(recv.group(1))
    return conns


# ---------- sampling (live) ----------

def sample(pid: int, port: int, with_net: bool) -> dict:
    """One sample of the server process; missing sources come back as None."""
    s = {"cpu_s": None, "rss_mb": None, "conns": None}
    try:
        s["cpu_s"] = parse_proc_stat(Path(f"/proc/{pid}/stat").read_text())
        s["rss_mb"] = parse_rss_mb(Path(f"/proc/{pid}/status").read_text())
    except (OSError, ValueError, IndexError):
        pass
    if with_net:
        try:
            out = subprocess.run(["ss", "-tinH", "state", "established", f"( sport = :{port} )"],
                                 capture_output=True, text=True, timeout=5)
            if out.returncode == 0:
                s["conns"] = parse_ss(out.stdout)
        except (OSError, subprocess.SubprocessError):
            pass
    return s


# ---------- summary ----------

def _window(samples: list) -> list:
    """Samples ([t, sample]) inside the steady window; all of them if the run is short."""
    if not samples:
        return []
    t0, t1 = samples[0][0], samples[-1][0]
    inside = [x for x in samples if t0 + WARMUP_S <= x[0] <= t1 - COOLDOWN_S]
    return inside if len(inside) >= 3 else samples


def _cpu_ms_per_tick(a, b, tick_rate: float):
    if a[1]["cpu_s"] is None or b[1]["cpu_s"] is None or b[0] <= a[0]:
        return None
    return (b[1]["cpu_s"] - a[1]["cpu_s"]) * 1000.0 / ((b[0] - a[0]) * tick_rate)


def _rates(win: list, key: str) -> list:
    """Bytes per second for each connection that lived at least MIN_CONN_S in the window."""
    first, last = {}, {}
    for t, s in win:
        for peer, c in (s.get("conns") or {}).items():
            first.setdefault(peer, (t, c[key]))
            last[peer] = (t, c[key])
    out = []
    for peer, (ta, va) in first.items():
        tb, vb = last[peer]
        if tb - ta >= MIN_CONN_S and vb >= va:
            out.append((vb - va) / (tb - ta))
    return out


def summarise(samples: list, tick_rate: float, bot_tick_rates: list) -> dict:
    """samples: [[t, sample()], ...] in time order. Returns the metrics (None = not measured)."""
    win = _window(samples)
    out = {"window_s": round(win[-1][0] - win[0][0], 1) if win else 0.0, "samples": len(win)}
    cpu = _cpu_ms_per_tick(win[0], win[-1], tick_rate) if len(win) >= 2 else None
    out["cpu_ms_per_tick"] = round(cpu, 2) if cpu is not None else None
    peak = None
    j = 0
    for i in range(len(win)):
        while j < len(win) and win[j][0] - win[i][0] < PEAK_WINDOW_S:
            j += 1
        if j >= len(win):
            break
        v = _cpu_ms_per_tick(win[i], win[j], tick_rate)
        if v is not None:
            peak = v if peak is None else max(peak, v)
    out["cpu_ms_per_tick_peak"] = round(peak, 2) if peak is not None else out["cpu_ms_per_tick"]
    out["tick_budget_ms"] = round(1000.0 / tick_rate, 1)
    rss_all = [s["rss_mb"] for _, s in samples if s.get("rss_mb")]
    rss_win = [s["rss_mb"] for _, s in win if s.get("rss_mb")]
    out["rss_peak_mb"] = round(max(rss_all), 1) if rss_all else None
    out["rss_growth_mb"] = round(rss_win[-1] - rss_win[0], 1) if len(rss_win) >= 2 else None
    measured = any(s.get("conns") is not None for _, s in win)
    down = _rates(win, "sent") if measured else []
    up = _rates(win, "received") if measured else []
    out["players_measured"] = len(down)
    out["down_kbps_per_player_median"] = round(statistics.median(down) * 8 / 1000, 1) if down else None
    out["down_kbps_per_player_max"] = round(max(down) * 8 / 1000, 1) if down else None
    out["up_kbps_per_player_median"] = round(statistics.median(up) * 8 / 1000, 1) if up else None
    out["up_kbps_per_player_max"] = round(max(up) * 8 / 1000, 1) if up else None
    rates = [r for r in bot_tick_rates if r is not None]
    out["tick_rate_min"] = round(min(rates), 2) if rates else None
    out["tick_rate_median"] = round(statistics.median(rates), 2) if rates else None
    return out


# ---------- budget ----------

def load_budget(path: Path = BUDGET) -> dict:
    return json.loads(Path(path).read_text())


def check(summary: dict, budget: dict, need_net: bool) -> tuple:
    """Returns (problems, notes). problems fail --perf-check; notes are printed only."""
    problems, notes = [], []
    for key, limit in (budget.get("max") or {}).items():
        if key.startswith("_"):
            continue
        v = summary.get(key)
        if v is None:
            if key.startswith(("down_", "up_", "players_")) and not need_net:
                continue
            problems.append(f"{key} was not measured")
        elif v > limit:
            problems.append(f"{key} {v} is over the budget of {limit}")
    for key, limit in (budget.get("min") or {}).items():
        if key.startswith("_") or (key.startswith("players_") and not need_net):
            continue
        v = summary.get(key)
        if v is None:
            if key.startswith(("down_", "up_", "players_")) and not need_net:
                continue
            problems.append(f"{key} was not measured")
        elif v < limit:
            problems.append(f"{key} {v} is under the budget of {limit}")
    base = budget.get("baseline") or {}
    ratio = float(budget.get("worse_ratio", 1.5))
    gated = set(budget.get("baseline_gated") or [])
    for key, b in base.items():
        if key.startswith("_"):
            continue
        v = summary.get(key)
        if v is None or not b:
            continue
        if v > b * ratio:
            msg = f"{key} {v} is more than {ratio:g}x the baseline {b}"
            (problems if key in gated else notes).append(msg)
        elif v < b / ratio:
            notes.append(f"{key} {v} is well under the baseline {b}: re-take it in perf_budget.json")
    return problems, notes


def table(summary: dict) -> str:
    rows = [
        ("server CPU per tick (avg / worst 5 s)", f"{summary.get('cpu_ms_per_tick')} / {summary.get('cpu_ms_per_tick_peak')} ms of {summary.get('tick_budget_ms')} ms"),
        ("server ticks per second (slowest bot / median)", f"{summary.get('tick_rate_min')} / {summary.get('tick_rate_median')}"),
        ("server memory (peak / growth in window)", f"{summary.get('rss_peak_mb')} MB / {summary.get('rss_growth_mb')} MB"),
        ("down per player (median / max)", f"{summary.get('down_kbps_per_player_median')} / {summary.get('down_kbps_per_player_max')} kbit/s"),
        ("up per player (median / max)", f"{summary.get('up_kbps_per_player_median')} / {summary.get('up_kbps_per_player_max')} kbit/s"),
        ("players measured, window", f"{summary.get('players_measured')}, {summary.get('window_s')} s"),
    ]
    w = max(len(r[0]) for r in rows)
    return "\n".join(["[bot-test] server performance:"] + [f"[bot-test]   {k.ljust(w)}  {v}" for k, v in rows])

"""Real gathering (protocol v3) checks across the whole bot test.

Per bot, gameplay_gather_v3 reports what it gathered through c2s_gather_start (completed,
walked_off, stopped, ...) and qa_gather_ledger reports what it saw (emptied nodes with their
wall-clock time, respawns, the most players on one node at once, final pack). This module
checks the run as a whole in long runs:

- at least MIN_GATHERERS bots finished a timed gather through c2s_gather_start;
- at least one gather was cancelled by walking away and one by c2s_gather_cancel;
- two players worked one node at the same time: not left to where the 8 bots happen to
  walk (that flaked, see docs/devlog/qa.md), but checked by check_pair() on the pair bots
  the harness sends to one node on purpose (qa_gather_ledger's pair mode);
- at least one node was emptied, so pick_probe() can choose one for the respawn probe
  (a fresh player who sees it empty, hears it come back, and gathers it).

Tested by tests/bot_test/test_gather_report.py.
"""

MIN_GATHERERS = 4
LONG_RUN = 120.0
# The probe logs in at least this long before its node is due back, to see it empty first.
PROBE_LEAD = 8.0
# Reports of one emptying from different bots land within this many seconds of each other.
REPORT_SPREAD = 2.0


def _b(stats: dict, name: str) -> dict:
    return stats.get("behaviours", {}).get(name, {}) or {}


def check(rows: dict, duration: float, bots: int) -> list:
    """rows: {bot: stats}. Returns a list of problems (empty when fine)."""
    if duration < LONG_RUN or not rows:
        return []
    v3 = [_b(s, "gameplay_gather_v3") for s in rows.values()]
    ledger = [_b(s, "qa_gather_ledger") for s in rows.values()]
    problems = []
    gatherers = sum(1 for b in v3 if int(b.get("completed", 0)) > 0)
    want = min(MIN_GATHERERS, bots)
    if gatherers < want:
        problems.append(f"only {gatherers} of {len(rows)} bots finished a timed gather (c2s_gather_start), want {want}")
    if not any(int(b.get("walked_off", 0)) > 0 for b in v3):
        problems.append("no gather was cancelled by walking away")
    if not any(int(b.get("stopped", 0)) > 0 for b in v3):
        problems.append("no gather was cancelled with c2s_gather_cancel")
    if not any(b.get("depleted") for b in ledger):
        problems.append("no node was ever emptied, so respawn could not be checked")
    return problems


def check_pair(rows: dict) -> list:
    """rows: {bot: stats} of the two pair bots. Both must report the same node, both must have
    seen two gatherers on it at once, and at least one of them must have been paid (the other
    may find the node emptied by the first one's finish)."""
    pairs = [_b(s, "qa_gather_ledger").get("pair") or {} for s in rows.values()]
    if len(pairs) != 2 or not all(pairs):
        return [f"pair: expected 2 pair bots with results, got {sum(1 for p in pairs if p)}"]
    problems = []
    nodes = {int(p.get("node", -1)) for p in pairs}
    if len(nodes) != 1 or -1 in nodes:
        problems.append(f"pair: the two bots went to different nodes {sorted(nodes)}")
    if not all(p.get("together") for p in pairs):
        problems.append("pair: no two players ever gathered one node at the same time")
    if not any(p.get("end") == "done" for p in pairs):
        problems.append("pair: neither player was paid for the shared gather "
                        f"(ended {[p.get('end') for p in pairs]})")
    return problems


def summary(rows: dict) -> str:
    v3 = [_b(s, "gameplay_gather_v3") for s in rows.values()]
    ledger = [_b(s, "qa_gather_ledger") for s in rows.values()]
    emptied = {int(d[0]) for b in ledger for d in b.get("depleted", [])}
    back = {int(n) for b in ledger for n in b.get("respawned", [])}
    return (f"timed gathers done={sum(int(b.get('completed', 0)) for b in v3)} "
            f"by {sum(1 for b in v3 if int(b.get('completed', 0)) > 0)} bots, "
            f"walked_off={sum(int(b.get('walked_off', 0)) for b in v3)} "
            f"stopped={sum(int(b.get('stopped', 0)) for b in v3)} "
            f"most_on_one_node={max((int(b.get('shared_node_max', 0)) for b in ledger), default=0)} "
            f"nodes_emptied={len(emptied)} respawned_in_run={len(back)}")


def pick_probe(rows: dict, now: float, lead: float = PROBE_LEAD) -> tuple:
    """The emptied node that comes back soonest but not before `now + lead`, as
    (node_id, unix time it is due back), or None. Night-only nodes are never picked (the
    probe can't gather them by day). Each `depleted` entry is [node, unix time, respawn s,
    night_only]; every bot hears the same s2c_node_state, so a node's latest emptying is
    the earliest report within REPORT_SPREAD of its newest report.
    """
    reports = {}
    for s in rows.values():
        for d in _b(s, "qa_gather_ledger").get("depleted", []):
            if len(d) >= 4 and d[3]:
                continue
            reports.setdefault(int(d[0]), []).append((float(d[1]), float(d[2]) if len(d) > 2 else 180.0))
    best = None
    for node, rs in reports.items():
        newest = max(t for t, _ in rs)
        at, respawn = min((t, r) for t, r in rs if t >= newest - REPORT_SPREAD)
        due = at + respawn
        if due < now + lead:
            continue
        if best is None or due < best[1]:
            best = (node, due)
    return best

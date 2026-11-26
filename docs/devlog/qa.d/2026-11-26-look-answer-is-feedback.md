# 2026-11-26: a saved look is answered (fun metrics)

`main` went red after PR 230 (no levels): `longest_wait_s_median` 6.36 s against 0.05 s
(+2.0 slack). The metrics now name the press behind each bot's longest wait
(`longest_wait_after`, `longest_wait_from_s`): every one was `c2s_set_look`, about 54 s in.
The server does answer it (s2c_look naming us, which gameplay_looks_v8 checks), but the fun
metrics never counted that as feedback. Before, the bots gathered until Felling 2 and the
XP and level lines landed right after, so the wait closed by chance; with levels gone the
bots stop after FARM_GATHERS and the wait ran until the next gather (up to 36 s locally,
31 s on CI). Fix: s2c_look for us and s2c_place_result count as feedback. Local 8 x 180 s
WebSocket + Postgres run: wait median 0.15 s, worst 0.16 s, PASSED. No baseline change.
Note: a local run after PR 229 needs `godot --headless --path game --import` first, or
TravellerBodies isn't in the class cache.

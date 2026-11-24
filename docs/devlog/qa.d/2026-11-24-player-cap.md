## 2026-11-24: the 8-player cap on Railway and in the bot test (`ws/qa/player-cap`)

**Fun:** the always-on world is a friends' world of 8 for real now: a ninth player is told
politely that it's full and walks in the moment a friend logs off, and nobody inside is ever
bumped. Every long bot test proves that with nine live bots.

**Built (qa paths, plus one fix in a behaviour under `tests/`):**
- `Dockerfile`: `ENV MAX_PLAYERS=8` (gameplay's cap from #199; unset means no cap, so local
  runs and the main bot test stay uncapped). `run_image_test.py`'s `REQUIRED_ENV` checks the
  image sets it, and the boot scenario checks the log says `[server] player cap: 8`, so a typo
  in the ENV can't silently leave Railway uncapped.
- Player-cap phase in `run_bot_test.py` (long runs only, after the chat gate; skip with
  `--no-player-cap`): a third server with `--max-players=8 --dev-commands=0`, eight
  `--single-login` bots (the first plays 22 s, the rest 55 s), and once the log shows all
  eight logged in, a ninth with `--retry-when-full`. Checks: the ninth was refused at least
  once with exactly "The world is full (8 / 8). Try again soon.", got in only after the
  leaver's "left" line, no stayer left before it got in, no bot ever saw more than 8 players
  (behaviour `qa_player_cap`), and the usual bot checks (nobody dropped, chat heard, 7 peers seen).
  Local: refused 10 times, admitted 20.7 s after it first knocked, ~60 s for the phase.
  Full run: unit 830/830 (Postgres), bot test 8 x 180 s WebSocket + Postgres with fun and perf
  checks PASSED in 337 s (hunter downed 1, 2 toasts); ENet 45 s smoke PASSED (first build).
- `bot.gd`: `--single-login` (no disconnect/reconnect cycle, one login expected) and
  `--retry-when-full` (a full-world refusal closes the connection and tries again every 2 s;
  once in, plays at least 15 s). Why reconnect each time instead of re-sending the login on
  one connection: the server kicks after 5 attempts on one peer, and a real player's client
  reconnects too.
- `CAP_PLAYERS = 8` must equal the Dockerfile's value; `test_player_cap.py` checks that, plus
  the log checks (7 cases). `test_qa_player_cap.gd` (4) checks the behaviour's expected text is
  exactly the server's `world_full_text()` on a full server, and that it stays quiet uncapped.

**Fixed a flake I hit on the way: `gameplay_hunt` after a missed haymaker.** My first full run
failed "brought grazer 4 down but the pack never got its hide and meat". The server log had a
light hit on grazer 4 and no heavy hit and no `[hunt]` line: the haymaker had *missed*, the
behaviour re-lured and then went straight to the jab, which can't down an unhurt grazer. Now a
miss re-lures and swings the haymaker again (`_wounded`), with at most 3 misses per hunt
before it fails. `tests/` is qa's path; gameplay should know (it's their behaviour), so it's in
this note rather than a request: nothing for them to do.

**Didn't work / environment:** the first run's perf check said "players_measured 0": this
container had no `ss` (iproute2). Installed it; CI has it. No Docker daemon here, so the image
test runs only in CI.

**Next run:** check this landed and the image test is green in CI. Then the bot-test hunt with
swing metrics (backlog item 2), then the restart-in-the-middle check (part 2).

# Night walkers in the bot test (ws/builder/night-walkers)

**What:** a fourth phase in long bot-test runs, `run_bot_test.run_night`. A server boots with
`--gloam=1 --dev-commands=0 --clock-offset=<to midnight>` (`night_clock_offset` computes it from
the same epoch, day length and start fraction as `WorldClock`; a unit test checks they match),
and four bots run behaviour `qa_night_walkers` for 60 s each, with the usual reconnect in the
middle. Each bot walks to its own post 55 m out (past `Gloam.SAFE_RADIUS`), throws a light swing
at the air every 4 s to make noise, goes for the nearest walker in `s2c_gloam` within 45 m,
faces it and throws heavy haymakers once it's within 1.6 m. The server log must show walkers on,
night on the clock, at least one grab and at least one walker put down; every bot must see
walkers; nothing on the wire may be non-finite or in an unknown state; a walker we downed must
leave `s2c_gloam` within 1 s.

**Why not `--gloam` on the main server (the item's literal wording):** the main run's gather,
pair, tool-gate and persistence checks assume a quiet world, and a knock-down teleports a bot to
Spawn Meadow mid-check. Making all of those tolerate walkers would touch `gameplay_vitals.gd` and
the gather behaviours, which the owner's open survival-kit PR (#232) changes. A separate phase
tests natural rising against a group, which is what the live world runs, without touching any of
the owner's files. It also runs with dev commands off, like the public server.

**What I saw locally (enet, 4 bots, 60 s):** each bot saw ~16 walkers rise; 11 walkers put down
in total. On the first try with bots that always swing first, **nobody was grabbed at all**:
bare-handed haymakers (9 damage, 4 to put one down) beat the grab every time. So each bot now
lets the first walker of each login grab it once (or waits 6 s) before swinging back; with that,
3 grabs per run. That is a fun signal, not just a test detail: a first night where you never get
touched isn't scary. Passed on to gameplay as a request.

**Cost:** about 70 s more on the CI bot test (the phase only runs in long runs; `--no-night`
skips it).

**Next self:** if the night phase flakes on "no walker grabbed anyone", raise `LET_GRAB_MAX` or
let the first two walkers in; never drop the grab check. Knock-downs are counted, not required.

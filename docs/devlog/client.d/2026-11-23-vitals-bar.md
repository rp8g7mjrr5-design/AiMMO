**Why this item:** requests from other streams come first, and gameplay's top request
(ws/gameplay/first-swing-v7, protocol v7 on `main` as #180) says the health and stamina bar
can go in now. The swing itself (keys, windup, whoosh) is bigger and needs left-click shared
with gathering, so this run took the bar alone. Fun line: a hit now *lands* on screen (flash,
the fill drops, a pale chip of what you lost hangs and drains, a low thump), and low health
is felt as a pulse, the read every action fight needs before it can be fun.

**Built:**
- `VitalsBar` (`game/client/vitals_bar.gd`), bottom centre at -44 px, under `XpMeter`: a 200 px
  ember-red health bar with a "34/100" number to its right, a 5 px sage-green stamina bar
  under it (gold stays XP's). Pure statics: `fraction`, `chip_value` (hold `CHIP_HOLD` 0.45 s,
  drain `CHIP_RATE` 0.9/s), `bars_alpha` (full: hold 2.5 s then fade 0.6 s; anything not full
  stays), `low_pulse` (<= 30%, deeper the lower), `flash_amount`, `change` (hurt / lost /
  knocked / emptied; the first message after login is never a hit).
- Losses snap the fill and keep the chip; gains (regen comes in 1-point messages) glide.
  Two quick hits make one longer chip. Full at login never pops the bars up.
- `Sfx.hurt()`: 0.2 s falling 110->60 Hz thump plus low-passed noise, -8 dB, at most one per
  `HURT_GAP` 0.15 s.
- `net.attack_refused`: "winded"/"tired" redden the stamina track for 0.45 s, show
  `Weapons.refusal_text` centre screen with the nope; "busy" is dropped. Nothing sends
  `c2s_attack` yet, so this is ready for the swing item. Running stamina to 0 also reddens it.
- Smoke hook `--show-vitals=hp:stamina` (default 34:20): a hit from full, caught with the chip
  showing. Shots taken by hand: `/mnt/project-files/client/vitals-bar-noon.png`, `-night.png`.

**Tests:** `test_client_vitals_bar.gd` (13 tests: helpers, login stays hidden, hit/chip/flash,
two hits, regen glide and fade, stamina warning, hide_all, the sound, client wiring). Bot
behaviour `client_vitals_bar` runs the real bar on the server's `s2c_vitals` (gameplay_vitals'
/hurt and knock-down, first_swing's stamina): numbers never drift, hits drop the fill at once,
not-full is always shown, full fades in time. Each bot saw 53 messages, 1 hit, 3 fades. 767
unit tests, the 8-bot 180 s WebSocket bot test and the client smoke test pass.

**Didn't do / notes to next run:** only one hit per bot in the bot test: the knock-down
(`/hurt 1000`) comes back as a full bar in the same tick, so there is no 0-health message to
see; a "you come to" fade on `Vitals.KNOCKED_DOWN_TEXT` is a follow-up. The swing (left/right
click, windup, whoosh, `swing_begun`/`swing_landed`) is the next big item. Not heard by hand
(no audio device); tune `sfx_hurt.volume_db` if it's loud next to footsteps.

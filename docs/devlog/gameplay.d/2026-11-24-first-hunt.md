**Picked.** The top open follow-up that needs nobody else: "the gentle first hunt" (grazer hp,
hide and meat drops, respawn). The other open items wait on client (dodge input, toasts),
world (weapon icons) or are "watch the numbers". Fun in one sentence: you creep up on a
sleeping herd at night, land a haymaker, the wounded grazer limps off slower than you can
walk, you run it down and finish it with a jab, and your pack holds a hide and two raw meat.

**Built (no protocol change).**
- `Wildlife.KINDS.grazer` has `hp` 12 and `drops` `[["hide", 1], ["raw_meat", 2]]`.
  `Wildlife.strike(state, id, from, now, damage = 0.0)` takes the damage; at 0 hp the grazer is
  down (`down_until`, `downs`): off `to_wire`/`to_wire_near`, not in `targets`, its herd still
  scatters, and `step` raises it at home whole after `RESPAWN_SECONDS` (180).
- Wounded (below full hp) flees at `WOUNDED_FLEE_SPEED` 5.0 (walk is 6): a chase you win. A
  wound heals after `HEAL_SECONDS` 60 untouched.
- `Wildlife.bolt_distance(night)`: at night grazers bolt only at `NIGHT_BOLT_RADIUS` 1.0 m
  (by day 4.5). Without this nothing could ever be hit: fists reach 2.0 m to a grazer's
  centre and a day grazer bolts at 4.5 m, so the first swing (#180) could only ever whiff.
  At night the existing creep-and-freeze rules (alert, settle, `tolerated` shrinking by
  `SETTLE_STEP`, rest scale 0.45) walk a patient stalker in to about 1.9 m; unit tested.
- Server `_land_swing` passes `Weapons.damage`, and `_hunted` gives the downing hunter the
  drops through `give_item` (so `s2c_inventory` goes out); `[hunt]` log line; `sessions[id].hunted`.
- `hide` and `raw_meat` sit in `Inventory.UNDRAWN` until world draws them.
- Hidden dev command `/lure` (`ChatCommands.is_lure`, `Server.lure_command`, `Wildlife.lure`):
  the nearest standing grazer (a wounded one first) lies drowsy 1.6 m in front of you for
  5 s. Bots only; a real night stalk depends on the wall clock and takes a minute.

**Why these calls.**
- *No toast yet.* `s2c_gather_result` would give a toast and haul sound for free with no
  bump, but client's `client_item_icons` bot behaviour fails any toast whose item has no
  icon of its own, and `hide`/`raw_meat` have none yet. So the pack gets the haul silently
  for now; the day world's icons land, `_hunted` sends `s2c_gather_result` per drop (one
  line, the comment there says where). Nobody can attack from the real client yet either
  (no attack key on `main`), so nothing is lost today.
- *Downed = off the wire* rather than a new "down" state: `HerdView` drops a missing id
  cleanly, while an unknown state index would draw a grazing grazer. A fall pose wants a
  `down` state in `Wildlife.STATES` that client and world draw first (requests filed).
- *No hunting XP.* A new skill in `Skills.ORDER` changes every player's total level in the
  roster and the skills window's rows; that wants client in step. Follow-up.
- *Hunter gets everything.* Whoever lands the downing blow; sharing between hunters waits
  for parties.
- Day hunting stays near impossible with fists (and a spear's 3.0 m reach still loses to
  the 4.5 m bolt): the hunt is a night thing until weapons and a crouch exist. That fits the
  grounded look (hunting at dusk and night) and makes the night worth going out in.

**Tests.** Unit 770/770 with Postgres (new `test_gameplay_hunt.gd`, 12 tests: hp and drops
are items, two bare-handed blows (haymaker + jab) or three jabs down one, a wounded one runs
at most 5 m/s, a walker catches it within 4 s, heals after 60 s, downed is off the wire and
targets and rises at home whole, a night stalker gets within reach without a bolt, by day
you can't, the server hands the hunter 1 hide + 2 raw meat and the onlooker nothing, the
server's s2c_wildlife leaves it out, `/lure` and it prefers a wounded grazer;
`test_gameplay_toolcraft` no longer asserts `UNDRAWN` is empty, only that the ember tools
left it). Bot test 8 x 180 s WebSocket with `--fun-check` PASSED: the hunter bot (`*_2`)
lured, landed the haymaker, re-lured the wounded grazer, jabbed it down, got hide and meat
in `s2c_inventory`, and never saw it in `s2c_wildlife` again; fun first reward 8.0 s, dead
median 25.8 s, 10.95 rewards/min, 8 of 8 levelled. Client smoke test passed. No bandwidth
numbers here (no `ss`).

**Next run:** if world has drawn `hide` / `raw_meat`, move them into `ITEMS`/`ITEM_ORDER`
and send `s2c_gather_result` per drop from `_hunted` (the toast). Then `c2s_dodge` in the next
bump, or recipes that use hide and meat (cooked meat at a campfire, a hide wrap).

**Caught after merging `main`:** two server-level tests (`test_gameplay_protocol_v6`'s bolt
test, `test_gameplay_wildlife`'s server tick test) put a player 3.5 m from a grazer and
expected a bolt; the server reads the wall clock, so at night (the drowsy 1.0 m ring) they
failed. Both now pin `clock_offset` to noon. The second 8 x 180 s bot test ran at night
(world 01:05) and passed, including `gameplay_wildlife`'s rush check (a rushing player still
spooks a sleeping herd when the 1 s alert runs out) and the hunt.

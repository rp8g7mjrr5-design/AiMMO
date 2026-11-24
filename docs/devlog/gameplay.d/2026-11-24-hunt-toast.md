**Built: the hunt toast (no protocol change, no migration).**

*Fun:* the moment a grazer drops, "+1 Hide" and "+2 Raw meat" pop with their own icons and
the haul sound, so the first hunt pays out loud instead of silently filling the pack.

- `Server._hunted` sends `s2c_gather_result(item, added)` to the hunter for each drop that
  fit (a full stack gets no toast for that drop, like a gather). On Net/Play since v3, and the
  client's `GatherPrompt.on_result` already turns it into the toast with the item's icon.
  The wounding blow sends nothing; onlookers get nothing.
- `hide` and `raw_meat` left `Inventory.UNDRAWN` (now empty again) for `NEW_ITEMS`, not
  `ITEMS`/`ITEM_ORDER`. *Why:* putting them in `ITEM_ORDER` (after veinstone, with the raw
  materials, where they belong) fails client's `test_client_pack_window` (it asserts 15 slots
  for "every ITEM_ORDER item plus one"; 16 stacks make 20). That test is client's file, so I
  filed a request to make it count-independent and used `NEW_ITEMS`, which exists for exactly
  this ("drawn but not in ITEMS yet"). Effect for players: the two stacks show after the
  ordered ones in the pack instead of next to stone. Saves are unaffected either way (the
  stored id is the same).
- The client picks its haul sound by node kind, so a hunt toast plays the ash sound. Fine
  for now; noted for client.

*Tests:* unit 826/826 with Postgres. `test_gameplay_hunt`: the server test now expects
`[["hide", 1], ["raw_meat", 2]]`; new: the toast only on the downing blow and only for the
hunter, a full hide stack toasts only the meat that fit, and the drops are drawn items with
their own icons and distinct tints, held after the ordered stacks. Bot behaviour
`gameplay_hunt` also checks the toast (each drop toasted with the count that fit, none after
the haymaker; stat `toasts`). Bot test 8 x 180 s WebSocket with `--fun-check` PASSED: the
hunter downed one grazer and got 2 toasts; client's `client_item_icons` and
`client_gather_prompt` behaviours, which fail any toast without its own icon or with a wrong
count, stayed green. First reward 7.7 s, 10.77 rewards/min, 8 of 8 levelled. Client smoke
test passed.

*Next run:* if client changed the pack test, move hide and raw meat into `ITEMS`/`ITEM_ORDER`
after veinstone (one line, plus the hunt test's order check). Then part 2 of owner direction
8 (world config on the wire) once #197's v8 has landed, with the stance events if they fit.

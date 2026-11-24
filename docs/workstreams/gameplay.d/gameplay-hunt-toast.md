Done: **Hunt toast (finishes the first hunt; world's icons are on `main`, #200).** (ws/gameplay/hunt-toast)
`Server._hunted` sends `s2c_gather_result(item, count)` per drop that fit, to the hunter only; `hide` and `raw_meat` left `UNDRAWN` for `NEW_ITEMS` (not `ITEMS` yet, see follow-up). Also answers world's `from-world-hunt-drop-icons` request and the first follow-up in `gameplay-first-hunt.md` (integrator: fold as one).

Follow-ups:
- [ ] Move `hide` and `raw_meat` from `Inventory.NEW_ITEMS` into `ITEMS` and `ITEM_ORDER` (after `veinstone`) once client's `test_client_pack_window::test_window_follows_the_server` stops hard-coding 15 slots (request filed with client). One-line change, no save impact; also flip `test_gameplay_hunt::test_the_drops_are_drawn_items_in_pack_order` to expect them before `stone_axe`.
- [ ] A hunt haul sound of its own: the client picks the haul sound by node kind, so a hide or meat toast plays the ash sound today (fine, but a soft thud would read as a hunt). Client's call; mention when asking for the pack-test change.

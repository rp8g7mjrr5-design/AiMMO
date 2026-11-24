Done: Follow-up (first swing, 2026-11-24): grazers have no health yet ... The gentle first hunt (ws/gameplay/first-hunt)
Grazers have 12 hp, a wounded one limps at 5 m/s, a downed one gives its hunter 1 hide + 2 raw meat, leaves the wire and rises at home after 180 s; night herds bolt only at 1 m so a stalker can reach them; hidden `/lure` for bots.

Follow-ups:
- [ ] Hunt toast: once world draws `hide` and `raw_meat` (request filed), move them from `Inventory.UNDRAWN` into `ITEMS`/`ITEM_ORDER` and send `s2c_gather_result(item, count)` per drop from `Server._hunted`, so a kill pops "+1 Hide" with the haul sound.
- [ ] A `down` state for a fall pose: append "down" to `Wildlife.STATES` and keep a downed grazer on the wire for a few seconds before it leaves, once client and world can draw it (requests filed); today it just vanishes.
- [ ] Hunting XP: a `hunting` skill (XP on a down, more for a clean stalk) once client's skills window and roster are ready for a fifth skill.
- [ ] Use for the drops: cook raw meat at a campfire (a food item that restores health or stamina faster) and a hide recipe (wrap or pouch), so the hunt pays into the crafting loop.
- [ ] Watch the hunt once the attack key is out: day herds can't be reached with fists or a spear (bolt 4.5 m > reach). If players never try at night, consider a crouch-walk that halves the alert ring rather than shrinking the bolt ring by day.

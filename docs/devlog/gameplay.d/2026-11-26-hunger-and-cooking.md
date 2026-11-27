# Hunger and cooking (owner's survival thread, branch claude/project-thread-wnmu97)

Step 1 of the owner's survival plan (roadmap Phase 2, "The survival plan"; design bible revision 2026-11-27).

**What shipped.** `game/shared/needs.gd` holds every number: hunger 0..100, full to low in about 30 real minutes, empty in an hour, drains only while logged in. Tiers fine / low / bad: low scales stamina regen by 0.75, bad by 0.5, stops the out-of-combat heal and wears health to `HP_FLOOR` (15), never lower. `Vitals.tick` grew two optional args (regen scale, heal allowed) so nothing else changed. Foods: cooked meat 40, berries 10, raw meat 15 and 8 health (never below 1). Eating and cooking ride on `c2s_place` ("eat", a food id, "cook"), so the only new RPC is `s2c_needs(Dictionary)` on Net/Play (protocol 12; frozen `net_v11.gd` / `net_play_v11.gd`). The Dictionary leaves room for thirst, warmth and rest without another bump. Saved as `characters.hunger` (migration 0006, default 100) and in the JSON store through CharacterData; a wipe and a knockdown (at least 50) refill it. Scrub's `also: {berries: 1}` is a new optional field in `ResourceNodes.KINDS`; the server sends a second `s2c_gather_result` for it.

**Client.** `NeedsIcon` (cooked-meat icon, straw when low, slow SMOULDER pulse when starving, a thin fill, "[F] Eat" hint the first few seconds) sits left of the vitals bar and is invisible while fed. F eats (new `eat` action). At a lit fire with raw meat the gather prompt shows "[E] Cook N raw meat". New procedural sounds `Sfx.eat()` and `Sfx.sizzle()`. Berries got an icon and two palette colours (`BERRY`, `BERRY_SHINE`).

**Tried and dropped.** Cooking as a craft-window recipe: the craft window only opens at the bench, so it could never be used at a fire.

**Next self.**
- The tier lines ("You're getting hungry. Press F to eat.") go to the chat feed as system lines; a notice-line version that respects the clean-fight rule would read better.
- Spoiling (plan step 6) will need a per-stack age; keep `cooked_meat`/`raw_meat` ids, add a freshness field rather than new ids.
- The character level (plan step 7): cooking should pay XP from the count `cook_request` returns.

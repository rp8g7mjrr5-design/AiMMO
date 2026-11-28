Done: **Basics 2: walkers rise at ruins** (more at higher grades) (ws/builder/ruin-guards)
Guards rise on a ruin's pad when a player comes within 50 m of it, by grade (day 1/2/3/4, night 2/4/5/7), refill one at a time, never within 18 m of a player.

Follow-ups:
- [ ] **Guards for the beach landmarks** (wreck and shack are `BeachGen` loot spots, not `Ruins.all()` sites), if a beach's loot comes too easy: one walker by night only, so a fresh player's beach stays safe by day.
- [ ] **Ruin guards in the bot test** (qa): CI plays Ashgrove, which has no ruins. Fold into qa's "Basics 3: the island in the bot test": a bot walking to the nearest grade 1 ruin is met by its guard.

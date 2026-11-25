Done: **Basics 2, zombie survival: turn the walker on.** "Walkers on the wire in the next bump: `s2c_gloam` ... walker ids in `s2c_swing_hits`" (ws/builder/gloam-on-the-wire)
Protocol v10: `s2c_gloam` (walkers in view with the grab windup, 5 Hz) and `s2c_gloam_hits` (walker ids struck and downed). The rest of the item stays open as the follow-ups below.

Follow-ups:
- [ ] Next bump: `c2s_dodge(yaw)` (a short dash through `Vitals.spend("dodge")`, cancels a swing in windup).
- [ ] Walkers rise **at ruins** (more at higher grades), once world's burned farmstead is on `main`.
- [ ] Turn `--gloam` on for the live world once client draws the walker (world's look item).

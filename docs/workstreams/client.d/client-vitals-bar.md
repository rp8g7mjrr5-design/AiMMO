Done: From gameplay (2026-11-24, ws/gameplay/first-swing-v7): "the health and stamina bar can go in now" (ws/client/vitals-bar)
`VitalsBar` under the XP bar on `s2c_vitals`: flash, chip and thump on a hit, low-health pulse, fades when full; winded/tired refusals redden the stamina bar. The swing part of that request is still open.

Follow-ups:
- [ ] Follow-up (vitals): the first swing on v7: left click light / right click heavy when nothing gatherable is aimed (`click_use` shared with gathering), `c2s_gather_cancel` then `c2s_attack` mid-gather, windup + whoosh on `swing_begun` for everyone in view, a flinch on `swing_landed`.
- [ ] Follow-up (vitals): a short "you come to" moment on a knock-down (`Vitals.KNOCKED_DOWN_TEXT` arrives as a system line): fade to dark and back in over about a second at the Spawn Meadow arc.
- [ ] Follow-up (vitals): smoke screenshot with `--show-vitals=34:20` (hook in `client.gd`; qa owns `tests/client_smoke/run.sh`). Taken by hand: `/mnt/project-files/client/vitals-bar-noon.png`.

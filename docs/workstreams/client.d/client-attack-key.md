Done: **Basics 2: the attack key (v7 is on the server, unused).** (ws/builder/attack-key)
Left click light / right click heavy when not gathering, gather-cancel then attack, whoosh at the blow, smack and grazer flinch on a hit, F1 lists it.

Follow-ups:
- [ ] Predict your own swing locally (animation and whoosh on the press, reconciled with `s2c_swing`), with the client-side stamina check so a "winded" swing never shows. *Fun: the swing answers the click instantly on any connection.*
- [ ] A tiny hit-stop and camera kick when your blow lands (`s2c_swing_hits` non-empty), restrained per art bible section 11. *Fun: hits feel like hits.*

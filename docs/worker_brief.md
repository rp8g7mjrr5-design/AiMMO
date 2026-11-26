# Worker brief (read this instead of the bibles)

One page for every automated run (owner, 2026-11-25: runs cost the owner's usage, so read
this and only open a bible section your item names). `CLAUDE.md` still comes first; this
file never relaxes a hard rule. The integrator keeps it current when the bibles change.

## The game
ZombAi: a grounded, third-person open-world zombie survival sandbox. A fallen medieval
kingdom on generated maps with risk-graded ruins, the Zombai (our undead), building and
surviving on servers of up to about 100 players, each with its own rules. One-time buy.
**Not an MMO.** Today's live Railway world is one such server, capped at 8: never break it.

## The current goal: the basics first (design bible, owner direction 9)
Until these four play end to end in a real session, they come before any polish:
1. **Character customization** on the cartoon body (goofy folk, owner 2026-11-26): every saved Appearance choice shows,
   and a new player picks a look before they play.
2. **Zombie survival:** the Zombai walker on screen and in the fight, hunger, the first night.
3. **A generated map** from a seed (roadmap Phase 1), big enough to explore, fast to load.
4. **Landmarks with loot:** ruins seen from a distance, walked to, searched for loot worth
   the walk (crates, chests, bodies, graded by the ruin).
Nothing left on the basics? Fix bugs or add tests for the basics before polishing anything.

## Fun comes first (the first rule)
If it isn't fun, it isn't worth shipping. Before you build, write one sentence on what a
player will feel that they didn't before. In practice: every action answers within about
100 ms (sound, motion, flash, number); a first reward within about 60 s of spawning; every
loop ends in a payoff you can see, hear and use; no dead time; always one clear next goal.

## No levels (design bible, owner direction 5, 2026-11-26)
No levels, XP, skill trees, perk points, "mastery" or any bar that fills by repetition. You
get stronger through tools (an axe opens the old ember ash, a pickaxe the rich seam), gear,
the base and what you know. Gate things by a material, a tool, a station or a place. Old XP
in saves is kept untouched and never read; the old skills RPCs stay as do-nothing slots.

## A clean fight (design bible, owner direction 10)
No text on screen in a fight: threats, blows, kills and knock-downs are told by motion and
sound only. Full speed only forward; backing off is a walk, capped on the server. Animations
blend, feet hold the ground, nothing plays twice or snaps.

## The look (art bible sections 0, 11, 12)
Grounded, not cute: real proportions, muted earthy colours (naturals under about 0.45
saturation), the ember glow only on things you can use, clear sunny days and real nights,
restrained effects and UI. The exception is the characters: survivors and the Zombai are
goofy cartoon folk (`Toon`; big heads, googly eyes, short legs) in the same muted colours
(owner, 2026-11-26; art bible section 3). Everything procedural (`game/procgen/`), colours from
`palette.gd`, inside the render budget. Nothing named, shaped or laid out after another game.
If your change shows something on screen, read art bible sections 0, 11 and 12 before you
start, and put before/after shots in the PR.

## Never (vision)
- Tell players about a feature before it is on `main` and in the bot test.
- Sell power, safety or progress.
- Add levels, XP or a skill tree (owner, 2026-11-26).
- Lose a player's save, world or character (add-only migrations, old saves always load).
- Make a death the player couldn't have seen coming.
- Break the official world or raise its cap past what the load test proved.
- Let a server's rules be a surprise.

## Hard rules in one breath (CLAUDE.md has the full text)
Add-only migrations; all tests green before anything lands (CI gates the merge); all art and
sound procedural; no secrets in code; one small finished feature per PR with auto-merge on
and nobody calling merge; never break save compatibility.

## The owner works on the game too
Jacob builds on the side. His branches and PRs (anything not on `ws/`, `claim/` or
`integrate/`) are his: never edit, close, rebase, revert or turn on auto-merge for them, and
stay out of the files they change (`docs/workstreams.md`, "The owner's own work").

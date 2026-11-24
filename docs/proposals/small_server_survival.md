# Proposal: a small-server survival game with faction claims

**Status: proposal only, not the direction.** Written 2026-11-24 because the owner is weighing
a change of direction: "small persistent world, Project Zomboid type game with randomly
generated maps and land claim for up to a certain amount of players", with land claims in the
spirit of the old Minecraft *Factions* plugin. Workers: do **not** build from this file. Until
the owner picks a direction, `CLAUDE.md`, `docs/roadmap.md` and the backlogs are what you
follow. The other option on the table is the towns-MMO vision in PR #184.

Everything below is our own design under "Inspired by, never copied" (design bible): the
reference games are named only here, to say whose *feel* we mean. No names, terms, UI, art or
text from them.

## 1. The pitch in one paragraph
Each server is a living, randomly generated valley that holds **32 to 48 players** and lasts
for a season. You arrive with nothing. Staying alive is the first game: hunger, thirst, the cold
of the night, wounds that need tending, food that spoils, and the **Hollows**, the people and
animals the Dimming has emptied, who wander by day and gather at night, drawn to noise and
light. The second game is your band: a few friends who build a shelter, then walls, then a
hold, and stake their land with a claim stone. A band's grip on its land is only as strong as
its members' **resolve**, which grows while they are online and alive and drops each time one of
them dies. Reach too far, or lose too many fights, and another band can break your walls and
take what you built. It is the deep, slow survival sim and the tense small-world politics in one
game, at a size where everyone on the server knows everyone else's name.

## 2. Why this could be the better call (and why it might not)
**For it.**
- **Scope a small team can actually finish.** A 32 to 48 player server is a well-understood
  problem; a thousands-strong MMO is the thing that sank the last big crowdfunded one
  (`docs/research/promises_study.md` on PR #184). Our server already sends every player to every
  player; at 48 that is fine, at 500 it isn't.
- **Random worlds give replay value for free.** Every season is a new map to learn, and a
  procedural world is what this codebase is already built around (hard rule 3, seeds).
- **Emergent stories.** Factions-style politics (alliances, betrayals, raids, a band over-reaching
  and falling) make content out of players, which an autonomous team can't hand-write fast enough.
- **A crowded genre has a gap.** Deep single-player-style survival sims are rarely built for
  small persistent servers with real territory; land-claim servers are mostly block games.

**Against it.**
- **Survival-sim depth takes years.** The reference sim has had more than a decade of
  development. We would ship a much thinner version and grow it; it will feel thin for a while.
- **PvP raiding is harsh.** Losing a base to a stronger band drives players away; the original
  plugin's offline raiding was its most hated part. Our design has to fix that (section 5).
- **Many servers cost money and operations.** Each server is its own process and database rows.
  We'd start with one public server.
- **It throws away the MMO framing** (the North star, owner directions 4 and 5 in their current
  words, and the towns vision in PR #184). Most of the *code* carries over (section 7); most of
  the *plan* does not.

## 3. Server size
Recommendation: **32 at first, 48 as the target, 64 as a stretch** once qa's perf gates show it
holds. Reasons: 32 is the size where a server feels busy but everyone can learn each other's
names; the reference sim's own developers asked server hosts to stay at about 20 during its
multiplayer test [SB] [LS]; and the Hollows (many creatures near players) cost more than players
do. The cap is a server setting, raised only when the bot test's perf numbers at that count pass.

## 4. Surviving (the first game)
All stats live in one data file each, tuned like the skill curve.
- **Needs:** hunger, thirst, warmth (nights are cold, rain is colder, fire and clothes help),
  fatigue. Each shows as a quiet icon only when it matters (art bible section 9).
- **Wounds:** cuts that bleed until bandaged, bites that can fester, a sprain that slows you. Few
  kinds, each with a clear cure, never a hidden timer that kills you without warning.
- **Food and fire:** forage, hunt, fish later; cook at a fire; food spoils, salting and smoking
  keep it. Farming plots in later phases.
- **Carry weight** instead of a grid: heavy loads slow you; bags carry more.
- **Skills, the long road kept:** our existing skills system carries over. Survival skills
  (Felling, Quarrying, Toolcraft, plus foraging, cooking, tending wounds, carpentry, masonry,
  weapon masteries) level by doing, with an unlock every few levels.
- **Death:** your body stays where you fell with everything you carried, for anyone to loot. You
  come back at the server's spawn or your band's hearth with a few starting items. What you keep
  is an owner choice (section 10).

## 5. Bands, claims and resolve (the second game)
Our own version of the Factions idea, with its known pain points fixed.
- **Bands.** Two or more players form a band (a name, a banner colour, ranks: leader, officer,
  member, recruit). Relations with other bands: allied, neutral, at feud.
- **Resolve.** Each member has resolve from 0 to 10, starting at 5. It climbs about 1 per hour
  online and alive, and regains slowly while offline (to a floor of 5, so real life isn't
  punished). Death costs resolve: more when killed by a player than by the world. A band's resolve
  is the sum of its members'.
- **Claims.** A band stakes land by building a **claim stone** and claiming square plots (32 m)
  around it, joined to each other. Inside its plots only the band and its allies can build, open
  doors or take from containers, and the Hollows don't spawn.
- **Over-reach.** Each plot costs 1 resolve to hold. When a band holds more plots than its resolve,
  it is **over-reached**: its walls and doors can be broken by anyone at feud with it, and its
  outermost plots can be claimed over by another band. Lose members, die a lot, or stop playing,
  and your hold shrinks; stay active and alive and it holds.
- **Breaching, not griefing.** Raiding means breaking doors and walls with tools and crafted
  breaching gear, which is loud (it draws Hollows) and slow (minutes per wall course). Builds
  are made of tiers (wood, stone, reinforced), each slower to break.
- **The offline fix.** While every member of a band is offline, its walls take a quarter of the
  damage, unless the band is over-reached. So a band that keeps its claim in line with its
  resolve can log off safely; an over-reached one can't. This keeps the Factions tension (don't
  over-extend) and removes its worst part (losing everything while you slept).
- **The waystation.** Each world's spawn is a neutral safe zone that no one can claim and where no
  one can fight. The whole server raises it together with shared projects (a trader's stall, a
  better bench, a notice board): the community-built town from PR #184, scaled to one per server.

## 6. Threat options (owner choice)
| Option | What it is | For | Against |
|---|---|---|---|
| **A. Wilderness only** | Wolves, boars, bears, storms, cold, hunger. | Grounded; fits the art direction as it stands. | Thin pressure at night and on bases; little reason to build walls against the world. |
| **B. Zombies** | The undead, hordes drawn by noise. | Instantly understood; proven tension. | The most crowded setting in survival games; hard to stand out; easy to look like the reference games. |
| **C. The Hollows (recommended)** | Our own lore: the Dimming drains the warmth from people and animals and leaves Hollows, slow by day, faster and in packs at night, drawn to noise and light, and gathering around a band that makes too much of either. Plus real wildlife. | Gives us horde and base-siege mechanics with an identity of our own; keeps Ashgrove's lore and the grounded look (grey, ash-cold silhouettes, no gore needed). | Has to be taught: players don't arrive knowing what a Hollow does. |

## 7. What carries over from today's build
| Keeps as it is | Changes | Goes |
|---|---|---|
| Godot client and headless authoritative server, WebSocket on Railway, Postgres, accounts | World: one fixed 512 m Ashgrove becomes a **generated world per server** (a seed per server, about 1 to 2 km, terrain built in chunks around the player instead of all at once) | The MMO North star and "thousands on one world" |
| Gathering with E, timed bars, node depletion; the bench and crafting; the skills system and XP | Persistence gets a `server_id` everywhere (add-only); a character belongs to one server | The single fixed hand-made map as the main world (it survives as the test seed and as stamped set pieces) |
| The action camera, vitals and swings (they become the base of survival combat) | Vitals grow into needs and wounds; inventory gets weight | The towns-MMO milestone order in PR #184 (its town projects shrink to the waystation) |
| Grounded Emberlight art, render budgets, quality tiers; grazers and wildlife | A building system (snap-grid foundations, walls, doors, roofs, containers) is new and large | Owner directions that only make sense for an MMO are reworded, not deleted (fun first, chat is for talking and the camera stay) |
| CI, bot test, fun metrics, self-updating client, the worker setup | Death drops a lootable body; a hearth respawn | |

**Hand-made map vs generator, combined:** the generator lays out each server's valley (rivers,
hills, forests, ridges), then places **hand-made set pieces** written as data: ruined steadings,
a hollow-haunted mill, a lookout crag, the waystation plot. Each world is new, and each still has
places that look designed.

## 8. Phased plan (honest scope for the autonomous team)
At today's pace (dozens of worker PRs a day, budget-limited), a phase is roughly **one to two
weeks**. These are forecasts, never promises (the study's lesson 9).
1. **The turn (pivot).** Docs rewritten (design bible, roadmap, backlogs), `server_id` and a seed
   per server, the generator v1 at 1 km with chunked terrain, the current gathering and crafting
   working in a generated world. *Done when:* two servers with different seeds run side by side in
   the bot test and characters stay on their own server.
2. **Survive the first night.** Hunger, thirst, warmth, fire and cooking, the first Hollows at night,
   death with a lootable body and respawn. *Done when:* a fresh player can die of cold, of hunger
   and to a Hollow, and can learn to avoid all three in one evening.
3. **A roof over your head.** Snap-grid building in wood and stone, doors with owners, chests,
   a bedroll respawn. *Done when:* a player builds a shelter that keeps the Hollows out at night,
   and it survives a server restart.
4. **Bands and claims.** Bands, ranks, relations, resolve, claim stones and plots, build and
   container permissions. *Done when:* a band claims land, outsiders can't build or loot there,
   and resolve moves with time online and deaths, all in the bot test.
5. **Over-reach and raids.** Breaching tools and build tiers, over-reach, claiming over, the
   offline damage rule, the waystation safe zone. *Done when:* an over-reached band can be raided,
   a band within its resolve can't be raided offline, and the bot test runs a raid.
6. **The server lives.** The 32 to 48 cap with perf gates, server settings, season start and end,
   a second public server. *Done when:* qa's 48-bot run passes the perf budget and a season can
   start on a fresh seed without touching player accounts.
7. **Depth, ongoing.** Wounds and illness, farming, fishing, more Hollow kinds and hordes, more
   biomes and set pieces, carts.

**What the AI team will struggle with** (so the owner knows where their playtests matter most):
how combat and survival *feel* minute to minute, raid balance between real groups, and whether
a season's pace is right. Bots test rules; only people test whether a raid felt fair.

## 9. What doesn't change
Fun comes first; chat is for talking; the over-the-shoulder camera; the grounded art direction
and its budgets; procedural everything; add-only migrations and never losing player data
outside an announced season end.

## 10. Choices only the owner can make
1. **Threat:** wilderness only, zombies, or the Hollows (recommended).
2. **PvP and raiding:** Factions-style raiding as the default server type (recommended, with the
   offline fix and a safe waystation), or peaceful servers first and raid servers later.
3. **How long a world lives:** seasons that end on a fresh map every two to three months
   (recommended; it is what makes random maps matter, but it means changing hard rule 6 so that
   accounts, cosmetics and titles carry over while bases do not), or one world that lives forever.
4. **What death costs:** drop everything you carried and keep your skills, minus a small slice
   (recommended), or full permadeath with a fresh character.
5. **This or the towns MMO (PR #184), or a mix.** A mix is possible: this game's servers, with the
   waystation as the community town. Merging this file decides nothing; the owner's word does.

## Sources
- [SB] Shockbyte, "Project Zomboid Build 42 multiplayer" (29 Jul 2026): https://shockbyte.com/blog/project-zomboid-build-42-multiplayer
- [LS] LogicServers, "Project Zomboid B42 multiplayer released to unstable": https://logicservers.com/blog/project-zomboid-B42-multiplayer-released
- [SF] Simple Factions plugin documentation (power from members, more lost to player kills, over-claiming land when claims exceed power, offline explosion protection): https://dev.curseforge.com/projects/simple-factions/pages/information
- [KF] KFactions plugin documentation (an older variant where claims cost power per hour and land opens to others at zero): https://www.curseforge.com/minecraft/bukkit-plugins/kfactions

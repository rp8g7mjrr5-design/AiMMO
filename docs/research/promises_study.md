# Study: the big MMO promises that didn't arrive, and what we take from them

Written 2026-11-24 for the owner direction "a beautiful map with towns that build up from
community" (`docs/vision.md`). The owner asked us to study the promises of **Ashes of
Creation** (Intrepid Studios) that were not delivered, so that AiMMO can deliver their spirit.

This is an internal design study. Per "Inspired by, never copied" (design bible), we name the
reference game here and nowhere player-facing, and we take **no names, terms, stage names,
lore or system branding** from it. What we keep is the *wish* players had; the design that
answers it is ours (`docs/vision.md`).

Sources are listed at the bottom with the tag used in the text. Where sources disagree, or a
claim is unverified (lawsuits, investor allegations), it is marked as such. Facts about the
design are from the developer's pre-release statements as reported by the press; the game
changed over ten years, so treat design details as "what was promised", not as a spec.

## 1. What happened, in short

| When | What | Source |
|---|---|---|
| Dec 2016 | Announced. | [WIKI] |
| Jun 2017 | Kickstarter, about $3.27 M from 19,000+ backers (goal $750k, met in under 12 h). The founder said the game needed about $30 M in total and that he was its main backer. | [WIKI] [GI] [KOT] |
| 2018 to 2020 | A separate battle-royale spin-off ("Apocalypse") ships free in Dec 2018 and is shut down in Mar 2020. Node sieges were meant to be trialled in it first. | [WIKI] [MM2] |
| 2019 | Node design published; release then "planned for 2020". | [MM1] |
| Jul 2021 | Alpha One: paid access through a $500 package, under NDA, for a month. | [WIKI] [KOT] |
| Dec 2021 | Engine switch, UE4 to UE5. | [WIKI] |
| 2024 to 2025 | Alpha Two testing. | [WIKI] |
| 11 Dec 2025 | Steam Early Access at $50 with a cosmetic shop. SteamDB peak about 31.8k concurrent, then a decline. | [MMO] [WCC] |
| Jan 2026 | Reviews: "playable, ambitious, and nowhere near ready" (5.8/10); user review site 7/10 with long lists of bugs. | [MMO] [GS] |
| 31 Jan to 2 Feb 2026 | The founder resigns "in protest" at the board; mass layoffs (WARN notice: permanent closure, 123 jobs); sales on Steam stop; Steam reviews fall to about 30% positive. | [PCG] [GI] [KOT] [WIKI] |
| Feb to Aug 2026 | Lawsuits (a cloud provider over about $850k unpaid; staff over WARN notice and pay; the founder against the company). An IP sale is reversed; on 27 Aug 2026 a federal court appoints a receiver over the IP. | [WIKI] [GF] |
| Oct to Nov 2026 | Official development stopped; a fan-run server opens early playtests; no relaunch. | [GF] [BIG] |

Unverified claims, recorded only so we don't repeat them as fact: an investor alleges the
founder never put in his own money and that the company carried about $140 M of debt
[WIKI] [WCC]; a report says the company was sold to private equity [MMOn].

## 2. Promise by promise

### Settlements that grow from what players do (the "node" system)
**Promised.** 103 fixed sites per server, each with a zone around it. Everything players do in
the zone (quests, gathering, killing) feeds the site's experience, and it grows through seven
stages from wilderness to a metropolis over weeks or months. Merchants and bankers at stage 2,
player housing at stage 3. Four site types fixed by the map. A site reaching stage 3 turns its
less-grown neighbours into vassals that cannot outgrow it, so the map settles into a few big
cities with satellites. Sites need daily experience to hold their stage and lose one stage at a
time when starved. Building comes from NPCs: players don't place buildings, they raise the
stage and elected leaders choose building types. [MM1] [HH] [PCG17]

**What shipped.** Reviewers in early access found nodes "largely inert": no visible world
change from node development, influence that stayed local, elections something people talked
about in chat rather than did. Others listed "dynamic cities" as a strength without detail.
[MMO] [GS]

**Why it fell short.**
- *The payoff was abstract.* Contribution was a number in a far-off bar; the town was built by
  NPCs when a stage flipped. Players couldn't see their own work in the world.
- *Designed for a population and a time span it never had.* Weeks-to-months stage climbs, 103
  sites per server and vassal lock-outs need thousands of steady players over a long-lived
  world. With wipes, an unstable early access and a falling population, almost nobody saw a
  town reach the stages where it mattered.
- *Decay as a chore.* Daily experience upkeep makes holding a town a job.
- *All-or-nothing on everything else.* Nodes were the hub that sieges, housing, caravans,
  governance and the economy hung off, so each unfinished system left the hub hollow.

### Sieges and destruction
**Promised.** From stage 3, an attacker collects a hard-to-get item to declare; a region-wide
countdown; a siege with siege weapons. A win resets the site to stage 0, citizens lose their
houses (kept as blueprints) and vassals are freed; a loss gives the defender a cooldown. Castle
sieges with hundreds of players on top. [MM2] [ATR]

**What shipped.** Early access reviewers never saw a node siege or a tipping point; large-scale
sieges were "still being tested". Mass PvP was where the servers lagged worst. [MMO] [ATR] [GS]

**Why it fell short.** Sieges were the last link in a long chain (grown towns, housing,
citizens, PvP flagging, server performance at 100+ players in one place) and every link had
to be finished first. Total destruction also means a few hundred players' months of work can
vanish in an evening, a design that needs a big, committed population to absorb the loss.

### Caravans (moving goods between towns, with risk)
**Promised.** Trade goods hauled between settlements, open to ambush, as the spine of a
regional economy and emergent PvP. [ATR] [PCG17]
**What shipped.** One guide calls caravan PvP "functioning"; we found no review that tested it
in depth, so we treat it as unproven. [ATR]

### Freeholds (land of your own near a town)
**Promised.** Plots near settlements for farms and crafting stations. [ATR]
**What shipped.** Not covered by any review we read; at best partial.

### A player-driven economy
**Promised.** Gathering, processing and crafting interlinked, little or no NPC endgame gear,
regional trade. [ATR]
**What shipped.** Long progress bars, little XP for crafting, a grid inventory, crafting levels
that don't advance the character, key recipes locked behind drops: reviewers called it
exhausting. [MMO]

### "Massive": scale and a big world
**Promised.** A huge open world with thousands per server.
**What shipped.** A large, beautiful world that was often empty, with long walks between
anything to do; crashes, freezes and lag in big fights. [MMO] [GS]

### Timeline and trust
**Promised.** Release around 2020 [MM1]; then years of paid alpha access ($500 for Alpha One),
a spin-off game, an engine change, a $50 early access with a shop [WIKI] [MMO]. Reported in
the collapse: a pivot toward subscriptions with battle passes and a gold shop, against what the
crowdfunding had promised [CB]. Community mood: "mistrust and disappointment" over postponed
and cut features [GS], a community "split down the middle" [ATR].

## 3. What players actually wanted (the spirit we deliver)
Under the feature list, the wish was simple and still unmet by anyone:
1. **The world remembers us.** What we do together leaves a mark everyone can see.
2. **A town we built, not one we were given.** "I hauled the stone for that wall."
3. **Places that differ.** Where you settle changes what you can do there.
4. **Real stakes, together.** Something can threaten what we built, and we can defend it.
5. **Trade that crosses the map**, and roads worth travelling.
6. **A corner of my own.**
7. **A team that ships what it shows.**

## 4. Lessons, turned into our rules
These are binding on `docs/vision.md` and every stream that builds it.
1. **Visible within a session.** A player's contribution changes the world in front of them the
   same minute (a beam set, a wall course laid), not a number in a bar. Every delivery is
   juiced like a gather.
2. **Players build it, by hand.** Buildings are raised from materials players gathered and
   crafted and labour they put in; no NPC builds a town for you.
3. **Design for the population we have.** Few sites, close together, bills that scale with how
   many people are actually playing. Add sites when towns fill, not before.
4. **No upkeep chores.** Nothing built ever decays because nobody logged in (design bible: no
   daily chores). Bonuses may run down; buildings never fall down on their own.
5. **The smallest playable version first.** A camp with a fire ring before a city. Each stage is
   finished and fun before the next is designed in detail. The hub never waits on its spokes.
6. **The threat is the world first.** The early danger to a town is PvE (our own: the Dimming)
   that the whole server defends together. PvP contests come later, opt-in (pillar 4), and
   never erase months of other people's work.
7. **Bots test what players can't yet.** Every multiplayer system (contributing, raising, town
   defence) runs in the 8-bot test before it ships, including a server restart in the middle.
8. **Performance is a feature.** Towns live inside the art bible's render budget and the
   server's perf budget from day one.
9. **Promise only what is on `main`.** Patch notes and anything player-facing describe what
   shipped. The roadmap is a forecast, never a promise. No paid early access to unfinished
   systems.
10. **Persist the world, never wipe it.** Town progress survives every deploy and restart
    (CLAUDE.md hard rules 1 and 6 apply to towns as much as characters).

## Sources
- [WIKI] Wikipedia, "Ashes of Creation": https://en.wikipedia.org/wiki/Ashes_of_Creation
- [PCG] PC Gamer, on the cancellation and layoffs (2026): https://www.pcgamer.com/games/mmo/2-days-after-promising-it-was-still-worthy-of-your-investment-the-most-successful-kickstarter-mmo-ever-was-canceled-and-its-team-laid-off-the-developers-and-staff-acted-in-good-faith-and-deserved-better/
- [PCG17] PC Gamer, "Ashes of Creation explains how Nodes help expand its reactive MMO world" (2017): https://www.pcgamer.com/ashes-of-creation-explains-how-nodes-help-expand-its-reactive-mmo-world
- [GI] Game Informer, 2 Feb 2026: https://gameinformer.com/2026/02/02/report-ashes-of-creation-developer-intrepid-studios-shuts-down-weeks-after-the-mmos
- [KOT] Kotaku, refunds and layoffs: https://kotaku.com/ashes-creation-refund-kickstarter-steam-mmo-layoffs-2000665006
- [WCC] Wccftech, "Suddenly implodes 52 days after Steam Early Access launch": https://wccftech.com/mmorpg-ashes-of-creation-suddenly-implodes/
- [MMO] MMORPG.com early access review (22 Jan 2026): https://www.mmorpg.com/reviews/ashes-of-creation-early-access-review-its-playable-ambitious-and-nowhere-near-ready-2000137065
- [MMOn] MMORPG.com news, "Turmoil continues": https://www.mmorpg.com/news/ashes-of-creation-turmoil-continues-as-sharif-responds-over-the-weekend-urging-patience-2000137182
- [GS] GameSpace early access review (6 Jan 2026): https://gamespace.com/featured/ashes-of-creation-early-access-review-something-intriguing-or-not-ready-for-prime-time/
- [CB] ComicBook.com op-ed on the collapse (7 Feb 2026): https://comicbook.com/gaming/feature/ashes-of-creation-mmorpg-collapse-op-ed
- [ATR] Atriarch guide, "Everything we know so far" (Aug 2026; unsourced claims, used only for what was promised): https://www.atriarch.com/ashes-of-creation-everything-we-know-so-far
- [MM1] Mein-MMO, nodes introduced (2019): https://mein-mmo.de/en/ashes-of-creation-nodes-vorgestellt,329235
- [MM2] Mein-MMO, how cities can be destroyed (2019): https://mein-mmo.de/en/in-ashes-of-creation-cities-can-be-destroyed-and-we-reveal-how,332336
- [HH] HellHades, "Nodes explained" (2021): https://hellhades.com/nodes-explained-ashes-of-creation/
- [GF] GameFragger, fan server (Oct 2026): https://gamefragger.com/multiplatform/massively-multiplayer/ashes-of-creation-is-playable-again-months-after-intrepid-studios-shut-down-thanks-to-a-fan-server-a29891
- [BIG] The Big MMORPG List, MMOs that shut down in 2026 (19 Nov 2026): https://thebigmmorpglist.com/mmo-news/article/mmos-that-shut-down-in-2026/

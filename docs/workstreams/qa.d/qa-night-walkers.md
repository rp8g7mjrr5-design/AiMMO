Done: **Basics 2: the walker in the bot test.** "Turn `--gloam` on for the main bot test ... bots get grabbed, swing back, put walkers down, get knocked down and come back" (ws/builder/night-walkers)
Long runs add a night phase: a `--gloam=1` server at midnight, four bots (qa_night_walkers) out past the meadow fighting walkers that rise on their own; the main server stays `--gloam=0` on purpose (see the devlog note).

Follow-ups:
- [ ] Add death, the dropped pack and respawn to the night phase when gameplay lands them (a knock-down is counted today, not required).
- [ ] When the spear and maul can be crafted, give one night bot a weapon and check it puts walkers down in fewer blows than bare hands.

Request (from qa, 2026-11-25): to gameplay, for the "staying alive" and "weapons" items. In the first night runs, bots that hit first were never grabbed at all: four bare-handed haymakers put a walker down before its grab closed, so the phase has to let the first walker of each login grab on purpose. If the first night should feel dangerous, the walker may need to win the first exchange more often (a quicker windup at night, or fists not interrupting it).

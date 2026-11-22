# AiMMO Patch Notes

## Week 00 — First Steps

Welcome to **Ashgrove**, a quiet valley where the ash trees burn orange all year and nobody quite remembers why. This is day one. The world is small, the paint is wet, and you are among the very first people to walk it.

### New
- **Arms and legs!** Wanderers finally have them. Arms swing, little boots stomp, and nobody slides across the meadow like a chess piece any more. Sleeves match your tunic and trousers are a darker shade of it, so every look you already had just got a matching outfit.
- **A sun-and-moon dial.** A little dial now sits above the chat with the day and hour, e.g. "Day 3 · 18:20 · Dusk". Plan your evening walks accordingly.
- **Same sunset for everyone.** Your sky now follows the server's clock exactly, so everyone in Ashgrove sees the sun go down at the same moment (no more private time zones).
- **What time is it?** Lost track of the sun? Type `/time` in chat to see the day and hour in Ashgrove, and how long until dawn, day, dusk, or night.
- **Who's around?** Type `/who` to see who else is wandering Ashgrove right now, and `/help` for the list of commands. Only you see the answers.
- **Everyone walks.** Wanderers now bob with each step, waddle side to side, and lean into their stride, then settle back and breathe gently when they stop. Name tags stay perfectly steady above their heads while they bounce along beneath.
- **One sky schedule.** The sky now runs on the valley's own clock, the same one the server keeps, so the sun rises, peaks, and sets on the same schedule for everyone in Ashgrove.
- **The sun's path got a nudge.** It rises in the east, swings a little south at noon, and sets in the west.
- **Days and nights.** Ashgrove now keeps one shared clock for everyone: a full day lasts 40 real minutes, and it carries on even while you are offline. The sun climbs, sets in ember orange, and hands the valley over to a pale moon.
- **Look up after dusk.** Stars come out and twinkle. They were always there, you just couldn't see them over the sunshine.
- **Settings window.** Press **Esc** (or the Settings button on the login screen) to tune mouse sensitivity, invert look, volume, shadows, and draw distance. Changes show up instantly and are remembered between sessions, so you can find your perfect sunset before clicking Done.
- **Behind the scenes:** our automated tests now catch code that crashes halfway through a check, so fewer hidden bugs slip into the world.
- **Behind the scenes:** our test bots now check that the world keeps streaming to every player at full speed, so a stalled server gets caught before it ever reaches you.
- **Behind the scenes:** every update is now test-driven through a full night in Ashgrove too, so a broken moon or a pitch-black meadow gets caught before it reaches you.
- **Behind the scenes:** every update is now tested against characters saved by every older version of the game, upgraded exactly the way the live server upgrades them. Your wanderer, your look, and where you left off are safe before the first inventory ever lands.
- **Gathering spots mapped.** The settlers have surveyed Ashgrove: 397 spots where ember ash, pine, stone and the rare ember sap can be gathered are now mapped across the valley, with a ring of every kind right at the edge of Spawn Meadow. You can't swing an axe at them just yet; gathering and an inventory are next.
- **Fixed:** a rare server hiccup when several wanderers left and joined at the same moment. The server also stops telling every client about every other client's hidden connection id.
- **Chat with a clock.** Chat lines now carry a little in-game timestamp (the same clock as the sky and the time dial), so "meet at dusk" means something.
- **Chat that knows when to be quiet.** Chat fades away after a quiet spell and pops back the moment someone speaks, you press Enter, or you hover over it. The time dial's readout fades with it; the little sun keeps shining. The log keeps the latest 150 lines, and the chat box now reminds you that `/help` exists.
- **The gathering spots are real.** Look closer at Ashgrove's wild places: big ember ashes, tall four-tier pines, stone outcrops with a pale seam, and ember-sap seeps that glow from a ring of dark stones. A ring of them waits right around Spawn Meadow. You'll be able to gather from them soon.

### Update your client
- This update changes how the game talks to the server, so download the new client from the Releases page to keep playing.

### Launch day
- **The valley of Ashgrove.** Half a kilometre of rolling hills, lakes, pine ridges, and ember-leaved ash groves, all grown from a single seed. Everyone sees the same world, tree for tree.
- **Make your wanderer.** Pick a name and a password and you are in. Your look (tunic colour, hat, and all) is woven from your name.
- **Walk together.** See everyone else who is online, moving in real time.
- **Talk.** Press Enter to chat with the whole valley.
- **You are remembered.** Log out anywhere and you will wake up right where you left off.

### Known issues
- There is nothing to *do* yet besides explore and chat. That changes next week.
- Your own character is not predicted locally, so on a slow connection walking can feel a little floaty.
- Your sky follows the valley's schedule using your computer's clock, so if that clock is off, your sun is off by the same amount. Listening for the server's exact time is next.

**Built: the 8-player cap (owner direction 8, Phase 1 part 1), no protocol change, no migration.**

*Fun:* friends who come to play find a world sized for them, and a full world says so plainly
on the login screen instead of failing or bumping someone out.

- `Server.max_players`, read in `start()` from `--max-players` or `MAX_PLAYERS` through
  `Server.parse_max_players`: a whole number above 0 caps, anything else (unset, 0, negative,
  junk) is no cap. Junk deliberately means "no cap" rather than "zero seats", so a typo in a
  Railway variable can never lock everyone out. Startup logs `[server] player cap: N|none`.
- `_on_login` checks `is_world_full()` right after the protocol check (an old client hears
  "out of date" first, which is the thing it can fix) and before any account lookup, so a
  refused login creates no account and costs no password hash. Only logged-in sessions take a
  seat; a peer sitting at the login screen doesn't. The refusal is a normal
  `s2c_login_result(false, "The world is full (8 / 8). Try again soon.")`; the peer stays
  connected and can try again (it counts toward the 5 login attempts, which then disconnect:
  a client hammering retries gets dropped, which is fine).
- Client request (hp 0 before the full bar on a knock-down): built, then pulled. The extra
  send fails client's `client_vitals_bar` bot behaviour: with both messages in one frame its
  `_full_for` never resets, so it counts the time from before the knock-down and fires "full
  for 3.3 s and the bars are still up" (main alone passes; a bar sim hides at 3.15 s). That
  file is client's, so I filed the fix with client and left the send for the run after.

*Not done, and why:* no bot behaviour for the cap. The bot test runs without a cap on purpose
(it logs in more than 8 bots), and a refusal needs the server started with a flag, which is
qa's runner. Asked qa for `MAX_PLAYERS=8` in the Dockerfile and, when they have room, a capped
phase. Until qa sets the Dockerfile, the live world has no cap (same as today).

*Tests:* `test_gameplay_player_cap.gd` (6 tests, real `_on_login` with a `JsonStore`): parsing,
the ninth friend refused with the exact text and nobody kicked and no account made, a seat
opens on a leave, a login-screen peer takes no seat, no cap by default with 10 logins, and the
out-of-date message wins over the cap.

*Next run:* part 2 (world config on the wire) is a protocol bump; PR #197 (character looks,
v8) holds the current bump, so wait for it to land or fold into the next one. Otherwise the
client's animation-events request (jump, stance, rest) also wants a bump; build it with part 2.

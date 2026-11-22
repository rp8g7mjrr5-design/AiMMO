# Protocol-mismatch tests

When `GameConfig.PROTOCOL_VERSION` goes up, players who haven't downloaded the new client
must see "Your game is out of date", not a login screen that spins forever.

## Why this can break

Godot numbers a node's `@rpc` methods by **sorting their names**, and sends the number,
not the name. An old client's `c2s_login` arrives as "RPC #2 on /root/Main/Net", and the
server runs whatever its own #2 is. Add `c2s_gather_start` to `net.gd` and the server's #2
becomes `c2s_input`: the old client's login fails to convert, nothing is sent back, and the
player waits forever. `s2c_login_result` on the way back has the same problem. (Proved on
2026-11-22 by adding exactly that RPC locally: both v1 and v2 clients hung.)

Two ways to add RPCs without locking anyone out silently:
1. Put new RPCs on a **different node** (e.g. a child of `Net` that `net.gd` creates in
   `_ready`, so every role gets it). `Net`'s own list then never changes.
2. Give new RPCs names that sort **after every existing one** in `net.gd`.

Removing or renaming an RPC that sorts before `c2s_login`/`s2c_login_result` also shifts them.

## Files

- `net_v<N>.gd`: frozen copies of `game/shared/net.gd` as shipped at protocol N. Never edit
  them. **When you bump `PROTOCOL_VERSION` from N to N+1, `net_v<N>.gd` must exist**
  (`net_v2.gd` is already here for the v3 bump). The unit test says so if one is missing.
- `old_client.gd`: a headless client built from any `net_v<N>.gd` that logs in with any
  protocol number and writes what happened to JSON.
- `run_protocol_test.py`: the live test, run in CI. Starts the server, connects one old
  client per frozen copy plus the current RPCs with protocol N-1 and N+1, requires a clear
  "update" rejection from each within 8 s, then requires a current client to still log in.
  `python3 tests/protocol/run_protocol_test.py [--transport websocket|enet]`
- `tests/unit/test_qa_protocol_compat.gd`: the fast check. Compares the login RPC numbers
  and arguments of every frozen copy against today's `net.gd` and names the RPC that
  shifted them.

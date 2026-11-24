class_name GameConfig
## Constants shared by server, client, and bots. Changing world constants changes the world
## for everyone, so treat WORLD_SEED as permanent.

const PROTOCOL_VERSION := 8 ## v8: c2s_set_look / s2c_look (character customization) on Net/Play. v7: s2c_vitals, c2s_attack / s2c_swing / s2c_swing_hits / s2c_attack_refused on Net/Play. v6: s2c_wildlife (grazers in view, 5 Hz) on Net/Play. v5: s2c_roster, c2s_unstuck / s2c_unstuck_result on Net/Play. v4: skills on Net/Play (s2c_skills, s2c_xp, s2c_level_up, s2c_level_up_seen). v3: Net/Play (timed gather, pack, nodes, crafting), ack_seq in snapshots
const DEFAULT_PORT := 7777
const TICK_RATE := 20
const TICK_DT := 1.0 / TICK_RATE

const WORLD_SEED := 20261127
const WORLD_HALF_SIZE := 256.0 ## The playable world is a square from -256 to +256 metres.
const SPAWN_POINT := Vector3(0, 0, 0)
const UNSTUCK_COOLDOWN := 60.0 ## seconds between "Return to Spawn Meadow" uses, per player
const UNSTUCK_NEAR := 12.0 ## metres: closer than this to spawn, the button says you are already there

const VIEW_RANGE := 120.0 ## metres: how far away players see others gather (and later fight, build)

const WALK_SPEED := 6.0 ## metres per second
const AUTOSAVE_SECONDS := 30.0
const WORLD_TIME_SYNC_SECONDS := 60.0 ## how often the server re-sends the world clock

const NAME_MIN := 3
const NAME_MAX := 16
const PASSWORD_MIN := 4
const PASSWORD_MAX := 64
const CHAT_MAX := 200
const CHAT_COOLDOWN := 0.5 ## seconds between messages from one player

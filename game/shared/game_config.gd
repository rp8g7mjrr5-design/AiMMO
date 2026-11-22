class_name GameConfig
## Constants shared by server, client, and bots. Changing world constants changes the world
## for everyone, so treat WORLD_SEED as permanent.

const PROTOCOL_VERSION := 1
const DEFAULT_PORT := 7777
const TICK_RATE := 20
const TICK_DT := 1.0 / TICK_RATE

const WORLD_SEED := 20261127
const WORLD_HALF_SIZE := 256.0 ## The playable world is a square from -256 to +256 metres.
const SPAWN_POINT := Vector3(0, 0, 0)

const WALK_SPEED := 6.0 ## metres per second
const AUTOSAVE_SECONDS := 30.0

const NAME_MIN := 3
const NAME_MAX := 16
const PASSWORD_MIN := 4
const PASSWORD_MAX := 64
const CHAT_MAX := 200
const CHAT_COOLDOWN := 0.5 ## seconds between messages from one player

class_name WorldWipe
## Monthly wipes (owner, 2026-11-26: "lets do monthly", automatic). A server started with
## AIMMO_WIPE=monthly (or --wipe=monthly) on a generated world runs one world a month: on the
## first Thursday at 19:00 UTC (WipeSchedule) it saves everyone, sends them off, and rolls a
## new island with a new seed, so every place lands and lays out differently.
##
## Nothing is deleted. Every world is a row in the store (worlds), and a character is wiped
## lazily, the first time they log in on a world they weren't on: what they had (position and
## pack) goes into wipe_archive, the pack is emptied (rows kept at 0), and they wash up on one
## of the new island's beaches. Their name, look and everything else stay. A player who never
## comes back is never touched.
##
## Off (the default, and always on Ashgrove) nothing here runs and the server is exactly as
## before: the official world is unaffected.


## Whether wipes run for `rule` on world `cfg` (generated worlds only: Ashgrove never wipes).
static func enabled(rule: String, cfg: Dictionary) -> bool:
	return rule == WipeSchedule.MONTHLY and int(cfg.get("gen_version", 0)) >= WorldGen.KINGDOM


## The world to run at boot. Keeps the store's current world while it hasn't reached its wipe
## time; otherwise begins a new one. The very first world takes the seed from `cfg` (the
## AIMMO_WORLD spec) so an owner can pick it; every later one rolls a fresh random seed.
## Gen version and size always follow `cfg`. Returns the world record, or {} if the store failed.
static func choose(store: PlayerStore, cfg: Dictionary, now: int, rng_seed: int = -1) -> Dictionary:
	var cur := store.current_world()
	if not cur.is_empty() and now < int(cur.wipes_at) and int(cur.gen_version) == int(cfg.get("gen_version", 0)):
		return cur
	return roll(store, cfg, now, cur.is_empty(), rng_seed)


## Begins a new world after `now`. `first` keeps cfg's seed; otherwise a random one that is
## never the seed just played.
static func roll(store: PlayerStore, cfg: Dictionary, now: int, first: bool, rng_seed: int = -1) -> Dictionary:
	var next := cfg.duplicate()
	if not first:
		var rng := RandomNumberGenerator.new()
		if rng_seed >= 0:
			rng.seed = rng_seed
		else:
			rng.randomize()
		var old := int(store.current_world().get("seed", cfg.get("seed", 0)))
		var s := old
		while s == old:
			s = rng.randi() & 0x7FFFFFFF
		next.seed = s
	return store.begin_world(next, WipeSchedule.next_after(now))


## The WorldGen config for a world record.
static func config_of(world: Dictionary) -> Dictionary:
	return {"seed": int(world.seed), "size_m": float(world.size_m), "gen_version": int(world.gen_version)}


## A character logging in on `world`: if they were last on another world, keep what they had
## there in the archive, empty their pack and wash them up on a beach. Returns true if it did.
## Does nothing without a world (wipes off). Saving the character is the caller's job.
static func on_login(store: PlayerStore, ch: Dictionary, world: Dictionary) -> bool:
	if world.is_empty() or int(ch.get("world_id", 0)) == int(world.id):
		return false
	var was := int(ch.get("world_id", 0))
	if not Inventory.normalize(ch.get("inventory", {})).values().all(func(q): return int(q) == 0):
		if not store.archive_wipe(ch, was):
			push_error("[wipe] could not archive %s's pack: %s; leaving it as it is" % [ch.get("name", "?"), store.last_error])
			return false
	var inv := Inventory.normalize(ch.get("inventory", {}))
	for k in inv:
		inv[k] = 0
	ch.inventory = inv
	ch.pack = [] # an empty pack on the new island
	var key := hash(str(ch.get("name", "")).to_lower()) & 0x7FFFFFFF
	var p := Terrain.clamp_to_world(WorldGen.landing_for(key))
	ch.x = p.x
	ch.y = p.y
	ch.z = p.z
	ch.world_id = int(world.id)
	Needs.set_hunger(ch, Needs.MAX) # a fresh start on the new island
	return true

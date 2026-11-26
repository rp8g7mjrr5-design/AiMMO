class_name CharacterData
## The one place that turns stored rows into character Dictionaries. Every field has a
## default so characters saved by older versions always load (save compatibility rule).

const DEFAULTS := {
	"id": 0,
	"account_id": 0,
	"name": "",
	"x": 0.0,
	"y": 0.0,
	"z": 0.0,
	"yaw": 0.0,
	"appearance_seed": 0,
	"inventory": {}, ## item id -> quantity, see Inventory. Stored in inventory_items (Postgres).
	"skills": {}, ## old XP from the retired leveling system, kept untouched (RetiredSkills). Stored in character_skills (Postgres).
	## The chosen look (Appearance), {} until the player picks one. Stored as JSON text in
	## characters.appearance (migration 0004); older saves have none and keep their seed look.
	"look": {},
}


static func normalize(src: Dictionary) -> Dictionary:
	var out := {}
	for k in DEFAULTS:
		var v: Variant = src.get(k, null)
		if v == null:
			v = DEFAULTS[k]
		match typeof(DEFAULTS[k]):
			TYPE_INT:
				out[k] = int(v) if typeof(v) != TYPE_STRING else (v as String).to_int()
			TYPE_FLOAT:
				var f: float = float(v) if typeof(v) != TYPE_STRING else (v as String).to_float()
				out[k] = f if is_finite(f) else 0.0
			TYPE_DICTIONARY:
				if k == "skills":
					out[k] = RetiredSkills.normalize(v)
				elif k == "look":
					out[k] = Appearance.from_json(v)
				else:
					out[k] = Inventory.normalize(v)
			_:
				out[k] = str(v)
	# A position outside the world (e.g. after a world resize) snaps back inside it.
	var p := Terrain.clamp_to_world(Vector3(out.x, out.y, out.z))
	out.x = p.x
	out.y = p.y
	out.z = p.z
	return out


static func from_pg_row(row: Dictionary) -> Dictionary:
	return normalize({
		"id": row.get("id"),
		"account_id": row.get("account_id"),
		"name": row.get("name"),
		"x": row.get("pos_x"),
		"y": row.get("pos_y"),
		"z": row.get("pos_z"),
		"yaw": row.get("yaw"),
		"appearance_seed": row.get("appearance_seed"),
		"look": Appearance.from_json(row.get("appearance", "")),
	})


## A new character. On an island they wash up on one of its beach landings, picked by their
## name so a crowd spreads over every beach; elsewhere it is the spawn point, as before.
static func new_for(account: Dictionary) -> Dictionary:
	var key := hash(str(account.get("username_lc", account.get("username", "")))) & 0x7FFFFFFF
	var p := Terrain.clamp_to_world(WorldGen.landing_for(key))
	return normalize({
		"account_id": account.id,
		"name": account.username,
		"x": p.x,
		"y": p.y,
		"z": p.z,
		"appearance_seed": hash(account.username_lc) & 0x7FFFFFFF,
	})


static func position(ch: Dictionary) -> Vector3:
	return Vector3(ch.x, ch.y, ch.z)

class_name Props
## Deterministic placement of trees and rocks. Same seed, same forest, on every machine.


const NODE_CLEARANCE := 3.0 ## no decorative tree or rock this close to a resource node


## Returns an Array of {pos: Vector3, scale: float, kind: "ash"|"pine"|"rock", rot: float}.
static func scatter(count: int = 1800) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.WORLD_SEED + 7
	var out: Array = []
	var h := GameConfig.WORLD_HALF_SIZE - 4.0
	var tries := 0
	while out.size() < count and tries < count * 6:
		tries += 1
		var x := rng.randf_range(-h, h)
		var z := rng.randf_range(-h, h)
		var y := Terrain.height(x, z)
		if Vector2(x, z).length() < 10.0:
			continue # keep the spawn meadow clear
		if y < Terrain.water_level() + 1.0 or y > 15.0:
			continue
		var slope := absf(Terrain.height(x + 1.0, z) - y) + absf(Terrain.height(x, z + 1.0) - y)
		var r := rng.randf()
		var kind := "rock"
		if slope < 0.8:
			if y > 6.0:
				kind = "pine" if r < 0.8 else "rock"
			else:
				kind = "ash" if r < 0.7 else ("pine" if r < 0.85 else "rock")
		if not ResourceNodes.near(Vector3(x, 0.0, z), NODE_CLEARANCE).is_empty():
			continue # all draws for this spot are done, so skipping never shifts the rest of the forest
		out.append({"pos": Vector3(x, y - 0.1, z), "scale": rng.randf_range(0.7, 1.4), "kind": kind, "rot": rng.randf() * TAU})
	return out

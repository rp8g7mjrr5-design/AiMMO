class_name Terrain
## Deterministic height field for the world. The server uses it to place players on the
## ground and the client uses the exact same function to build the terrain mesh, so both
## always agree on where the ground is.

static var _noise: FastNoiseLite
static var _ridge: FastNoiseLite


static func _ensure() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.seed = GameConfig.WORLD_SEED
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.006
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_ridge = FastNoiseLite.new()
	_ridge.seed = GameConfig.WORLD_SEED + 1
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_ridge.frequency = 0.0025


## Ground height in metres at world position (x, z), for the world WorldGen is configured
## for. Ashgrove (gen_version 0, the default) keeps this exact code path, bit for bit.
static func height(x: float, z: float) -> float:
	if WorldGen.is_kingdom():
		return WorldGen.height(x, z)
	_ensure()
	var base := _noise.get_noise_2d(x, z) * 9.0
	var r := 1.0 - absf(_ridge.get_noise_2d(x, z))
	var ridge := r * r * r * 18.0
	# Flatten a meadow around spawn so new players start somewhere calm.
	var d := Vector2(x, z).length()
	var calm := clampf((d - 20.0) / 60.0, 0.0, 1.0)
	return (base + ridge - 4.0) * calm + 0.5 * (1.0 - calm)


## Water level. Players wade; the ground below it renders as lake bed.
static func water_level() -> float:
	if WorldGen.is_kingdom():
		return WorldGen.water_level()
	return -2.5


static func clamp_to_world(p: Vector3) -> Vector3:
	var h := WorldGen.half_size()
	var x := clampf(p.x, -h, h)
	var z := clampf(p.z, -h, h)
	return Vector3(x, height(x, z), z)

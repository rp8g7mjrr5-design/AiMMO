class_name DayNight
extends Node
## Drives the sky, sun, moon, stars, fog, and ambient light from the time of day.
## WorldBuilder creates one of these; it repaints the world a few times a second.
##
## Clock: there is one source of truth, the server's `WorldClock`. The client calls
## `DayNight.set_world_seconds(s)` whenever the server sends the time (s2c_world_time);
## between syncs the time runs on from the last value. Before the first sync it uses
## `WorldClock.now_seconds()` from this machine's wall clock, which has the same epoch as
## the server, so the sky does not jump when the server's time arrives.
## `AIMMO_TIME_OF_DAY=0.0..1.0` pins the time of day (screenshots, tests).

const UPDATE_INTERVAL := 0.25 ## seconds between repaints; the sun moves 0.04 degrees in that time

static var synced_seconds := NAN ## last world seconds from the server; NAN until the first sync
static var synced_at_msec := 0 ## Time.get_ticks_msec() when synced_seconds arrived
static var pinned_fraction := -1.0 ## >= 0 freezes the clock at that fraction

var env: Environment
var sky_mat: ShaderMaterial
var sun: DirectionalLight3D
var _timer := 0.0


## The one entry point for the server clock. Safe to call on every sync.
static func set_world_seconds(world_seconds: float) -> void:
	if not is_finite(world_seconds):
		return
	synced_seconds = world_seconds
	synced_at_msec = Time.get_ticks_msec()


## Forget the server sync (back to the local wall clock). Used on disconnect and by tests.
static func clear_sync() -> void:
	synced_seconds = NAN
	synced_at_msec = 0


static func is_synced() -> bool:
	return not is_nan(synced_seconds)


## World seconds right now as this client best knows them.
static func now_world_seconds() -> float:
	if is_synced():
		return WorldClock.extrapolate(synced_seconds, synced_at_msec, Time.get_ticks_msec())
	return WorldClock.now_seconds()


static func now_fraction() -> float:
	if pinned_fraction >= 0.0:
		return fposmod(pinned_fraction, 1.0)
	return WorldClock.day_fraction(now_world_seconds())


static func pin_from_env() -> void:
	var v := OS.get_environment("AIMMO_TIME_OF_DAY")
	if v != "" and v.is_valid_float():
		pinned_fraction = clampf(v.to_float(), 0.0, 1.0)


func _ready() -> void:
	apply(now_fraction())


func _process(delta: float) -> void:
	# The heartbeat runs every frame (one RenderingServer call), so the glow swells smoothly.
	Emberlight.set_pulse(Emberlight.pulse(now_world_seconds()))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = UPDATE_INTERVAL
	apply(now_fraction())


func apply(frac: float) -> void:
	var s := SkyClock.sample(frac)
	Emberlight.set_night(s.night)
	if sky_mat:
		sky_mat.set_shader_parameter("top_color", s.sky_top)
		sky_mat.set_shader_parameter("horizon_color", s.sky_horizon)
		sky_mat.set_shader_parameter("ground_color", s.fog)
		sky_mat.set_shader_parameter("sun_dir", s.sun_dir)
		sky_mat.set_shader_parameter("moon_dir", s.moon_dir)
		sky_mat.set_shader_parameter("star_alpha", s.stars)
	if env:
		env.fog_light_color = s.fog
		env.ambient_light_energy = s.ambient_energy
	if sun:
		var dir: Vector3 = s.light_dir
		if dir.y > 0.001:
			# A DirectionalLight shines along its -Z, so look from the light towards the ground.
			sun.basis = Basis.looking_at(-dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD)
		sun.light_color = s.light_color
		sun.light_energy = s.light_energy
		sun.visible = s.light_energy > 0.01
	# Lanterns, ember-ash leaves and sap seeps glow from the same clock (siblings under World).
	Lamps.apply_glow(get_parent(), Lamps.night_glow(frac))
	# Ember motes rise near the ash and the seeps from dusk until dawn.
	Motes.apply(get_parent(), Motes.amount(frac))


## The sky itself: a code-only shader with a colour gradient, a sun disk, a moon, and stars.
static func sky_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type sky;

uniform vec3 top_color : source_color = vec3(0.36, 0.55, 0.82);
uniform vec3 horizon_color : source_color = vec3(0.93, 0.78, 0.62);
uniform vec3 ground_color : source_color = vec3(0.80, 0.72, 0.62);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float star_alpha = 0.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float up = d.y;
	vec3 col;
	if (up >= 0.0) {
		col = mix(horizon_color, top_color, pow(clamp(up, 0.0, 1.0), 0.55));
	} else {
		col = mix(horizon_color, ground_color, clamp(-up * 6.0, 0.0, 1.0));
	}

	// Sun: a soft glow on the horizon side plus a crisp low-poly-friendly disk.
	float sd = dot(d, normalize(sun_dir));
	float glow = pow(max(sd, 0.0), 24.0) * 0.35 * clamp(sun_dir.y * 4.0 + 0.6, 0.0, 1.0);
	col += horizon_color * glow;
	col = mix(col, vec3(1.0, 0.95, 0.85) * 1.6, smoothstep(0.9993, 0.9996, sd) * step(-0.05, sun_dir.y));

	// Stars: one hashed point per cell of a cube grid, fading in at dusk and twinkling a little.
	if (star_alpha > 0.0 && up > 0.0) {
		vec3 g = d * 160.0;
		vec3 cell = floor(g);
		float h = hash13(cell);
		if (h > 0.985) {
			vec3 centre = cell + 0.5 + (vec3(hash13(cell + 1.7), hash13(cell + 3.1), hash13(cell + 5.3)) - 0.5) * 0.6;
			float r = length(g - centre);
			float tw = 0.75 + 0.25 * sin(TIME * (1.0 + h * 3.0) + h * 40.0);
			float s = smoothstep(0.28, 0.0, r) * tw * clamp(up * 5.0, 0.0, 1.0);
			col += vec3(0.85, 0.9, 1.0) * s * star_alpha * 1.4;
		}
	}

	// Moon: a pale disk with a faint ember-tinted rim, only above the horizon.
	float md = dot(d, normalize(moon_dir));
	float moon = smoothstep(0.9990, 0.9993, md) * step(0.0, moon_dir.y);
	col = mix(col, vec3(0.86, 0.88, 0.95), moon * max(star_alpha, 0.35));
	col += vec3(0.6, 0.45, 0.4) * pow(max(md, 0.0), 300.0) * 0.12 * star_alpha;

	COLOR = col;
}
"""
	return sh

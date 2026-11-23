class_name Quality
extends RefCounted
## The one Graphics quality value (art bible, section 7): Low, Medium (default) or High.
## Picking one in Settings sets the sun's shadow distance and the view distance from the table
## below (the Shadows and Draw distance controls still fine-tune after that), and world code
## reads `Quality.level` / `flora_density()` / `motes_scale()` when it builds flora and motes.
## The look must hold on Low: Low keeps sun shadows (nearer and harder) instead of dropping them.

const LOW := 0
const MEDIUM := 1
const HIGH := 2
const NAMES := ["Low", "Medium", "High"]

## Per level: ClientSettings.shadow_quality index (1 = 60 m, 2 = 120 m), view distance in
## metres (600 m is where the valley haze is solid, so Medium and High end at the haze), the
## sun's shadow map size, the soft-shadow filter, and the flora and mote multipliers world reads.
const PRESETS := [
	{"shadow_quality": 1, "draw_distance": 400.0, "shadow_atlas": 2048,
		"soft_shadows": RenderingServer.SHADOW_QUALITY_HARD, "flora": 0.5, "motes": 0.5},
	{"shadow_quality": 1, "draw_distance": 600.0, "shadow_atlas": 4096,
		"soft_shadows": RenderingServer.SHADOW_QUALITY_SOFT_LOW, "flora": 1.0, "motes": 1.0},
	{"shadow_quality": 2, "draw_distance": 600.0, "shadow_atlas": 4096,
		"soft_shadows": RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, "flora": 1.0, "motes": 1.5},
]

## The level in use on this computer. The client sets it from ClientSettings on start and on
## every Settings change; Medium until then (the server and bots never change it).
static var level := MEDIUM


static func clamp_level(l: int) -> int:
	return clampi(l, LOW, HIGH)


static func preset(l: int) -> Dictionary:
	return PRESETS[clamp_level(l)]


static func level_name(l: int = level) -> String:
	return NAMES[clamp_level(l)]


## How much of the generated flora to draw (1.0 = all of it, today's look).
static func flora_density(l: int = level) -> float:
	return float(preset(l).flora)


## Multiplier on the number of floating motes and other capped particles.
static func motes_scale(l: int = level) -> float:
	return float(preset(l).motes)


## Puts a level in force: `level` for world code that reads it, and the renderer's shadow map.
## The client calls it with the saved level before it builds the world, and on every change.
static func use(l: int) -> void:
	level = clamp_level(l)
	apply_renderer(level)


## Pushes the level's shadow map size and filter to the renderer (client only; a no-op headless).
static func apply_renderer(l: int) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := preset(l)
	RenderingServer.directional_shadow_atlas_set_size(int(p.shadow_atlas), true)
	RenderingServer.directional_soft_shadow_filter_set_quality(int(p.soft_shadows))

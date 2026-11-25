class_name ZombaiBody
## The Zombai walker's body and its motion, all procedural (CLAUDE.md hard rule 3). The
## kingdom's dead were people, so a walker is built on the traveller's own body and skeleton
## (AvatarBuilder, AvatarSkeleton): the same real proportions, then drained. Ash-grey flesh,
## sunken dark eyes, the clothes they died in gone dull and colourless, and no pack: they carry
## nothing. Grounded, not a cartoon ghoul (art bible sections 0 and 11; vision, "readable": the
## Zombai grey and ash-cold, the living warm).
##
## The poses are AvatarClips poses (bone -> Euler, plus "root_pos"), pure functions of time,
## so tests check them headless:
## - shamble(phase, speed, t): the traveller's walk with the weight gone wrong. Hunched over,
##   head lolled to one side, one arm half reaching ahead and the other hanging dead, a hitch
##   in the step.
## - grab(k): the telegraph, `k` 0..1 through the windup. Both arms come up and forward to
##   reach for you, the body leans in; at the very end it lunges. This is the cue to step back
##   or hit first, so it reads from behind the player's shoulder at 15 m.
## - stagger(t): a heavy blow rocks it back on its heels and it sags forward again.
## - fall(t): put down for good. It folds and goes over (the traveller's knock-down, without
##   the breathing), then lies still.

const VARIANTS := 4 ## distinct bodies built once; walker id picks one
const HUNCH := 0.32 ## rad the spine and chest pitch forward between them
const LOLL := 0.28 ## rad the head hangs to one side
const STAGGER := 0.7 ## seconds a stagger plays (Gloam.STAGGER_SECONDS)
const FALL := AvatarClips.KNOCKDOWN ## seconds to go over


## The flesh tone of a walker: Palette.COLD_ASH pulled toward weathered stone, one of a few
## shades by variant, never green.
static func flesh(variant: int) -> Color:
	var base := Palette.COLD_ASH.lerp(Palette.ROCK, 0.45)
	return base.darkened(0.06 * float(variant % 3)).lerp(Palette.FIRE_ASH, 0.1 * float(variant % 2))


## What the dead wear: the living colour drained out and darkened, with a little cold ash in it.
static func drained(c: Color) -> Color:
	var lum := c.r * 0.3 + c.g * 0.59 + c.b * 0.11
	var grey := Color(lum, lum, lum)
	return c.lerp(grey, 0.65).darkened(0.28).lerp(Palette.COLD_ASH.darkened(0.45), 0.15)


## The parts of walker body `variant` (AvatarBuilder.parts' format, ready for
## AvatarSkeleton.skin_parts): a traveller's body, its skin turned to ash, its eyes dark
## hollows, its cloth drained, its pack and bedroll gone.
static func parts(variant: int) -> Array:
	var seed := 90210 + variant * 7919
	var src := AvatarBuilder.parts(seed)
	var skin: Color = src[1].color # index 1 is always the head
	var ash := flesh(variant)
	var out: Array = []
	for p in src:
		var q: Dictionary = p.duplicate()
		var c: Color = p.color
		if p.limb == "" and (p.pos as Vector3).z < AvatarSkeleton.BACK_FROM:
			continue # the pack and the bedroll: they carry nothing
		if _near(c, skin.darkened(0.5)):
			q.color = Palette.SOOT.lerp(Palette.SMOULDER, 0.08) # sunken eyes, the faintest ember of what's left
		elif _near(c, skin) or _near(c, skin.darkened(0.06)) or _near(c, skin.darkened(0.04)):
			q.color = ash if _near(c, skin) else ash.darkened(0.08)
		else:
			q.color = drained(c)
		out.append(q)
	return out


static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) < 0.004


## The skinned mesh for body `variant` (AvatarSkeleton.rig_mesh turns it into a posable walker).
static func mesh(variant: int) -> ArrayMesh:
	return AvatarSkeleton.skin_parts(parts(variant), AvatarBuilder.LIMB_PIVOTS, AvatarBuilder.PART_AO)


## Which body a walker wears, and how tall it stands, from its id: steady for as long as it's in view.
static func variant_of(id: int) -> int:
	return posmod(id * 7 + 3, VARIANTS)


static func size_of(id: int) -> float:
	return 0.94 + 0.1 * fposmod(float(id) * 0.6180339, 1.0)


## Which side a walker's head lolls to and which arm reaches: +1 or -1 from its id.
static func lean_side(id: int) -> float:
	return 1.0 if id % 2 == 0 else -1.0


## --- poses ---

## The shamble at stride `phase` (0..1) and ground speed `speed` m/s, `t` seconds alive.
static func shamble(phase: float, speed: float, t: float, sd: float = 1.0) -> Dictionary:
	# The traveller's own gait, slowed in the legs (a dragging, short-stepped walk) ...
	var p := AvatarClips.gait(phase, minf(speed, 2.2) * 0.8)
	var sway := sin(TAU * phase) # +1 as the left foot comes through
	var hitch := maxf(0.0, sin(TAU * phase + 0.6)) # the bad leg: a lurch once a stride
	var go := clampf(speed / 0.8, 0.0, 1.0)
	var breath := sin(t * 1.3)
	# ... and everything above the hips gone wrong.
	p.root_pos = (p.root_pos as Vector3) + Vector3(0.0, -0.05 - 0.03 * hitch * go, 0.0)
	p["Hips"] = (p.get("Hips", Vector3.ZERO) as Vector3) + Vector3(0.08, 0.0, 0.06 * sway * go * sd)
	p["Spine"] = Vector3(HUNCH * 0.55 + 0.04 * hitch * go, 0.06 * sway * go, -0.05 * sd)
	p["Chest"] = Vector3(HUNCH * 0.45 + 0.02 * breath, 0.05 * sway * go, -0.04 * sd)
	p["Neck"] = Vector3(-0.1, 0.1 * sd, 0.0)
	p["Head"] = Vector3(-0.12 + 0.05 * sin(t * 0.7), 0.15 * sd, LOLL * sd + 0.05 * sway * go)
	# The reaching arm hangs half forward, swaying with the stride; the other hangs dead.
	var reach := "Left" if sd > 0.0 else "Right"
	var dead := "Right" if sd > 0.0 else "Left"
	p[reach + "UpperArm"] = Vector3(-0.75 + 0.12 * sway * go, 0.0, AvatarClips.side(reach) * 0.12)
	p[reach + "LowerArm"] = Vector3(-0.35 - 0.05 * breath, 0.0, 0.0)
	p[reach + "Hand"] = Vector3(-0.1, 0.0, 0.0)
	p[dead + "UpperArm"] = Vector3(0.05 - 0.18 * sway * go, 0.0, AvatarClips.side(dead) * 0.06)
	p[dead + "LowerArm"] = Vector3(-0.08, 0.0, 0.0)
	p[dead + "Hand"] = Vector3(0.1, 0.0, 0.0)
	return p


## The grab's windup, `k` 0..1 (0: it just started, 1: the grab closes). Both arms rise to
## reach straight at you by halfway, the body leans in, and the last fifth is the lunge.
static func grab(k: float, sd: float = 1.0) -> Dictionary:
	var up := smoothstep(0.0, 0.5, k)
	var lunge := smoothstep(0.8, 1.0, k)
	var p := AvatarClips.make({
		"root": Vector3(0.0, -0.08 - 0.06 * lunge, 0.22 * lunge),
		"Hips": Vector3(0.1 + 0.12 * lunge, 0.0, 0.0),
		"Spine": Vector3(HUNCH * 0.4 + 0.1 * lunge, 0.0, -0.03 * sd),
		"Chest": Vector3(HUNCH * 0.3 + 0.08 * lunge, 0.0, 0.0),
		"Neck": Vector3(-0.15 * up, 0.0, 0.0),
		"Head": Vector3(-0.2 * up, 0.05 * sd, LOLL * sd * (1.0 - 0.7 * up)),
		"arms": {"x": lerpf(-0.4, -1.5, up) - 0.1 * lunge, "z": lerpf(0.08, 0.14, up), "elbow": lerpf(-0.4, -0.15, up) + 0.1 * lunge, "hand": -0.2 * up},
		"legLeft": {"x": -0.25 - 0.2 * lunge, "knee": 0.35 + 0.15 * lunge, "flat": true},
		"legRight": {"x": 0.12, "knee": 0.2, "flat": true},
	})
	return p


## Rocked back by a heavy blow, `t` seconds in (STAGGER long), then sagging back into the hunch.
static func stagger(t: float, sd: float = 1.0) -> Dictionary:
	var rocked := AvatarClips.make({
		"root": Vector3(0.0, -0.06, -0.16),
		"Hips": Vector3(-0.15, 0.0, 0.06 * sd), "Spine": Vector3(-0.25, 0.12 * sd, 0.0), "Chest": Vector3(-0.2, 0.08 * sd, 0.0),
		"Neck": Vector3(-0.2, 0.0, 0.0), "Head": Vector3(-0.35, 0.2 * sd, 0.15 * sd),
		"armLeft": {"x": -0.3, "z": 0.7, "elbow": -0.4}, "armRight": {"x": -0.2, "z": 0.85, "elbow": -0.3},
		"legLeft": {"x": -0.3, "knee": 0.45, "flat": true}, "legRight": {"x": 0.2, "knee": 0.25, "flat": true},
	})
	var back := shamble(0.0, 0.0, t, sd)
	return AvatarClips.timeline([[0.0, back], [0.12, rocked, "out"], [STAGGER, back, "smooth"]], t)


## Put down: goes over like a knocked-down traveller, then lies still (no breath: it's dead).
static func fall(t: float) -> Dictionary:
	if t < FALL:
		return AvatarClips.knockdown(t)
	var still := AvatarClips.lying(0.0)
	still["Spine"] = Vector3.ZERO
	still["Chest"] = Vector3.ZERO
	return still

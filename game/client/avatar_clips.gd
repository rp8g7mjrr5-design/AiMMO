class_name AvatarClips
## Every motion the traveller has, as pure functions of time that return a pose. No keyframe
## files and nothing imported (CLAUDE.md hard rule 3): the art is the maths below.
##
## A pose is a Dictionary: bone name (AvatarSkeleton.BONES) -> Vector3 Euler rotation (YXZ,
## Godot's default order), plus "root_pos" -> Vector3, the Root bone's offset from standing.
## A bone that is missing is at rest. AvatarAnimator picks, layers and blends these; tests and
## the frame-strip tool call them directly.
##
## How it is meant to feel (art bible, "grounded"; design bible, "Physical and grounded"):
## weight first. Feet plant and stay planted (the stride is solved with two-bone leg IK, so a
## foot on the ground moves back exactly as fast as the body moves forward); the hips drop into
## every heavy blow and every landing; wind-ups are slow and strikes are fast; nothing floats.
##
## Sign conventions are AvatarSkeleton's: on a hanging bone (arm, leg) +x swings it back, on an
## upright bone (spine, head) +x tilts it forward; +y on the spine turns the chest to its own
## left; z abducts an arm by side(): +z raises the left arm out, -z the right.

const SIDES := ["Left", "Right"]
const HIP := AvatarSkeleton.HIP_HEIGHT
const L1 := AvatarSkeleton.THIGH
const L2 := AvatarSkeleton.SHIN
const ANKLE := AvatarSkeleton.ANKLE_HEIGHT
const REACH := (L1 + L2) * 0.995 ## a leg never locks fully straight
const IDLE_SHIFT_PERIOD := 16.0 ## s for an idle traveller to stand on one leg, the other, and back
const IDLE_HIP_ROLL := 0.06 ## rad the hips tilt over the standing leg

## --- locomotion ---
const RUN_FROM := 2.6 ## m/s; at or below this the gait is a pure walk
const RUN_AT := 5.0   ## m/s; at or above this it is a pure run (the server moves at 6)
const CONTACT_WALK := 0.62 ## s a foot would like to stay planted per step at a walk
const CONTACT_RUN := 0.2   ## ... and at a run
const MIN_STANCE := 0.2 ## share of the cycle a foot is down, at least (a fast run)
const MAX_STANCE := 0.65 ## ... and at most (a stroll)
const LIFT_WALK := 0.1  ## m the swinging ankle clears the ground
const LIFT_RUN := 0.34
const DROP_WALK := 0.07 ## m the hips sit lower than standing, so the knees stay soft
const DROP_RUN := 0.16
const BOB_WALK := 0.022 ## m of rise and fall per step
const BOB_RUN := 0.03
const LEAN_WALK := 0.05 ## rad the hips and spine pitch forward
const LEAN_RUN := 0.17
const ARM_WALK := 0.42 ## rad each arm swings either way
const ARM_RUN := 0.75
const ELBOW_WALK := -0.32 ## rad of elbow bend
const ELBOW_RUN := -1.45


static func side(s: String) -> float:
	return 1.0 if s == "Left" else -1.0


static func rest() -> Dictionary:
	return {"root_pos": Vector3.ZERO}


## Steps (full left+right cycles) per second at `speed` m/s: about 0.85 at a stroll, 1.35 at
## the server's 6 m/s run, a little quicker beyond it.
static func cadence(speed: float) -> float:
	return clampf(0.75 + 0.125 * speed, 0.75, 1.7)


## How much of the gait is a run (0..1) at `speed`.
static func run_amount(speed: float) -> float:
	return smoothstep(RUN_FROM, RUN_AT, speed)


## Thigh and shin rotation.x (hanging-bone convention) that put the ankle at `ankle`, both
## (z, y) in the avatar's space, from a hip joint at `hip`. The knee bends forward. A target
## out of reach straightens the leg towards it. Pure.
static func leg_ik(hip: Vector2, ankle: Vector2) -> Vector2:
	var d := ankle - hip
	var dist := clampf(d.length(), 0.05, REACH)
	var phi := atan2(d.x, -d.y) # angle of the target from straight down, forward positive
	var alpha := acos(clampf((L1 * L1 + dist * dist - L2 * L2) / (2.0 * L1 * dist), -1.0, 1.0))
	var beta := acos(clampf((L1 * L1 + L2 * L2 - dist * dist) / (2.0 * L1 * L2), -1.0, 1.0))
	return Vector2(-(phi + alpha), PI - beta)


## Where the knee-to-ankle chain from `leg_ik` actually puts the ankle (for tests).
static func leg_fk(hip: Vector2, thigh: float, shin: float) -> Vector2:
	var knee := hip + Vector2(-sin(thigh), -cos(thigh)) * L1
	return knee + Vector2(-sin(thigh + shin), -cos(thigh + shin)) * L2


## Solve both legs onto ground targets and write them into `pose`. `feet` maps "Left"/"Right"
## to the ankle target (z, y) in the avatar's space; `toe` maps them to the foot's pitch
## against the ground (+ toe down). The hip joints follow the pose's root_pos and hips pitch.
static func plant_legs(pose: Dictionary, feet: Dictionary, toe: Dictionary = {}) -> void:
	var root: Vector3 = pose.get("root_pos", Vector3.ZERO)
	var hips: Vector3 = pose.get("Hips", Vector3.ZERO)
	var hip := Vector2(root.z, HIP + root.y)
	for s in SIDES:
		var target: Vector2 = feet.get(s, Vector2(0.0, ANKLE))
		var a := leg_ik(hip, target)
		var thigh := a.x - hips.x
		pose[s + "UpperLeg"] = Vector3(thigh, 0.0, side(s) * 0.02)
		pose[s + "LowerLeg"] = Vector3(a.y, 0.0, 0.0)
		pose[s + "Foot"] = Vector3(-(a.x + a.y) + float(toe.get(s, 0.0)), 0.0, 0.0)


## Standing legs: both feet planted at z `left_z` / `right_z` with the hips `crouch` m lower.
static func stand_legs(pose: Dictionary, crouch: float, left_z: float = 0.02, right_z: float = -0.02) -> void:
	var root: Vector3 = pose.get("root_pos", Vector3.ZERO)
	root.y -= crouch
	pose.root_pos = root
	plant_legs(pose, {"Left": Vector2(left_z, ANKLE), "Right": Vector2(right_z, ANKLE)})


## One leg's ankle target and toe pitch at gait phase `u` (0..1, 0 = the foot strikes the
## ground) with stance share `stance`, half stride `a`, swing lift `lift`. Pure.
static func foot_path(u: float, stance: float, a: float, lift: float, run: float) -> Dictionary:
	if u < stance:
		var k := u / stance
		return {"pos": Vector2(a * (1.0 - 2.0 * k), ANKLE), "toe": 0.0, "planted": true}
	var k := (u - stance) / (1.0 - stance)
	var z := -a + 2.0 * a * (1.0 - cos(PI * k)) * 0.5
	# A run kicks the heel up early in the swing; a walk just clears the turf.
	var arc := sin(PI * pow(k, lerpf(1.0, 0.65, run)))
	var toe := lerpf(0.45, -0.25, smoothstep(0.0, 0.85, k)) * minf(lift / LIFT_WALK, 1.0) * 0.8
	return {"pos": Vector2(z, ANKLE + lift * arc), "toe": toe, "planted": false}


## The walk-to-run gait at stride phase `phase` (0..1, the left foot strikes at 0) and
## `speed` m/s. At 0 m/s it is exactly the standing pose, so it can stay blended in.
static func gait(phase: float, speed: float) -> Dictionary:
	var run := run_amount(speed)
	var go := clampf(speed / 1.2, 0.0, 1.0) # how much of a stride there is at all
	var f := cadence(speed)
	var contact := lerpf(CONTACT_WALK, CONTACT_RUN, run)
	var drop := lerpf(DROP_WALK, DROP_RUN, run) * go
	var bob_amp := lerpf(BOB_WALK, -BOB_RUN, run) * go
	# The planted foot travels from +a to -a. A leg can only reach so far from hips this high,
	# so the stride is cut to fit and the foot stays down for exactly as long as the body takes
	# to pass over that much ground: no sliding (only past MIN_STANCE, in a flat-out run).
	var h := HIP - drop - absf(bob_amp) - ANKLE
	var a_max := sqrt(maxf(REACH * REACH - h * h, 0.0)) * 0.97
	var a := minf(speed * contact * 0.5, a_max)
	var stance := clampf(2.0 * a / speed * f, MIN_STANCE, MAX_STANCE) if speed > 0.01 else 0.5
	var lift := lerpf(LIFT_WALK, LIFT_RUN, run) * go
	var p := rest()
	var uL := fposmod(phase, 1.0)
	var uR := fposmod(phase + 0.5, 1.0)
	# Bob: a walk vaults over the planted leg (highest mid-stance); a run compresses into it.
	var mid := fposmod(uL - stance * 0.5, 0.5) * 2.0 # 0 at either foot's mid-stance
	var bob := cos(TAU * mid) * bob_amp
	p.root_pos = Vector3(0.0, -drop + bob, 0.0)
	var lean := lerpf(LEAN_WALK, LEAN_RUN, run) * go
	var fl := foot_path(uL, stance, a, lift, run)
	var fr := foot_path(uR, stance, a, lift, run)
	var swing_l: float = fl.pos.x / maxf(a, 0.001) * go # +1 left foot forward .. -1 back
	p["Hips"] = Vector3(lean * 0.6, -0.12 * swing_l * go, 0.035 * (1.0 if not fl.planted else -1.0) * go * (1.0 - run))
	p["Spine"] = Vector3(lean * 0.4, 0.1 * swing_l * go, 0.0)
	p["Chest"] = Vector3(lean * 0.25, 0.1 * swing_l * go, 0.0)
	p["Neck"] = Vector3(-lean * 0.6, -0.05 * swing_l * go, 0.0)
	p["Head"] = Vector3(-lean * 0.35, 0.0, 0.0)
	var arm := lerpf(ARM_WALK, ARM_RUN, run) * go
	var elbow := lerpf(-0.12, lerpf(ELBOW_WALK, ELBOW_RUN, run), go)
	for s in SIDES:
		var fwd := swing_l if s == "Left" else -swing_l
		# The arm swings against its own leg: left foot forward, left arm back.
		p[s + "UpperArm"] = Vector3(arm * fwd - 0.05 * run, 0.0, side(s) * lerpf(0.0, 0.07, run))
		p[s + "LowerArm"] = Vector3(elbow - 0.18 * maxf(-fwd, 0.0) * go, 0.0, 0.0)
		p[s + "Hand"] = Vector3(-0.1, 0.0, 0.0)
	plant_legs(p, {"Left": fl.pos, "Right": fr.pos}, {"Left": fl.toe, "Right": fr.toe})
	return p


## Standing still, at ease: slow breathing, the weight on one leg with the hips and shoulders
## tilted against each other, soft elbows, the head turned a little, and every eight seconds or so
## the weight shifts to the other leg (`idle_weight`). Never a soldier at attention.
static func idle(t: float) -> Dictionary:
	var p := rest()
	var breath := sin(t * 1.9)
	var w := idle_weight(t) # +1: the weight on the right leg, -1: on the left
	var roll := -IDLE_HIP_ROLL * w # the loaded hip rides up, the free one drops
	p.root_pos = Vector3(-0.03 * w, 0.004 * breath - 0.01, 0.0)
	p["Hips"] = Vector3(0.0, 0.06 * w + 0.02 * sin(t * 0.37), roll)
	# the shoulders tilt against the hips, and the head turns a little towards the free side
	p["Spine"] = Vector3(0.02 + 0.01 * breath, -0.025 * w, -roll * 0.55)
	p["Chest"] = Vector3(0.015 * breath, -0.03 * w, -roll * 0.45)
	p["Neck"] = Vector3(-0.01 * breath, 0.06 * sin(t * 0.23) + 0.05 * w, 0.0)
	p["Head"] = Vector3(0.03 + 0.02 * sin(t * 0.31), 0.04 * sin(t * 0.17) + 0.06 * w, 0.04 * w)
	var feet := {}
	var toe := {}
	for s in SIDES:
		var sg := side(s)
		var free := (1.0 + w * sg) * 0.5 # 1 on the unloaded side
		p[s + "UpperArm"] = Vector3(-0.08 - 0.05 * free + 0.02 * breath, 0.0, sg * (0.05 + 0.015 * breath))
		p[s + "LowerArm"] = Vector3(-(0.26 + 0.12 * free), 0.1 * sg, 0.0)
		p[s + "Hand"] = Vector3(-0.18, -0.25 * sg, 0.1 * sg)
		feet[s] = Vector2(-0.02 + 0.07 * free, ANKLE) # the free foot rests a little forward, knee soft
		toe[s] = 0.1 * free
	plant_legs(p, feet, toe)
	for s in SIDES:
		var sg := side(s)
		var ul: Vector3 = p[s + "UpperLeg"]
		p[s + "UpperLeg"] = Vector3(ul.x, 0.05 * sg, sg * 0.05 - roll) # feet a little apart, legs plumb
		var ft: Vector3 = p[s + "Foot"]
		p[s + "Foot"] = Vector3(ft.x, 0.1 * sg, -sg * 0.05 + roll)
	return p


## Which leg an idle traveller stands on at `t`: holds one side for several seconds, then shifts
## its weight across in about a second and a half. 0 at t = 0, so the idle starts square.
static func idle_weight(t: float) -> float:
	var u := sin(t * TAU / IDLE_SHIFT_PERIOD)
	return clampf(u * 2.2, -1.0, 1.0) * (1.0 - 0.15 * (1.0 - absf(u)))


## --- keyframe timelines ---

## The pose at `t` along `keys`, an Array of [time, pose, ease?]: between two keys the pose
## eases with the later key's curve ("smooth" by default; "in" accelerates into the key,
## "out" bursts out of the earlier one). Before the first key it is the first; after the last,
## the last.
static func timeline(keys: Array, t: float) -> Dictionary:
	if t <= float(keys[0][0]):
		return keys[0][1].duplicate()
	for i in range(1, keys.size()):
		var t1 := float(keys[i][0])
		if t <= t1:
			var t0 := float(keys[i - 1][0])
			var k := (t - t0) / maxf(t1 - t0, 0.0001)
			var e: String = keys[i][2] if keys[i].size() > 2 else "smooth"
			return blend(keys[i - 1][1], keys[i][1], ease_k(k, e))
	return keys[keys.size() - 1][1].duplicate()


static func ease_k(k: float, curve: String) -> float:
	match curve:
		"in":
			return k * k
		"out":
			return 1.0 - (1.0 - k) * (1.0 - k)
		"linear":
			return k
		"snap": # a blow: almost all of the travel in the first third
			return 1.0 - pow(1.0 - k, 3.0)
	return smoothstep(0.0, 1.0, k)


## `a` blended towards `b` by `w` (0..1): every bone, root_pos, and the float or Vector2
## extras actions carry (crouch, feet). Anything missing from one side counts as rest. If
## `only` is given, only those keys move and everything else keeps a's values (an upper-body
## layer over walking legs).
static func blend(a: Dictionary, b: Dictionary, w: float, only: Array = []) -> Dictionary:
	var out := a.duplicate()
	var keys: Array = only if not only.is_empty() else _union(a, b)
	for k in keys:
		var va = a.get(k)
		var vb = b.get(k)
		if va == null and vb == null:
			continue
		if va == null:
			va = _zero_like(vb)
		if vb == null:
			vb = _zero_like(va)
		if va is Vector3 and vb is Vector3:
			out[k] = (va as Vector3).lerp(vb, w)
		elif va is Vector2 and vb is Vector2:
			out[k] = (va as Vector2).lerp(vb, w)
		elif (va is float or va is int) and (vb is float or vb is int):
			out[k] = lerpf(float(va), float(vb), w)
	return out


static func _zero_like(v: Variant) -> Variant:
	if v is Vector3:
		return Vector3.ZERO
	if v is Vector2:
		return Vector2.ZERO
	return 0.0


static func _union(a: Dictionary, b: Dictionary) -> Array:
	var keys := a.keys()
	for k in b:
		if not k in a:
			keys.append(k)
	return keys


## A pose from a compact table: {bone: Vector3} plus "root": Vector3, with "arms"/"legs"
## entries {upper, lower, abduct} applied to both sides mirrored. Feet are set flat to the
## ground when "flat" is true (the knees and hips decide where they are).
static func make(spec: Dictionary) -> Dictionary:
	var p := rest()
	p.root_pos = spec.get("root", Vector3.ZERO)
	for k in spec:
		if spec[k] is Vector3 and k != "root":
			p[k] = spec[k]
	for s in SIDES:
		var arm: Dictionary = spec.get("arm" + s, spec.get("arms", {}))
		if not arm.is_empty():
			p[s + "UpperArm"] = Vector3(float(arm.get("x", 0.0)), float(arm.get("y", 0.0)) * side(s), float(arm.get("z", 0.0)) * side(s))
			p[s + "LowerArm"] = Vector3(float(arm.get("elbow", 0.0)), 0.0, 0.0)
			p[s + "Hand"] = Vector3(float(arm.get("hand", 0.0)), 0.0, 0.0)
		var leg: Dictionary = spec.get("leg" + s, spec.get("legs", {}))
		if not leg.is_empty():
			var thigh := float(leg.get("x", 0.0))
			var knee := float(leg.get("knee", 0.0))
			p[s + "UpperLeg"] = Vector3(thigh, 0.0, float(leg.get("z", 0.0)) * side(s))
			p[s + "LowerLeg"] = Vector3(knee, 0.0, 0.0)
			var hips: Vector3 = p.get("Hips", Vector3.ZERO)
			var foot := float(leg.get("foot", 0.0))
			if leg.get("flat", false):
				foot += -(hips.x + thigh + knee)
			p[s + "Foot"] = Vector3(foot, 0.0, 0.0)
	return p


## --- upper-body actions: gathering, crafting, swings ---
## These own AvatarSkeleton.UPPER. Each also returns "crouch" (m the hips sink) and
## "feet" (Vector2: left and right foot z) for when the legs are standing still; while
## walking the legs keep their gait.

## The gather loop for `style` ("chop", "mine", "collect") at stroke phase `p` (0..1).
## Chop and mine wind up slow over the right shoulder and bite down fast; mine is heavier,
## lower and leans deeper. Collect works low with both hands, scooping and lifting.
static func gather(style: String, p: float) -> Dictionary:
	if style == "collect":
		var dip := 0.5 - 0.5 * cos(TAU * p) # 0 up, 1 down in the sap
		var out := make({
			"Spine": Vector3(0.25 + 0.1 * dip, 0.0, 0.0),
			"Chest": Vector3(0.2 + 0.12 * dip, 0.0, 0.0),
			"Neck": Vector3(0.1, 0.0, 0.0),
			"Head": Vector3(0.12 + 0.05 * dip, 0.0, 0.0),
			"arms": {"x": lerpf(-1.05, -0.62, dip), "z": -0.12, "elbow": lerpf(-0.75, -0.35, dip), "hand": -0.3},
		})
		out.crouch = 0.2 + 0.08 * dip
		out.feet = Vector2(0.14, -0.12)
		return out
	var s := GatherSwing.stroke(style, p)
	var heavy := 1.0 if style == "mine" else 0.0
	var top: float = inverse_lerp(-0.55, -2.85, s.arm) if heavy > 0.0 else inverse_lerp(-0.75, -2.7, s.arm)
	top = clampf(top, 0.0, 1.0) # 1 at the top of the wind-up, 0 at the bite
	var bite := 1.0 - top
	var out := make({
		# Wound up over the right shoulder (chest turned right), driving down across to centre.
		"Spine": Vector3(lerpf(-0.08, 0.18 + 0.1 * heavy, bite), lerpf(-0.22, 0.06, bite), 0.0),
		"Chest": Vector3(lerpf(-0.1, 0.2 + 0.1 * heavy, bite), lerpf(-0.18, 0.05, bite), 0.0),
		"Neck": Vector3(lerpf(-0.05, 0.08, bite), lerpf(0.25, -0.05, bite), 0.0),
		"Head": Vector3(lerpf(-0.05, 0.15, bite), lerpf(0.1, 0.0, bite), 0.0),
		# Hands together on the haft: both arms swing in towards the middle.
		"armLeft": {"x": s.arm, "z": lerpf(-0.42, -0.3, bite), "elbow": lerpf(-1.05, -0.2, bite), "hand": lerpf(0.3, -0.2, bite)},
		"armRight": {"x": s.arm + 0.12 * top, "z": lerpf(-0.3, -0.22, bite), "elbow": lerpf(-0.85, -0.12, bite), "hand": lerpf(0.3, -0.2, bite)},
	})
	out.crouch = lerpf(0.03, 0.09 + 0.07 * heavy, bite)
	out.feet = Vector2(0.18, -0.14)
	return out


## Working at the bench for `t` seconds: the left hand steadies the piece, the right taps and
## shapes it in a beat about once a second, head down over the work.
static func craft(t: float) -> Dictionary:
	var beat := fposmod(t / 0.95, 1.0)
	var up := smoothstep(0.0, 0.7, beat) * (1.0 - smoothstep(0.72, 0.85, beat)) # slow lift, quick tap
	var out := make({
		"Spine": Vector3(0.18, 0.05, 0.0),
		"Chest": Vector3(0.14, 0.04, 0.0),
		"Neck": Vector3(0.12, -0.05, 0.0),
		"Head": Vector3(0.3, 0.0, 0.0),
		"armLeft": {"x": -0.75, "z": -0.2, "elbow": -1.0, "hand": -0.2},
		"armRight": {"x": lerpf(-0.7, -1.25, up), "z": -0.12, "elbow": lerpf(-0.9, -1.6, up), "hand": lerpf(-0.1, 0.35, up)},
	})
	out.crouch = 0.03 + 0.015 * (1.0 - up)
	out.feet = Vector2(0.08, -0.1)
	return out


## The fists-up guard every swing starts from and settles back to.
static func guard() -> Dictionary:
	var out := make({
		"Spine": Vector3(0.06, 0.08, 0.0),
		"Chest": Vector3(0.06, 0.06, 0.0),
		"Neck": Vector3(-0.05, -0.1, 0.0),
		"Head": Vector3(-0.04, -0.04, 0.0),
		"arms": {"x": -0.6, "z": 0.18, "elbow": -1.95, "hand": 0.0},
	})
	out.crouch = 0.06
	out.feet = Vector2(0.2, -0.15)
	return out


## A swing of `kind` ("light" or "heavy") `t` seconds in, with the weapon's phase lengths
## (Weapons: windup, active, recovery). Bare-handed for now, like the server (PR 180):
## light is a quick left jab, heavy a loaded right haymaker that turns the whole body.
static func swing(kind: String, t: float, windup: float, active: float, recovery: float) -> Dictionary:
	var g := guard()
	var keys: Array
	if kind == "heavy":
		var load := make({
			"Spine": Vector3(0.0, 0.45, 0.0), "Chest": Vector3(-0.05, 0.4, 0.0),
			"Neck": Vector3(-0.05, -0.45, 0.0), "Head": Vector3(0.0, -0.35, 0.0),
			"armLeft": {"x": -0.75, "z": 0.3, "elbow": -1.6},
			"armRight": {"x": 0.35, "z": 0.95, "elbow": -1.45, "hand": 0.2},
		})
		load.crouch = 0.13
		load.feet = Vector2(0.24, -0.2)
		var hit := make({
			"Spine": Vector3(0.22, -0.45, 0.0), "Chest": Vector3(0.18, -0.4, 0.0),
			"Neck": Vector3(-0.15, 0.4, 0.0), "Head": Vector3(-0.08, 0.3, 0.0),
			"armLeft": {"x": -0.35, "z": 0.25, "elbow": -1.9},
			"armRight": {"x": -1.35, "y": 0.5, "z": 0.55, "elbow": -0.55},
		})
		hit.crouch = 0.1
		hit.feet = Vector2(0.28, -0.2)
		var follow := blend(hit, g, 0.35)
		follow.crouch = 0.12
		follow.feet = Vector2(0.26, -0.18)
		keys = [[0.0, g], [windup, load, "smooth"], [windup + active, hit, "snap"],
			[windup + active + recovery * 0.35, follow, "out"], [windup + active + recovery, g, "smooth"]]
	else:
		var chamber := make({
			"Spine": Vector3(0.05, 0.16, 0.0), "Chest": Vector3(0.05, 0.12, 0.0),
			"Neck": Vector3(-0.05, -0.2, 0.0), "Head": Vector3(-0.04, -0.06, 0.0),
			"armLeft": {"x": -0.45, "z": 0.12, "elbow": -2.1},
			"armRight": {"x": -0.62, "z": 0.2, "elbow": -2.0},
		})
		chamber.crouch = 0.08
		chamber.feet = Vector2(0.2, -0.15)
		var jab := make({
			"Spine": Vector3(0.12, -0.25, 0.0), "Chest": Vector3(0.1, -0.22, 0.0),
			"Neck": Vector3(-0.1, 0.3, 0.0), "Head": Vector3(-0.08, 0.1, 0.0),
			"armLeft": {"x": -1.5, "y": -0.15, "z": -0.1, "elbow": -0.08},
			"armRight": {"x": -0.62, "z": 0.2, "elbow": -2.0},
		})
		jab.crouch = 0.07
		jab.feet = Vector2(0.26, -0.15)
		keys = [[0.0, g], [windup, chamber, "smooth"], [windup + active, jab, "snap"],
			[windup + active + recovery, g, "smooth"]]
	return timeline(keys, t)


## --- full-body moves: jump, knockdown and getting up, sitting ---

## Jump take-off, `t` seconds after the press: a quick dip that loads the legs, arms drawn
## back, then the drive up. `TAKEOFF` long; the body leaves the ground at its end.
const TAKEOFF := 0.16
static func jump_takeoff(t: float) -> Dictionary:
	var dip := smoothstep(0.0, 0.09, t) * (1.0 - smoothstep(0.09, TAKEOFF, t))
	var drive := smoothstep(0.09, TAKEOFF, t)
	var p := make({
		"Hips": Vector3(0.2 * dip, 0.0, 0.0),
		"Spine": Vector3(0.15 * dip - 0.05 * drive, 0.0, 0.0),
		"Chest": Vector3(0.1 * dip, 0.0, 0.0),
		"Head": Vector3(-0.15 * dip, 0.0, 0.0),
		"arms": {"x": lerpf(0.55 * dip, -1.1, drive), "z": 0.15, "elbow": -0.3},
	})
	p.root_pos = Vector3(0.0, -0.2 * dip, 0.0)
	plant_legs(p, {"Left": Vector2(0.06, ANKLE + 0.05 * drive), "Right": Vector2(-0.04, ANKLE + 0.05 * drive)}, {"Left": 0.5 * drive, "Right": 0.5 * drive})
	return p


## In the air, `t` seconds after leaving the ground, rising while `vy` > 0: knees tuck at the
## top, legs reach down for the ground on the way back.
static func jump_air(t: float, vy: float) -> Dictionary:
	var tuck := clampf(1.0 - absf(vy) / 4.0, 0.0, 1.0)
	var fall := clampf(-vy / 4.0, 0.0, 1.0)
	return make({
		"Hips": Vector3(0.05, 0.0, 0.0),
		"Spine": Vector3(0.05 + 0.08 * tuck, 0.0, 0.0),
		"Head": Vector3(-0.05, 0.0, 0.0),
		"armLeft": {"x": lerpf(-1.0, -0.5, fall), "z": lerpf(0.35, 0.6, fall), "elbow": -0.5},
		"armRight": {"x": lerpf(-0.6, -0.35, fall), "z": lerpf(0.3, 0.6, fall), "elbow": -0.6},
		"legLeft": {"x": lerpf(-0.4, -1.1, tuck) * (1.0 - fall) - 0.35 * fall, "knee": lerpf(0.6, 1.5, tuck) * (1.0 - fall) + 0.35 * fall, "foot": 0.25},
		"legRight": {"x": lerpf(0.1, -0.7, tuck) * (1.0 - fall) - 0.05 * fall, "knee": lerpf(0.9, 1.6, tuck) * (1.0 - fall) + 0.5 * fall, "foot": 0.3},
	})


## Landing, `t` seconds after touchdown: the knees soak it up and the hips sink, then rise.
const LAND := 0.32
static func jump_land(t: float, hard: float = 1.0) -> Dictionary:
	var k := clampf(t / LAND, 0.0, 1.0)
	var sink := (sin(PI * pow(k, 0.55))) * (0.12 + 0.12 * clampf(hard, 0.0, 1.0))
	var p := make({
		"Hips": Vector3(0.7 * sink, 0.0, 0.0),
		"Spine": Vector3(0.6 * sink, 0.0, 0.0),
		"Chest": Vector3(0.4 * sink, 0.0, 0.0),
		"Head": Vector3(-0.8 * sink, 0.0, 0.0),
		"arms": {"x": -1.2 * sink, "z": 0.3 + 1.0 * sink, "elbow": -0.4},
	})
	p.root_pos = Vector3(0.0, -sink * 1.6, 0.0)
	plant_legs(p, {"Left": Vector2(0.09, ANKLE), "Right": Vector2(-0.07, ANKLE)})
	return p


## Knocked down, `t` seconds after the blow: a stagger back, the knees go, and the body hits
## the ground on its back with a small bounce. `KNOCKDOWN` long, then `lying()` holds.
const KNOCKDOWN := 1.05
static func knockdown(t: float) -> Dictionary:
	return timeline(_knockdown_keys(), t)


static func _knockdown_keys() -> Array:
	var stand := make({"legs": {"x": 0.0, "knee": 0.05, "flat": true}})
	var stagger := make({
		"root": Vector3(0.0, -0.06, -0.14),
		"Hips": Vector3(-0.12, 0.0, 0.05), "Spine": Vector3(-0.2, 0.1, 0.0), "Chest": Vector3(-0.22, 0.08, 0.0),
		"Neck": Vector3(-0.2, 0.0, 0.0), "Head": Vector3(-0.3, 0.15, 0.08),
		"armLeft": {"x": -0.7, "z": 0.95, "elbow": -0.5}, "armRight": {"x": -0.45, "z": 1.1, "elbow": -0.3},
		"legLeft": {"x": -0.35, "knee": 0.5, "flat": true}, "legRight": {"x": 0.25, "knee": 0.3, "flat": true},
	})
	var buckle := make({
		"root": Vector3(0.0, -0.48, -0.32),
		"Hips": Vector3(-0.65, 0.0, 0.1), "Spine": Vector3(0.15, 0.05, 0.0), "Chest": Vector3(0.15, 0.0, 0.0),
		"Neck": Vector3(0.1, 0.0, 0.0), "Head": Vector3(0.1, 0.1, 0.0),
		"armLeft": {"x": -1.4, "z": 0.65, "elbow": -0.4}, "armRight": {"x": -1.2, "z": 0.8, "elbow": -0.6},
		"legLeft": {"x": -0.55, "knee": 1.6, "foot": 0.3}, "legRight": {"x": -0.95, "knee": 1.75, "foot": 0.2},
	})
	var impact := _lying(0.0)
	impact.root_pos += Vector3(0.0, -0.02, 0.0)
	var bounce := _lying(0.0)
	bounce.root_pos += Vector3(0.0, 0.035, 0.0)
	bounce["Head"] = Vector3(0.25, 0.0, 0.0)
	return [[0.0, stand], [0.18, stagger, "out"], [0.5, buckle, "smooth"], [0.74, impact, "in"],
		[0.86, bounce, "out"], [KNOCKDOWN, _lying(0.0), "smooth"]]


## Lying on the back after a knockdown, `t` seconds in: breathing hard, then slower.
static func lying(t: float) -> Dictionary:
	return _lying(t)


static func _lying(t: float) -> Dictionary:
	var breath := sin(t * lerpf(4.0, 2.2, clampf(t / 3.0, 0.0, 1.0)))
	return make({
		"root": Vector3(0.0, -0.84, -0.62),
		"Hips": Vector3(-1.5, 0.0, 0.0), "Spine": Vector3(0.02 * breath, 0.0, 0.0),
		"Chest": Vector3(0.03 * breath, 0.0, 0.0), "Neck": Vector3(0.12, 0.0, 0.0), "Head": Vector3(0.05, 0.35, 0.0),
		"armLeft": {"x": 0.25, "z": 0.85, "elbow": -0.35}, "armRight": {"x": -0.1, "z": 0.45, "elbow": -0.6},
		"legLeft": {"x": -0.08, "knee": 0.15, "foot": -0.3}, "legRight": {"x": -0.45, "knee": 0.8, "foot": 0.1},
	})


## Getting up from lying on the back, `t` seconds in: sit up on an elbow, draw the knees in,
## roll onto one knee, push off it and stand. `GETUP` long.
const GETUP := 1.5
static func getup(t: float) -> Dictionary:
	var sit := make({
		"root": Vector3(0.0, -0.8, -0.52),
		"Hips": Vector3(-0.45, 0.0, 0.0), "Spine": Vector3(0.25, 0.0, 0.0), "Chest": Vector3(0.2, 0.0, 0.0),
		"Head": Vector3(0.1, 0.0, 0.0),
		"armLeft": {"x": -0.6, "z": 0.2, "elbow": -0.9}, "armRight": {"x": 0.75, "z": 0.25, "elbow": -0.15},
		"legLeft": {"x": -1.4, "knee": 2.05, "foot": -0.2}, "legRight": {"x": -0.9, "knee": 1.1, "foot": 0.0},
	})
	var kneel := make({
		"root": Vector3(0.0, -0.5, -0.28),
		"Hips": Vector3(0.3, 0.0, 0.0), "Spine": Vector3(0.2, 0.0, 0.0), "Chest": Vector3(0.12, 0.0, 0.0),
		"Head": Vector3(-0.25, 0.0, 0.0),
		"armLeft": {"x": -0.75, "z": 0.15, "elbow": -0.4}, "armRight": {"x": -0.25, "z": 0.2, "elbow": -0.5},
		"legLeft": {"x": -1.85, "knee": 1.55, "flat": true}, "legRight": {"x": -0.35, "knee": 1.8, "foot": 0.9},
	})
	var push := make({
		"root": Vector3(0.0, -0.2, -0.1),
		"Hips": Vector3(0.3, 0.0, 0.0), "Spine": Vector3(0.15, 0.0, 0.0), "Chest": Vector3(0.05, 0.0, 0.0),
		"Head": Vector3(-0.25, 0.0, 0.0),
		"armLeft": {"x": -0.55, "z": 0.15, "elbow": -0.6}, "armRight": {"x": -0.3, "z": 0.25, "elbow": -0.4},
		"legLeft": {"x": -1.25, "knee": 1.15, "flat": true}, "legRight": {"x": -0.2, "knee": 0.6, "flat": true},
	})
	var stand := idle(0.0)
	return timeline([[0.0, _lying(0.0)], [0.4, sit, "smooth"], [0.8, kneel, "smooth"],
		[1.15, push, "smooth"], [GETUP, stand, "out"]], t)


## Sitting down to rest, `t` seconds in: lower into a squat, a hand back to the ground, then
## settle onto the turf with the knees up and forearms on them. `SIT` long. Played backwards
## (`stand_up`) to get up again.
const SIT := 1.1
static func sit_down(t: float) -> Dictionary:
	return timeline(_sit_keys(), t)


static func stand_up(t: float) -> Dictionary:
	return timeline(_sit_keys(), SIT - t * (SIT / STAND))
const STAND := 0.85


static func _sit_keys() -> Array:
	var squat := make({
		"root": Vector3(0.0, -0.45, -0.05),
		"Hips": Vector3(0.35, 0.0, 0.0), "Spine": Vector3(0.12, 0.0, 0.0), "Chest": Vector3(0.05, 0.0, 0.0),
		"Head": Vector3(-0.3, 0.0, 0.0),
		"armLeft": {"x": -0.85, "z": 0.12, "elbow": -0.4}, "armRight": {"x": 0.3, "z": 0.3, "elbow": -0.1},
		"legs": {"x": -1.7, "knee": 1.9, "flat": true},
	})
	return [[0.0, idle(0.0)], [0.5, squat, "smooth"], [SIT, sitting(0.0), "smooth"]]


## Sitting on the ground at rest, `t` seconds in: knees up, forearms on them, a slow breath
## and a look around now and then.
static func sitting(t: float) -> Dictionary:
	var breath := sin(t * 1.6)
	var look := sin(t * 0.21) * 0.5 + sin(t * 0.13) * 0.3
	return make({
		"root": Vector3(0.0, -0.82, -0.2),
		"Hips": Vector3(-0.2, 0.0, 0.0), "Spine": Vector3(0.3 + 0.015 * breath, 0.0, 0.0),
		"Chest": Vector3(0.22 + 0.02 * breath, 0.0, 0.0), "Neck": Vector3(-0.1, 0.2 * look, 0.0),
		"Head": Vector3(-0.25, 0.25 * look, 0.0),
		"arms": {"x": -0.95, "z": 0.12, "elbow": -0.55, "hand": 0.3},
		"legs": {"x": -2.3, "knee": 2.5, "z": 0.14, "flat": true},
	})

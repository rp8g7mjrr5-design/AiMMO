extends SceneTree
## Client smoke: every gather and craft answers the player within 100 ms ("nothing happened
## when I pressed E" can't ship). Design bible, "Fun comes first": tight feedback is rule one.
##
##   xvfb-run godot --rendering-driver opengl3 --path game -s tests/client_smoke/feedback_check.gd -- \
##     --name=X --password=Y --address=127.0.0.1:PORT --autoconnect --out=/abs/feedback.json
##
## Boots the real game scene, logs a fresh character in and plays the first minute with real
## input (Input.action_press, as a keyboard would):
## - walks to the nearest ash, then the nearest pine, and presses E on each until the pack
##   holds a wooden pickaxe's parts (the first tool: bare hands can't break stone). Every press must show the gather bar (or a refusal notice) within
##   100 ms, and every haul toast must pop within 100 ms of the bar filling.
## - walks to the workbench and presses E: the window must open on that frame. Presses the
##   wooden pickaxe's real Craft button: "Working..." on that frame, and the server's answer (the
##   "Crafted" toast) within 100 ms.
## Times are wall-clock from the press to the first frame that shows the feedback. Any client
## needs two frames for an answer from the server (the frame that handles the press and sends
## it, then the frame that reads the reply and draws it): about 33 ms on a 60 fps machine, but
## CI draws in software at about 100-130 ms a frame. So each limit is 100 ms plus two median
## frames, and, frame rate aside, feedback must be on screen within MAX_FRAMES frames of the
## press (a client that waits for a tween, a timer or a later tick fails either way).
## Writes every sample to --out and exits 1 with every problem printed.

const BUDGET_MS := 100.0 ## owner rule: feedback within 100 ms of the input
const MAX_FRAMES := 2 ## frames after the press frame; local feedback is on frame 0
const GIVE_UP_MS := 3000.0 ## no feedback at all by then: "nothing happened"
const LOGIN_TIMEOUT := 40.0
const WALK_TIMEOUT := 25.0
const SETTLE := 1.5
const AXE := "wooden_pickaxe" ## the first tool a fresh character makes (owner direction 11)

var problems: Array[String] = []
var samples: Array = [] ## {what, ms, frames}
var frame_ms: Array = [] ## every frame's wall time, for the slack
var out_path := ""
var _last_us := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_path = a.substr(6)
	root.add_child(load("res://main.tscn").instantiate())
	_run.call_deferred()


# --- rules (static, unit tested in tests/unit/test_qa_feedback_check.gd) ---

## Median of a list of numbers (0 for none).
static func median(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var s := xs.duplicate()
	s.sort()
	var n := s.size()
	return float(s[n / 2]) if n % 2 == 1 else (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5


## The limit one sample is held to: the budget plus two frames (the press frame and the frame
## that draws the answer). A slow runner widens it, so MAX_FRAMES and GIVE_UP_MS still catch a
## client that waits.
static func limit_ms(budget: float, median_frame: float) -> float:
	return budget + 2.0 * maxf(median_frame, 0.0)


## Problems for a run: each sample {what, ms, frames} (ms < 0 = never seen) against limit_ms
## and MAX_FRAMES, and the kinds of feedback that must have been measured at least once (`needed`).
static func verdict(samples_in: Array, budget: float, median_frame: float, needed: Array) -> Array[String]:
	var out: Array[String] = []
	var lim := limit_ms(budget, median_frame)
	var seen := {}
	for s in samples_in:
		seen[str(s.what)] = true
		var ms := float(s.ms)
		if ms < 0.0:
			out.append("%s: no feedback at all (nothing happened)" % s.what)
		elif ms > lim:
			out.append("%s: feedback took %.0f ms (limit %.0f ms = %.0f + two %.0f ms frames)" % [s.what, ms, lim, budget, median_frame])
		elif int(s.get("frames", 0)) > MAX_FRAMES:
			out.append("%s: feedback took %d frames after the press (limit %d)" % [s.what, int(s.frames), MAX_FRAMES])
	for w in needed:
		if not seen.has(w):
			out.append("%s: never measured" % w)
	return out


## The JSON written for the CI artifact.
static func report(samples_in: Array, budget: float, median_frame: float, problems_in: Array) -> Dictionary:
	var worst := {}
	for s in samples_in:
		var w := str(s.what)
		worst[w] = maxf(float(worst.get(w, -1.0)), float(s.ms))
	return {"budget_ms": budget, "median_frame_ms": snappedf(median_frame, 0.1),
		"limit_ms": snappedf(limit_ms(budget, median_frame), 0.1), "max_frames": MAX_FRAMES, "worst_ms": worst,
		"samples": samples_in, "problems": problems_in, "ok": problems_in.is_empty()}


# --- the run ---

func _run() -> void:
	var client: Node = await _wait_for_login()
	if client != null:
		await _wait(SETTLE)
		await _gather_until_axe_parts(client)
		await _craft_axe(client)
	_finish()


func _frame() -> void:
	await process_frame
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		frame_ms.append((now - _last_us) / 1000.0)
	_last_us = now


func _wait(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await _frame()


func _wait_for_login() -> Node:
	var until := Time.get_ticks_msec() + int(LOGIN_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < until:
		var c := root.get_node_or_null("Main/Role")
		if c == null:
			for n in root.get_children():
				c = n.get_node_or_null("Role")
				if c != null:
					break
		if c != null and "logged_in" in c and c.logged_in and c.avatars.has(c.my_id):
			return c
		await _frame()
	problems.append("client did not log in within %.0fs" % LOGIN_TIMEOUT)
	return null


func _feet(client: Node) -> Vector3:
	return (client.avatars[client.my_id].node as Node3D).global_position


## Presses an action for one frame from the top of a frame (before the client's _process),
## so the client sees it as just pressed, the way a key would arrive. Returns the press time.
func _tap(action: String) -> int:
	Input.action_press(action)
	var t := Time.get_ticks_usec()
	await _frame()
	Input.action_release(action)
	return t


## Waits for `seen` to be true, up to GIVE_UP_MS. Returns {ms, frames} since `t0` (usec), ms -1
## when it never happened. The first check is the frame the press was handled in. Something
## already showing at `t0` counts as 0 ms (the haul toast can beat the client's own bar by
## a frame, because the bar starts when s2c_gather_begin arrives).
func _until(t0: int, seen: Callable) -> Dictionary:
	var frames := 0
	while true:
		if seen.call():
			return {"ms": maxf(0.0, (Time.get_ticks_usec() - t0) / 1000.0), "frames": frames}
		if (Time.get_ticks_usec() - t0) / 1000.0 > GIVE_UP_MS:
			return {"ms": -1.0, "frames": frames}
		await _frame()
		frames += 1
	return {}


func _record(what: String, r: Dictionary, extra := "") -> void:
	samples.append({"what": what, "ms": snappedf(float(r.ms), 0.1), "frames": int(r.frames)})
	print("[feedback] %s: %s after %d frame(s)%s" % [what, "never" if r.ms < 0 else "%.0f ms" % r.ms, r.frames, extra])


func _toast_on(client: Node) -> bool:
	return client.gather_prompt.toast_label.modulate.a > 0.99


func _walk_to(client: Node, target: Vector3, close_enough: Callable) -> void:
	var cam: ActionCamera = client.cam
	var until := Time.get_ticks_msec() + int(WALK_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < until and not close_enough.call():
		var d := target - _feet(client)
		d.y = 0.0
		cam.yaw = atan2(-d.x, -d.z)
		cam.heading = cam.yaw
		Input.action_press("move_forward")
		await _frame()
	Input.action_release("move_forward")
	await _wait(0.6) # stop: moving cancels a gather


## The nearest tier-1 node of `kind` the client doesn't know as spent.
func _live_node(client: Node, kind: String) -> Dictionary:
	var best := {}
	var best_d := INF
	for n in ResourceNodes.near(_feet(client), 60.0, kind):
		if int(n.get("tier", 1)) >= 2 or client.gather_prompt.spent.has(int(n.id)):
			continue
		var d := _feet(client).distance_to(n.pos)
		if d < best_d:
			best_d = d
			best = n
	return best


func _gather_until_axe_parts(client: Node) -> void:
	var needs: Dictionary = Crafting.RECIPES[AXE].needs
	for item in needs:
		var kind := ""
		for k in ResourceNodes.KINDS:
			if str(ResourceNodes.KINDS[k].item) == item:
				kind = k
		var tries := 0
		while int(client.gather_prompt.pack.get(item, 0)) < int(needs[item]) and tries < 6:
			tries += 1
			var n := _live_node(client, kind)
			if n.is_empty():
				problems.append("no live %s node near spawn to gather" % kind)
				return
			await _walk_to(client, n.pos, func():
				var t: Dictionary = client.gather_prompt.current_target()
				return not t.is_empty() and int(t.id) == int(n.id) and bool(t.can))
			var t: Dictionary = client.gather_prompt.current_target()
			if t.is_empty() or not bool(t.can):
				print("[feedback] could not reach %s node %d, trying another" % [kind, n.id])
				client.gather_prompt.spent[int(n.id)] = true
				continue
			await _press_gather(client, kind)
	for item in needs:
		if int(client.gather_prompt.pack.get(item, 0)) < int(needs[item]):
			problems.append("could not gather %d %s for the %s (have %d)" % [needs[item], item, AXE, int(client.gather_prompt.pack.get(item, 0))])


## One press of E on the node in front: the bar (or a refusal notice) answers it, then the
## haul toast answers the bar filling.
func _press_gather(client: Node, kind: String) -> void:
	var gp: GatherPrompt = client.gather_prompt
	var t0 := await _tap("interact")
	var r := await _until(t0, func(): return gp.bar.visible or _toast_on(client))
	_record("gather press -> bar (%s)" % kind, r)
	if not gp.gathering():
		print("[feedback] the press was refused: ", gp.toast_label.text)
		await _wait(0.5)
		return
	var ch: Dictionary = gp.channel()
	var full_at := int((float(ch.started) + float(ch.seconds)) * 1000000.0) # ticks_msec clock, in usec
	var toast_before := gp.toast_label.text
	# Wait for the bar to fill, then time the haul toast from that moment.
	while Time.get_ticks_usec() < full_at and gp.gathering():
		await _frame()
	var r2 := await _until(full_at, func(): return _toast_on(client) and gp.toast_item() != "")
	_record("bar full -> haul toast (%s)" % kind, r2, "  \"%s\"" % gp.toast_label.text if r2.ms >= 0 else "  (last toast \"%s\")" % toast_before)
	await _wait(0.3)


func _craft_axe(client: Node) -> void:
	if not problems.is_empty():
		return
	var bench := Crafting.workbench_pos()
	await _walk_to(client, bench, func(): return Crafting.near_bench(_feet(client)) and \
		Vector2(_feet(client).x, _feet(client).z).distance_to(Crafting.WORKBENCH_XZ) < Crafting.BENCH_RANGE - 2.0)
	if not Crafting.near_bench(_feet(client)):
		problems.append("could not reach the workbench")
		return
	var cw: CraftWindow = client.craft_window
	var t0 := await _tap("interact")
	_record("bench press -> window", await _until(t0, func(): return cw.visible))
	if not cw.visible:
		return
	await _wait(0.3)
	var button: Button = cw._rows[AXE].button
	if button.disabled:
		problems.append("the %s Craft button is greyed out with its parts in the pack (%s)" % [AXE, button.tooltip_text])
		return
	var t1 := Time.get_ticks_usec()
	button.pressed.emit() # what a click does
	_record("craft press -> working", await _until(t1, func(): return cw.status_label.text == CraftWindow.WORKING))
	var r := await _until(t1, func(): return not cw.is_waiting() and _toast_on(client) and client.gather_prompt.toast_item() == AXE)
	_record("craft press -> crafted toast", r, "  \"%s\", craft sound %s" % [client.gather_prompt.toast_label.text, "playing" if client.sfx_craft.playing else "not playing"])


func _finish() -> void:
	var mf := median(frame_ms)
	problems.append_array(verdict(samples, BUDGET_MS, mf, [
		"gather press -> bar (ash)", "bar full -> haul toast (ash)", "gather press -> bar (pine)",
		"bar full -> haul toast (pine)", "bench press -> window", "craft press -> working", "craft press -> crafted toast"]))
	print("[feedback] median frame %.1f ms, limit %.0f ms per feedback" % [mf, limit_ms(BUDGET_MS, mf)])
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(report(samples, BUDGET_MS, mf, problems), "  "))
	if problems.is_empty():
		print("[feedback] every gather and craft answered within budget")
		quit(0)
	else:
		for p in problems:
			print("[feedback] FAIL ", p)
		quit(1)

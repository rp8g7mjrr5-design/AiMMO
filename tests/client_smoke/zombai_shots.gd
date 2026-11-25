extends SceneTree
## Client smoke (scratch for the Zombai PR): logs in, raises a bound walker with /gloam, and
## photographs it shambling up, raising its arms, and going down to heavy blows.
##   xvfb-run godot --rendering-driver opengl3 --path game -s tests/client_smoke/zombai_shots.gd -- \
##     --shots=/abs/dir --name=X --password=Y --address=127.0.0.1:PORT --autoconnect

var shots := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	root.add_child(load("res://main.tscn").instantiate())
	_run.call_deferred()


func _client() -> Node:
	for n in root.get_children():
		var c := n.get_node_or_null("Role")
		if c != null:
			return c
	return null


func _run() -> void:
	var c: Node = null
	for i in 600:
		c = _client()
		if c != null and "logged_in" in c and c.logged_in and c.avatars.has(c.my_id):
			break
		await process_frame
	await create_timer(2.5).timeout
	c._on_chat_submitted("/gloam")
	await create_timer(1.2).timeout
	await _save("zombai-1-rises.png")
	await create_timer(1.0).timeout
	c.cam.yaw += 2.2 # swing the camera round to see it from the side
	await create_timer(0.6).timeout
	await _save("zombai-1b-side.png")
	var took_windup := false
	var t := 0.0
	while t < 12.0 and not took_windup:
		var v: ZombaiView = c.zombai
		for id in v.ids():
			if v.state(id) == "grab" and v.windup(id, Time.get_ticks_msec() / 1000.0) > 0.55:
				await _save("zombai-2-arms-up.png")
				took_windup = true
				break
		await process_frame
		t += root.get_process_delta_time()
	print("[zombai] windup shot: ", took_windup, " figures drawn: ", c.zombai_figures.drawn)
	for i in 8:
		var yaw := ActionCamera.facing_yaw(c.cam.move_yaw())
		var v2: ZombaiView = c.zombai
		var me: Vector3 = c.prediction.position
		for id in v2.ids():
			var p := v2.position(id, Time.get_ticks_msec() / 1000.0)
			yaw = atan2(p.x - me.x, p.z - me.z)
		c.net.play.c2s_attack.rpc_id(1, "heavy", yaw)
		await create_timer(1.3).timeout
		if c.zombai.ids().is_empty():
			break
	await create_timer(0.9).timeout
	await _save("zombai-3-down.png")
	print("[zombai] downs seen: ", c.zombai.downs, " bodies: ", c.zombai.bodies())
	quit(0)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(shots.path_join(name))
	print("[zombai] saved ", name)

extends TestCase
## Client-side prediction: your avatar walks on the frame you press a key, agrees with a
## laggy server without popping or rubber-banding, settles exactly where the server has you,
## and snaps on a real teleport. The sim below runs the client's send loop (client.gd) against
## the server's tick (server.gd) with a one-way delay, like a real connection.

const START := Vector3(4, 0, 6)


## A client and an authoritative server talking over a link with `latency` seconds each way.
class Sim:
	var pred := Prediction.new()
	var t := 0.0
	var latency := 0.06
	var seq := 0
	var send_accum := 0.0
	var last_sent := Vector2(INF, INF)
	var server_pos := Vector3.ZERO
	var server_move := Vector2.ZERO
	var server_seq := -1
	var server_next_tick := 0.0
	var to_server: Array = [] ## [arrive_at, seq, move]
	var to_client: Array = [] ## [arrive_at, pos, ack]
	var drawn: Array = [] ## drawn position every frame

	func _init(start: Vector3, p_latency: float, server_phase := 0.013) -> void:
		latency = p_latency
		server_pos = Terrain.clamp_to_world(start)
		pred.place(server_pos)
		server_next_tick = server_phase

	## Run `seconds` of frames of `dt` holding `move`.
	func run(move: Vector2, seconds: float, dt: float) -> void:
		var end := t + seconds
		while t < end - 0.000001:
			t += dt
			# Server ticks that fell inside this frame.
			while server_next_tick <= t:
				while not to_server.is_empty() and float(to_server[0][0]) <= server_next_tick:
					var m: Array = to_server.pop_front()
					if int(m[1]) > server_seq:
						server_seq = int(m[1])
						server_move = m[2]
				server_pos = Movement.step(server_pos, server_move, GameConfig.TICK_DT)
				to_client.append([server_next_tick + latency, server_pos, server_seq])
				server_next_tick += GameConfig.TICK_DT
			while not to_client.is_empty() and float(to_client[0][0]) <= t:
				var s: Array = to_client.pop_front()
				pred.reconcile(s[1], s[2])
			# The client frame: walk now, send at the tick rate (as client.gd does).
			pred.advance(seq + 1, move, dt)
			drawn.append(pred.position)
			send_accum += dt
			if send_accum >= GameConfig.TICK_DT:
				send_accum = 0.0
				seq += 1
				if move != last_sent or move != Vector2.ZERO or seq % 10 == 0:
					to_server.append([t + latency, seq, move])
					last_sent = move


func test_you_walk_on_the_frame_you_press() -> void:
	var sim := Sim.new(START, 0.1)
	sim.run(Vector2.ZERO, 0.5, 1.0 / 60.0)
	var before := sim.pred.position
	sim.run(Vector2(0, 1), 1.0 / 60.0, 1.0 / 60.0)
	check_near(sim.pred.position.z - before.z, GameConfig.WALK_SPEED / 60.0, 0.001, "moved one frame of walk before any snapshot")
	check_near(sim.server_pos.z, before.z, 0.0001, "while the server hasn't heard yet")


func test_walking_never_rubber_bands() -> void:
	for latency in [0.02, 0.06, 0.15]:
		for fps in [30.0, 60.0, 144.0]:
			var sim := Sim.new(START, latency)
			sim.run(Vector2.ZERO, 0.4, 1.0 / fps)
			var from := sim.drawn.size()
			sim.run(Vector2(0, 1), 2.0, 1.0 / fps)
			sim.run(Vector2(1, 0), 1.0, 1.0 / fps)
			# While walking straight, the drawn position never steps back along the walk.
			var worst := 0.0
			for i in range(from + 1, from + int(2.0 * fps)):
				worst = minf(worst, sim.drawn[i].z - sim.drawn[i - 1].z)
			check(worst > -0.02, "%dms %dfps: stepped back %.3f m while walking forward" % [int(latency * 1000), int(fps), -worst])
			check_eq(sim.pred.snaps, 0, "%dms %dfps: no snaps in normal play" % [int(latency * 1000), int(fps)])
			check(sim.pred.max_error < Prediction.WALK_DEADZONE * 2.0, "%dms %dfps: disagreement stays small (%.3f m)" % [int(latency * 1000), int(fps), sim.pred.max_error])


func test_you_settle_exactly_where_the_server_has_you() -> void:
	var sim := Sim.new(START, 0.08)
	sim.run(Vector2(0.6, 0.8), 1.7, 1.0 / 60.0)
	sim.run(Vector2(-1, 0), 0.33, 1.0 / 60.0)
	sim.run(Vector2.ZERO, 1.0, 1.0 / 60.0)
	check(sim.pred.position.distance_to(sim.server_pos) < 0.01, "drawn %s, server %s" % [sim.pred.position, sim.server_pos])
	check(sim.pred.pending_seconds() == 0.0, "acked walks are dropped (%.2f s left)" % sim.pred.pending_seconds())


func test_drawn_position_is_ahead_of_the_server_by_the_round_trip() -> void:
	var sim := Sim.new(START, 0.1)
	sim.run(Vector2(0, 1), 1.0, 1.0 / 60.0)
	# The server is ~200 ms behind (1.2 m at 6 m/s); you are drawn where your keys put you.
	var lead := sim.pred.position.z - sim.server_pos.z
	check(lead > 0.8 and lead < 1.8, "lead over the server %.2f m" % lead)
	check_near(sim.pred.position.z - START.z, GameConfig.WALK_SPEED * 1.0, 0.4, "walked a second's worth")


func test_a_teleport_snaps() -> void:
	var p := Prediction.new()
	p.place(Terrain.clamp_to_world(START))
	var far := Terrain.clamp_to_world(START + Vector3(30, 0, 0))
	p.reconcile(far, 0)
	check_eq(p.snaps, 1, "snapped")
	check(p.position.distance_to(far) < 0.001, "now at the teleport target")
	check_eq(p.correction, Vector3.ZERO, "nothing left to ease")


func test_a_small_disagreement_eases_out() -> void:
	var p := Prediction.new()
	p.place(Terrain.clamp_to_world(START))
	var off := Terrain.clamp_to_world(START + Vector3(1.0, 0, 0))
	p.reconcile(off, 0)
	check_eq(p.snaps, 0, "1 m is eased, not snapped")
	p.advance(1, Vector2.ZERO, 1.0 / 60.0)
	var first := p.position.x - START.x
	check(first > 0.05 and first < 0.3, "one frame moves part of the way (%.3f)" % first)
	for i in 60:
		p.advance(1, Vector2.ZERO, 1.0 / 60.0)
	check(p.position.distance_to(off) < 0.01, "a second later it's gone")


func test_first_snapshot_places_you() -> void:
	var p := Prediction.new()
	check(not p.has_position, "nowhere yet")
	check_eq(p.advance(1, Vector2(0, 1), 0.1), Vector3.ZERO, "no walking before you're placed")
	p.reconcile(Terrain.clamp_to_world(START), -1)
	check(p.has_position, "placed")
	check(p.position.distance_to(Terrain.clamp_to_world(START)) < 0.001, "at the server's spot")


func test_bad_input_is_ignored() -> void:
	var p := Prediction.new()
	p.place(Terrain.clamp_to_world(START))
	p.advance(1, Vector2(NAN, 1), 0.1)
	p.advance(1, Vector2(0, 1), NAN)
	p.reconcile(Vector3(INF, 0, 0), 0)
	check(p.position.is_finite(), "still finite: %s" % p.position)
	check(p.position.distance_to(Terrain.clamp_to_world(START)) < 0.001, "and didn't move")


func test_pending_merges_and_is_bounded() -> void:
	var p := Prediction.new()
	p.place(Terrain.clamp_to_world(START))
	for i in 10:
		p.advance(5, Vector2(0, 1), 0.01)
	check_eq(p.pending.size(), 1, "same seq and move merge into one walk")
	check_near(p.pending_seconds(), 0.1, 0.0001, "with their time summed")
	for i in Prediction.MAX_PENDING + 50:
		p.advance(6 + i, Vector2(0, 1), 0.001)
	check_eq(p.pending.size(), Prediction.MAX_PENDING, "lost acks can't grow it forever")
	p.reconcile(p.position, 6 + Prediction.MAX_PENDING + 49)
	check_eq(p.pending.size(), 0, "an ack clears everything up to it")


func test_walls_hold_in_the_replay_too() -> void:
	var p := Prediction.new()
	var edge := Terrain.clamp_to_world(Vector3(GameConfig.WORLD_HALF_SIZE - 0.5, 0, 0))
	p.place(edge)
	for i in 60:
		p.advance(1, Vector2(1, 0), 1.0 / 60.0)
	check_near(p.position.x, GameConfig.WORLD_HALF_SIZE, 0.0001, "stopped at the world's edge")
	# The server, a little behind, replays to the same wall: no disagreement.
	check_near(p.reconcile(edge, 0), 0.0, 0.001, "replay hits the same wall")

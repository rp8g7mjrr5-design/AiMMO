extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): protocol v9, the world config and campfires on the wire.
##
## - Every login must be followed within WORLD_TIMEOUT by s2c_world: a {seed, size_m,
##   gen_version} config that WorldGen.apply takes as is (applying it and reading it back gives
##   the same config), as the client will do before building terrain.
## - Every s2c_campfires must be whole fires (5 floats each, ids > 0, a fire's time left never
##   above Campfires.burn_seconds()). The bot that kindles one (gameplay_campfires, *_5) must
##   hear its fire in an s2c_campfires; everyone else hears it too, so it is counted on all.
## - One bot (*_6) asks to place a campfire over the wire once (c2s_place) and must get an
##   s2c_place_result within RESULT_TIMEOUT whose reason is "" or a known refusal; bots carry
##   no campfire, so it is normally "no_item".

const WORLD_TIMEOUT := 4.0
const RESULT_TIMEOUT := 4.0
const PLACER_SUFFIX := "_6"
const PLACE_AFTER := 12.0

var _login_at := -1.0
var _logins := 0
var _place_sent_at := -1.0
var _placed_once := false
var _fires_seen := {} ## fire id -> true
var worlds := 0
var fire_lists := 0
var place_results := 0
var place_reason := ""


func setup(net: Node) -> void:
	net.world_config.connect(_on_world)
	net.campfires_changed.connect(_on_fires)
	net.place_result.connect(_on_place_result)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_logins += 1
	_login_at = bot.elapsed


func _on_world(config: Dictionary) -> void:
	if _login_at < 0.0:
		fail("s2c_world arrived with no login waiting for it")
		return
	_login_at = -1.0
	worlds += 1
	for k in ["seed", "size_m", "gen_version"]:
		if not config.has(k):
			fail("s2c_world has no %s: %s" % [k, config])
			return
	WorldGen.apply(config)
	var back := WorldGen.config()
	if int(back.seed) != int(config.seed) or int(back.gen_version) != int(config.gen_version) \
			or absf(float(back.size_m) - float(config.size_m)) > 0.01:
		fail("s2c_world %s does not survive WorldGen.apply (read back %s)" % [config, back])


func _on_fires(entries: PackedFloat32Array) -> void:
	fire_lists += 1
	if entries.size() % 5 != 0:
		fail("s2c_campfires has %d floats, not whole fires" % entries.size())
		return
	for i in range(0, entries.size(), 5):
		var id := int(entries[i])
		if id <= 0:
			fail("s2c_campfires has fire id %d" % id)
		if entries[i + 4] < 0.0 or entries[i + 4] > Campfires.burn_seconds() + 0.5:
			fail("fire %d has %.1f s left" % [id, entries[i + 4]])
		_fires_seen[id] = true


func _on_place_result(item: String, ok: bool, reason: String, text: String) -> void:
	if _place_sent_at < 0.0:
		fail("s2c_place_result (%s, %s) with no c2s_place sent" % [item, reason])
		return
	_place_sent_at = -1.0
	place_results += 1
	place_reason = reason
	if ok != (reason == "") or (reason != "" and not Campfires.REFUSALS.has(reason)):
		fail("odd place answer: ok %s, reason '%s'" % [ok, reason])
	if text.strip_edges() == "":
		fail("place answer with no text to show")


func on_play(_delta: float) -> void:
	if _login_at >= 0.0 and bot.elapsed - _login_at > WORLD_TIMEOUT:
		fail("no s2c_world within %.0f s of logging in" % WORLD_TIMEOUT)
		_login_at = -1.0
	if _place_sent_at >= 0.0 and bot.elapsed - _place_sent_at > RESULT_TIMEOUT:
		fail("c2s_place never answered")
		_place_sent_at = -1.0
	if not _placed_once and _logins == 1 and str(bot.bot_name).ends_with(PLACER_SUFFIX) \
			and bot.elapsed >= PLACE_AFTER and float(bot.duration) - bot.elapsed > 10.0:
		_placed_once = true
		if bot.send_play("c2s_place", ["campfire"]):
			_place_sent_at = bot.elapsed


func on_finish() -> void:
	stat("worlds", worlds)
	stat("fire_lists", fire_lists)
	stat("fires_seen", _fires_seen.size())
	stat("place_results", place_results)
	stat("place_reason", place_reason)
	if worlds < _logins:
		fail("%d logins but %d s2c_world" % [_logins, worlds])
	for b in bot.behaviours:
		if b.name == "gameplay_campfires" and int(b.kindled) > 0 and int(b._fire) > 0 and not _fires_seen.has(int(b._fire)):
			fail("kindled campfire %d but never heard it in s2c_campfires" % int(b._fire))

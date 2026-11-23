extends "res://tests/bot_test/bot_behaviour.gd"
## Bot behaviour (gameplay): crafting.
##
## Right after each login the bot stands still and types /craft (the recipe list must come
## back), then /craft axe. Where it stands decides the right answer: near the Spawn Meadow
## workbench (every first login starts there) the server must look at the pack ("You need
## ..." or "You craft ..."), far from it the server must send it to the bench. Bots never
## carry 3 ash wood and 2 stone this early, so the real craft is proven by the unit tests;
## this proves the server routes /craft, checks the bench from its own position, and answers.
## Positions within a metre of the bench's edge are skipped, since the bot may drift.

const FIRST_DELAY := 1.0 ## before gameplay_gathering walks off (it starts 3 s in)
const RETRY_AFTER := 1.5 ## an unanswered line (shared 0.5 s chat cooldown) is sent again
const MAX_TRIES := 4
const EDGE := 1.0

var _step := 0 ## 0 idle, 1 list, 2 axe
var _next_at := 0.0
var _tries := 0
var _expect := "" ## "bench", "pack" or "" (too close to the edge to say)
var lists := 0
var bench_checks := 0
var pack_checks := 0
var skipped := 0


func setup(net: Node) -> void:
	net.system_message.connect(_on_system)


func on_login(_reconnect: bool, _character: Dictionary) -> void:
	_step = 1
	_tries = 0
	_next_at = bot.elapsed + FIRST_DELAY


func on_play(_delta: float) -> void:
	if _step == 0:
		return
	bot.move = Vector2.ZERO # hold still so the server's position is the one we judge by
	if bot.elapsed < _next_at:
		return
	if _tries >= MAX_TRIES:
		_step = 0 # chat was busy this login; the other login or the unit tests cover it
		return
	_tries += 1
	_next_at = bot.elapsed + RETRY_AFTER
	if _step == 1:
		bot.send_command("/craft")
	else:
		bot.send_command("/craft axe", _judge_position)


## Runs when the bot harness actually sends /craft axe, so the position judged is the one the
## server sees (the line may wait a moment behind other behaviours' commands).
func _judge_position() -> void:
	var d := Vector2(bot.my_pos.x, bot.my_pos.z).distance_to(Crafting.WORKBENCH_XZ)
	_expect = "pack" if d < Crafting.BENCH_RANGE - EDGE else ("bench" if d > Crafting.BENCH_RANGE + EDGE else "")


func _on_system(text: String) -> void:
	if _step == 1 and text.begins_with("Recipes"):
		lists += 1
		if not text.contains("stone axe"):
			fail("recipe list without the stone axe: %s" % text)
		_step = 2
		_tries = 0
		_next_at = 0.0
	elif _step == 2 and (text.begins_with("You need") or text.begins_with("You craft") or text.begins_with("You already") or text.begins_with("A stone axe needs")):
		var sent_to_bench := text.begins_with("A stone axe needs")
		match _expect:
			"pack":
				pack_checks += 1
				if sent_to_bench:
					fail("at the workbench (%s) but told to go to it: %s" % [bot.my_pos, text])
			"bench":
				bench_checks += 1
				if not sent_to_bench:
					fail("far from the workbench (%s) but got: %s" % [bot.my_pos, text])
			_:
				skipped += 1
		_step = 0


func on_finish() -> void:
	stat("lists", lists)
	stat("pack_checks", pack_checks)
	stat("bench_checks", bench_checks)
	stat("skipped", skipped)
	if lists < 1:
		fail("/craft never listed the recipes")
	if pack_checks + bench_checks < 1:
		fail("/craft axe was never answered where the right answer was clear")

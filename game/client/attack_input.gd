class_name AttackInput
extends RefCounted
## The attack keys (protocol v7, c2s_attack): left click is a light swing and right click a
## heavy one, whenever the click isn't gathering. Pure rules over one frame's input, so the
## "which click does what" table is unit tested (test_client_attack_input.gd).
##
## - Left click on a node you can gather keeps gathering (the action camera's "E or
##   left-click"): it starts the gather, or keeps chopping while you already are. Anywhere
##   else (the sky, a grazer, open ground, a spent node, a tree you can't fell yet) it swings.
## - Right click always swings heavy, even mid-gather: the server never cuts a gather short
##   for a swing, so the client sends c2s_gather_cancel first (both reliable and ordered).
## - A left click mid-gather that is aimed off the node also cancels and swings, so a grazer
##   wandering up while you chop is one click away.
## - While your own swing plays, or within MIN_GAP of the last one sent, clicks are dropped
##   here (the server would only answer "busy"), so mashing the button sends one swing, not
##   a stream.
##
## Returns {} for nothing, else {"kind": "light"|"heavy", "cancel_gather": bool}.

const MIN_GAP := 0.15 ## seconds between two c2s_attack sends, at most


static func decide(light_pressed: bool, heavy_pressed: bool, gather_op: Dictionary, target: Dictionary, gathering: bool, waiting: bool, swinging: bool, since_sent: float = INF) -> Dictionary:
	if not light_pressed and not heavy_pressed:
		return {}
	if swinging or since_sent < MIN_GAP:
		return {}
	if heavy_pressed:
		return {"kind": "heavy", "cancel_gather": gathering}
	# A light click: did the gather side want it?
	if str(gather_op.get("op", "")) == "start" or waiting:
		return {}
	var on_node := not target.is_empty() and bool(target.get("aimed", false)) and bool(target.get("can", false))
	if on_node:
		return {} # click-to-gather, or a click while chopping keeps chopping
	return {"kind": "light", "cancel_gather": gathering}


## When the blow of a swing lands, in seconds after s2c_swing: the weapon's windup, stretched
## by the same factor client.gd stretches the animation to the server's `seconds`.
static func blow_delay(weapon: String, kind: String, seconds: float) -> float:
	var a := Weapons.attack(weapon, kind)
	if a.is_empty():
		return 0.0
	var total := float(a.windup) + float(a.active) + float(a.recovery)
	var k := seconds / total if seconds > 0.0 and total > 0.0 else 1.0
	return float(a.windup) * k

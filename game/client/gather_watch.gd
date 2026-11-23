class_name GatherWatch
extends RefCounted
## Everyone's timed gathers as this client sees them (yours too), turned into what the world
## shows: a hit reaction on the node when a gather pays out, and the node's empty look when
## the server says it is spent.
##
## The server tells you a node emptied (s2c_node_state) a moment before it tells you the
## gather that emptied it is done (s2c_gather_end "done"). World asks for play_hit first and
## then set_depleted, so the last hit still sheds leaves or chips. So a depletion on a node
## someone is gathering waits for that gather's end (at most DEFER_MAX seconds).
##
## Pure bookkeeping: every call returns ops for the client to apply, so it is unit tested
## without a world. Ops: ["hit", node_id] and ["deplete", node_id, depleted: bool].

const DEFER_MAX := 0.6

var running := {} ## peer id -> node id being gathered
var _deferred := {} ## node id -> time (s) by which its depletion shows anyway


## s2c_gather_begin(peer, node, seconds).
func begun(peer: int, node_id: int) -> void:
	running[peer] = node_id


## s2c_gather_end(peer, node, reason).
func ended(peer: int, node_id: int, reason: String) -> Array:
	if int(running.get(peer, -1)) == node_id:
		running.erase(peer)
	var ops: Array = []
	if reason == "done":
		ops.append(["hit", node_id])
	if _deferred.has(node_id) and (reason == "done" or not _busy(node_id)):
		_deferred.erase(node_id)
		ops.append(["deplete", node_id, true])
	return ops


## s2c_node_state(node, depleted) at time `now` (seconds).
func node_state(node_id: int, depleted: bool, now: float) -> Array:
	if depleted and _busy(node_id):
		_deferred[node_id] = now + DEFER_MAX
		return []
	_deferred.erase(node_id)
	return [["deplete", node_id, depleted]]


## Every frame: depletions whose gather end never came show now.
func tick(now: float) -> Array:
	var ops: Array = []
	for id in _deferred.keys():
		if now >= float(_deferred[id]):
			_deferred.erase(id)
			ops.append(["deplete", id, true])
	return ops


## A peer left: their gather is over (the server sends no end for a gatherer who left view).
func forget(peer: int) -> void:
	running.erase(peer)


func reset() -> void:
	running.clear()
	_deferred.clear()


func _busy(node_id: int) -> bool:
	return running.values().has(node_id)

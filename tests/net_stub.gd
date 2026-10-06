class_name NetStub
extends RefCounted
## Stands in for the Game scene in tests: records what the host sends.

var sent := {}


func send(_peer: int, method: String, args: Array) -> void:
	_count(method, args)


func broadcast(method: String, args: Array) -> void:
	_count(method, args)


func _count(method: String, args: Array) -> void:
	if not sent.has(method):
		sent[method] = []
	if sent[method].size() < 2000:
		sent[method].append(args)

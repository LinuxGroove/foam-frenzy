extends Node
## Optional online features through the shared Nakama server (autoload: LGOnline).
##
## Everything here is optional: games must work with no server at all. All
## calls return quickly with a failure when the server is off or unreachable,
## and nothing is retried in a loop.
##
## Remote play uses Nakama's realtime relay with Godot's high-level
## multiplayer API (NakamaMultiplayerBridge), so the same host-authoritative
## game code runs over LAN (ENet) or online (relay) unchanged. Rooms are
## Nakama named matches, "<game>:<CODE>", so friends join with a short code
## and the server needs no custom logic for it.

signal status_changed(status: String)
signal _join_settled
signal _connect_settled(ok: bool)

## No look-alikes in the Kenney fonts (0/O, 1/I/L, 2/Z, 5/S, 8/B).
const CODE_ALPHABET := "CDFGHJKMNPQRTVWX34679"
const CODE_LENGTH := 6
## last_error values for a room that has no host, or already has one.
const NO_ROOM := "no_room"
const ROOM_TAKEN := "room_taken"
## last_error values when quick match ends without a room.
const NO_MATCH := "no_match"
const CANCELLED := "cancelled"

var status := "offline"
var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
var bridge: NakamaMultiplayerBridge
var room_code := ""
var last_error := ""
## A sign-in is under way; later callers wait for it instead of starting
## a second one.
var _connecting := false
## Ends the running quick-match search (see cancel_matchmaking).
var _cancel_search := Callable()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func is_enabled() -> bool:
	var settings := get_node_or_null("/root/LGSettings")
	return settings != null and bool(settings.get_value("online", "enabled"))


func is_connected_online() -> bool:
	return session != null and socket != null and socket.is_connected_to_host()


## Authenticates this device and opens the realtime socket. The server
## refuses logins that don't say which game and version they come from.
func connect_async(display_name: String, game_id: String) -> bool:
	if is_connected_online():
		return true
	if _connecting:
		return await _connect_settled
	_connecting = true
	var ok := await _connect(display_name, game_id)
	_connecting = false
	_connect_settled.emit(ok)
	return ok


func _connect(display_name: String, game_id: String) -> bool:
	var settings := get_node("/root/LGSettings")
	_set_status("connecting")
	client = Nakama.create_client(
		str(settings.get_value("online", "server_key")),
		str(settings.get_value("online", "host")),
		int(settings.get_value("online", "port")),
		str(settings.get_value("online", "scheme")),
		5, NakamaLogger.LOG_LEVEL.ERROR)
	var vars := {
		"game": game_id,
		"version": str(ProjectSettings.get_setting("application/config/version", "0.0.0")),
		"platform": "ubuntu" if OS.get_name() == "Linux" else OS.get_name().to_lower(),
	}
	session = await client.authenticate_device_async(Nakama.get_device_id(), null, true, vars)
	if session.is_exception():
		var msg: String = session.get_exception().message
		if msg.begins_with("update_required"):
			return _fail("The game server needs a newer version of this game. Please update.")
		return _fail("Could not sign in: %s" % msg)
	if display_name != "":
		# Best effort; a taken or invalid name shouldn't block play.
		await client.update_account_async(session, null, display_name)
	socket = Nakama.create_socket_from(client)
	var res: NakamaAsyncResult = await socket.connect_async(session)
	if res.is_exception():
		return _fail("Could not open the realtime connection: %s" % res.get_exception().message)
	socket.closed.connect(_on_socket_closed)
	_set_status("online")
	return true


## Creates a relay room and returns its code ("" on failure). The scene's
## multiplayer is already using `bridge.multiplayer_peer` when this returns.
func host_room_async(game_id: String) -> String:
	# A fresh code can land on a room someone else is in; try another.
	for _attempt in 3:
		var code := _new_code()
		if await _join_named(game_id, code, true):
			return code
		if last_error != ROOM_TAKEN:
			break
	return ""


## Joins the room with this code. Fails with last_error NO_ROOM when nobody
## is hosting it.
func join_room_async(game_id: String, code: String) -> bool:
	code = normalize_code(code)
	if not is_connected_online():
		return false
	# Ask first: joining a code nobody hosts would open a room for the typo.
	# Servers without the lookup answer something else; join and let
	# _join_named catch it.
	var found = await client.rpc_async(session, "core.room_find", JSON.stringify({"code": code}))
	if found.is_exception() and str(found.get_exception().message).begins_with("room_not_found"):
		return _fail(NO_ROOM)
	return await _join_named(game_id, code, false)


## Quick match: waits up to `timeout` seconds for other players of this game
## who are also looking, then joins them in a room. Returns "host" or "guest"
## (the bridge picks the host), or "" with last_error NO_MATCH when nobody
## turned up in time, CANCELLED after cancel_matchmaking(), or a server error.
## The scene's multiplayer is using the room's peer when it returns a role.
func find_match_async(min_players: int, max_players: int, timeout := 60.0) -> String:
	if not is_connected_online():
		return ""
	leave_room()
	bridge = NakamaMultiplayerBridge.new(socket)
	# Attach first and settle inside match_joined, as in _join_named.
	multiplayer.multiplayer_peer = bridge.multiplayer_peer
	var result := {"done": false, "ok": false}
	var settle := func(ok: bool, error: String):
		if not result.done:
			result.done = true
			result.ok = ok
			if error != "":
				last_error = error
			_join_settled.emit()
	bridge.match_joined.connect(func(): settle.call(true, ""), CONNECT_ONE_SHOT)
	bridge.match_join_error.connect(func(err):
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		settle.call(false, str(err.message) if err else "join failed"), CONNECT_ONE_SHOT)
	_cancel_search = func(): settle.call(false, CANCELLED)
	get_tree().create_timer(timeout).timeout.connect(func(): settle.call(false, NO_MATCH))
	# The server limits the ticket to this game's players.
	var ticket = await socket.add_matchmaker_async("*", min_players, max_players)
	if ticket.is_exception():
		settle.call(false, str(ticket.get_exception().message))
	elif result.done:
		await socket.remove_matchmaker_async(ticket.ticket)
	else:
		bridge.start_matchmaking(ticket)
	if not result.done:
		await _join_settled
	_cancel_search = Callable()
	if not result.ok:
		if bridge:
			if multiplayer.multiplayer_peer == bridge.multiplayer_peer:
				multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
			# Also removes the ticket, or leaves a room joined too late.
			bridge.leave()
			bridge = null
		if last_error in [NO_MATCH, CANCELLED]:
			_set_status("online")
		else:
			_fail(last_error)
		return ""
	room_code = ""
	return "host" if bridge.multiplayer_peer.get_unique_id() == 1 else "guest"


## Stops a find_match_async() that's still looking.
func cancel_matchmaking() -> void:
	if _cancel_search.is_valid():
		_cancel_search.call()


func leave_room() -> void:
	if bridge:
		bridge.leave()
		bridge = null
	room_code = ""


## Calls a server RPC with a JSON payload. Returns the parsed response or null.
func rpc_async(rpc_id: String, payload: Dictionary) -> Variant:
	if not is_connected_online():
		return null
	var res = await client.rpc_async(session, rpc_id, JSON.stringify(payload))
	if res.is_exception():
		push_warning("Online: RPC %s failed: %s" % [rpc_id, res.get_exception().message])
		return null
	return JSON.parse_string(res.payload) if res.payload != "" else {}


## One leaderboard: its top `limit` records and this player's own, as
## {"top": [row, ...], "mine": row or null}, where a row is {"rank", "name",
## "score", "me"}. Null on failure (see last_error). Weekly boards show the
## current week.
func leaderboard_async(game_id: String, board: String, limit := 10) -> Variant:
	if not is_connected_online():
		return null
	var res = await client.list_leaderboard_records_async(session, "%s.%s" % [game_id, board], [session.user_id], null, limit)
	if res.is_exception():
		last_error = str(res.get_exception().message)
		return null
	# Records carry the account's username, which is random for device
	# logins; players pick a display name, so look those up.
	var ids := PackedStringArray()
	for r in res.records + res.owner_records:
		if not r.owner_id in ids:
			ids.append(r.owner_id)
	var names := {}
	if not ids.is_empty():
		var users = await client.get_users_async(session, ids)
		if not users.is_exception():
			for u in users.users:
				names[u.id] = u.display_name if u.display_name != "" else u.username
	var row := func(r) -> Dictionary:
		return {
			"rank": int(r.rank),
			"name": names.get(r.owner_id, r.username),
			"score": int(r.score),
			"me": r.owner_id == session.user_id,
		}
	var top := []
	for r in res.records:
		top.append(row.call(r))
	var mine = null
	if not res.owner_records.is_empty():
		mine = row.call(res.owner_records[0])
	return {"top": top, "mine": mine}


## This player's stats object, written by the game's server module when the
## host reports a round (`<game>.stats`, key `stats` by convention). {} when
## the player hasn't finished an online round yet; null on failure.
func stats_async(game_id: String, collection := "stats", key := "stats") -> Variant:
	if not is_connected_online():
		return null
	var id := NakamaStorageObjectId.new("%s.%s" % [game_id, collection], key, session.user_id)
	var res = await client.read_storage_objects_async(session, [id])
	if res.is_exception():
		last_error = str(res.get_exception().message)
		return null
	if res.objects.is_empty():
		return {}
	var value = JSON.parse_string(res.objects[0].value)
	return value if value is Dictionary else {}


## The account id behind a multiplayer peer in the current room ("" if unknown).
func user_id_for_peer(peer_id: int) -> String:
	if peer_id == 1 and bridge and bridge.multiplayer_peer.get_unique_id() == 1 and session:
		return session.user_id
	if bridge == null:
		return ""
	var presence = bridge.get_user_presence_for_peer(peer_id)
	return presence.user_id if presence else ""


func disconnect_online() -> void:
	leave_room()
	if socket:
		socket.close()
	socket = null
	session = null
	_set_status("offline")


static func normalize_code(code: String) -> String:
	return code.strip_edges().to_upper().replace("-", "").replace(" ", "")


## Whether a code could name a room (the server takes 4-16 letters and digits).
static func is_valid_code(code: String) -> bool:
	var c := normalize_code(code)
	if c.length() < 4 or c.length() > 16:
		return false
	for ch in c:
		if not ((ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9")):
			return false
	return true


## Joining a named room creates it when it's empty, and the bridge makes
## whoever arrives first the host, so check we got the role we asked for.
func _join_named(game_id: String, code: String, as_host: bool) -> bool:
	if not is_connected_online():
		return false
	leave_room()
	bridge = NakamaMultiplayerBridge.new(socket)
	# Attach the peer before joining: a guest's bridge announces the host
	# (peer 1) the moment it is assigned an id, and a multiplayer API that
	# attaches later never hears it, so every RPC to the host fails.
	multiplayer.multiplayer_peer = bridge.multiplayer_peer
	# Settle inside the bridge's match_joined signal, not on a later frame:
	# awaiting callers resume right there, before the bridge announces the
	# host and the guest's hello goes out, so the caller's state is set
	# before the host can answer (or kick).
	var result := {"done": false, "ok": false}
	var settle := func(ok: bool):
		if not result.done:
			result.done = true
			result.ok = ok
			_join_settled.emit()
	bridge.match_joined.connect(func(): settle.call(true), CONNECT_ONE_SHOT)
	bridge.match_join_error.connect(func(err):
		last_error = str(err.message) if err else "join failed"
		# Detach before the bridge drops its peer, so a refused join isn't
		# reported as a lost host.
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		settle.call(false), CONNECT_ONE_SHOT)
	get_tree().create_timer(10.0).timeout.connect(func(): settle.call(false))
	bridge.join_named_match("%s:%s" % [game_id, code])
	if not result.done:
		await _join_settled
	var error := ""
	if not result.ok:
		error = "Could not join room %s" % code
	elif (bridge.multiplayer_peer.get_unique_id() == 1) != as_host:
		error = ROOM_TAKEN if as_host else NO_ROOM
	if error != "":
		if multiplayer.multiplayer_peer == bridge.multiplayer_peer:
			multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
		bridge.leave()
		bridge = null
		return _fail(error)
	room_code = code
	return true


func _new_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var code := ""
	for i in CODE_LENGTH:
		code += CODE_ALPHABET[rng.randi_range(0, CODE_ALPHABET.length() - 1)]
	return code


func _fail(message: String) -> bool:
	last_error = message
	push_warning("Online: " + message)
	_set_status("error")
	return false


func _on_socket_closed() -> void:
	_set_status("offline")


func _set_status(s: String) -> void:
	status = s
	status_changed.emit(s)

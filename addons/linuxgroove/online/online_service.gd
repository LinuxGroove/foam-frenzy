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

## No look-alikes in the Kenney fonts (0/O, 1/I/L, 2/Z, 5/S, 8/B).
const CODE_ALPHABET := "CDFGHJKMNPQRTVWX34679"
const CODE_LENGTH := 6

var status := "offline"
var client: NakamaClient
var session: NakamaSession
var socket: NakamaSocket
var bridge: NakamaMultiplayerBridge
var room_code := ""
var last_error := ""


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


## Creates a relay room and returns its code ("" on failure). The scene
## tree's multiplayer is already using `LGOnline.bridge.multiplayer_peer`.
func host_room_async(game_id: String) -> String:
	var code := _new_code()
	if await _join_named(game_id, code):
		return code
	return ""


func join_room_async(game_id: String, code: String) -> bool:
	return await _join_named(game_id, normalize_code(code))


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


func _join_named(game_id: String, code: String) -> bool:
	if not is_connected_online():
		return false
	leave_room()
	bridge = NakamaMultiplayerBridge.new(socket)
	# The bridge announces the host the moment it joins, before this returns,
	# so the scene's multiplayer must already be listening or it never learns
	# that peer 1 is there (and drops everything the host sends).
	var mp := get_tree().get_multiplayer()
	mp.multiplayer_peer = bridge.multiplayer_peer
	var result := {"done": false, "ok": false}
	bridge.match_joined.connect(func():
		result.ok = true
		result.done = true, CONNECT_ONE_SHOT)
	bridge.match_join_error.connect(func(err):
		last_error = str(err.message) if err else "join failed"
		result.done = true, CONNECT_ONE_SHOT)
	bridge.join_named_match("%s:%s" % [game_id, code])
	var waited := 0.0
	while not result.done and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	if not result.ok:
		bridge = null
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()
		return _fail("Could not join room %s" % code)
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

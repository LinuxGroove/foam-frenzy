extends Node
## The lobby and transport for one play session (autoload: Session).
##
## Every mode runs the same host-authoritative match:
##   SOLO     this device hosts with bots, no network (OfflineMultiplayerPeer)
##   LAN      ENet on the local network, found by LanBeacon or a join code
##   ONLINE   Nakama relay through the shared game server, joined by room code
## Peer 1 is always the host. Bots get negative ids and exist only on the host.
##
## Each device can bring up to GameConfig.MAX_LOCAL players (couch play): the
## keyboard and mouse player plus one per extra controller. A player's actor
## id is peer * 4 + seat, so it is the same on every device.

signal roster_changed
signal settings_changed
signal seats_changed
signal hosts_found(hosts: Array)
signal joined
signal left(reason: String)
signal status(text: String)
## Host: a player's device has loaded the arena and can receive the match.
signal peer_loaded(id: int)

enum Mode { NONE, SOLO, LAN_HOST, LAN_CLIENT, ONLINE_HOST, ONLINE_CLIENT }

const HELLO_TIMEOUT := 6.0
const SEATS_PER_PEER := 4

var mode := Mode.NONE
## actor id -> {"name", "look", "blaster", "slot", "bot", "peer", "seat"}
var players := {}
var settings := Rules.DEFAULT_SETTINGS.duplicate()
var join_code := ""
var lan_address := ""
var in_match := false
var match_config := {}
## Host: peers whose game scene is ready, so match messages can reach them.
var loaded_peers := {}
var matches_played := 0
## The next match is a practice round (see MatchHost.practice).
var practice := false
## This device's players: [{"pad", "name", "look", "blaster"}]. Seat 0 is the
## keyboard player (pad LGSeat.ANY_FREE_PAD); the rest each own a controller.
var local_seats: Array = []

var _beacon: LanBeacon
var _pending_hello := {}
var _seat_inputs := {}


func _ready() -> void:
	_beacon = LanBeacon.new()
	_beacon.name = "Beacon"
	add_child(_beacon)
	_beacon.hosts_changed.connect(_on_beacon_hosts)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	# Seats read the game's settings, which main.gd would register later.
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	_reset_seats()


func is_host() -> bool:
	return mode in [Mode.SOLO, Mode.LAN_HOST, Mode.ONLINE_HOST]


func is_online() -> bool:
	return mode in [Mode.ONLINE_HOST, Mode.ONLINE_CLIENT]


func local_id() -> int:
	return multiplayer.get_unique_id()


func player_name() -> String:
	var n := str(LGSettings.get_value("player", "name")).strip_edges()
	return n if n != "" else "Camper"


func player_look() -> int:
	return int(LGSettings.get_value("player", "look"))


static func actor_id(peer: int, seat: int) -> int:
	return peer * SEATS_PER_PEER + seat


# --- Couch seats ---------------------------------------------------------

## The controls for this device's seat `index`.
func seat_input(index: int) -> LGSeat:
	if not _seat_inputs.has(index):
		if index == 0 or index >= local_seats.size():
			_seat_inputs[index] = LGSeat.primary()
		else:
			_seat_inputs[index] = LGSeat.for_pad(index, int(local_seats[index].pad))
		_seat_inputs[index].deadzone = float(LGSettings.get_value("input", "stick_deadzone"))
	return _seat_inputs[index]


## Adds a player on controller `pad`. Returns the new seat index, or -1.
func add_local_seat(pad: int) -> int:
	if local_seats.size() >= GameConfig.MAX_LOCAL or in_match:
		return -1
	for s in local_seats:
		if int(s.pad) == pad:
			return -1
	var index := local_seats.size()
	var used := []
	for p in players.values():
		used.append(int(p.look))
	for s in local_seats:
		used.append(int(s.look))
	local_seats.append({
		"pad": pad,
		"name": "Player %d" % (index + 1),
		"look": _free_look(used),
		"blaster": randi() % Rules.BLASTERS.size(),
	})
	LGInput.claim_pad(pad, index)
	_seats_updated()
	return index


func remove_local_seat(index: int) -> void:
	if index <= 0 or index >= local_seats.size() or in_match:
		return
	LGInput.release_pad(int(local_seats[index].pad))
	local_seats.remove_at(index)
	# Seats after it move up one place.
	for i in range(1, local_seats.size()):
		LGInput.claim_pad(int(local_seats[i].pad), i)
	_seats_updated()


func set_seat_value(index: int, key: String, value: Variant) -> void:
	if index < 0 or index >= local_seats.size():
		return
	local_seats[index][key] = value
	if index == 0:
		match key:
			"look":
				LGSettings.set_value("player", "look", value)
			"blaster":
				LGSettings.set_value("play", "blaster", value)
	_seats_updated()


## The seat whose controller is `pad`, or -1.
func seat_for_pad(pad: int) -> int:
	for i in range(1, local_seats.size()):
		if int(local_seats[i].pad) == pad:
			return i
	return -1


func _reset_seats() -> void:
	for i in range(1, local_seats.size()):
		LGInput.release_pad(int(local_seats[i].pad))
	local_seats = [{
		"pad": LGSeat.ANY_FREE_PAD,
		"name": player_name(),
		"look": player_look(),
		"blaster": int(LGSettings.get_value("play", "blaster")),
	}]
	_seat_inputs.clear()


func _seats_updated() -> void:
	_seat_inputs.clear()
	local_seats[0].name = player_name()
	if is_host():
		_apply_seats(1, _seat_payload())
	elif mode != Mode.NONE:
		_c_seats.rpc_id(1, _seat_payload())
	seats_changed.emit()


func _seat_payload() -> Array:
	var out := []
	for s in local_seats:
		out.append([str(s.name), int(s.look), int(s.blaster)])
	return out


## Host: replaces peer's players with the seats it sent.
func _apply_seats(peer: int, seats: Array) -> void:
	var keep_slots := {}
	for id in players.keys():
		var p: Dictionary = players[id]
		if not p.bot and int(p.peer) == peer:
			keep_slots[int(p.seat)] = int(p.slot)
			players.erase(id)
	for i in mini(seats.size(), GameConfig.MAX_LOCAL):
		var s: Array = seats[i]
		if players.size() >= GameConfig.MAX_PLAYERS and not _drop_a_bot():
			break
		var id := actor_id(peer, i)
		players[id] = {
			"name": _unique_name(str(s[0]).strip_edges().left(16)),
			"look": clampi(int(s[1]), 0, GameConfig.LOOKS.size() - 1),
			"blaster": clampi(int(s[2]), 0, Rules.BLASTERS.size() - 1),
			"slot": keep_slots.get(i, _free_slot()),
			"bot": false, "peer": peer, "seat": i,
		}
	_broadcast_roster()


# --- Starting and joining ----------------------------------------------

func start_solo(bots := 3) -> void:
	leave()
	mode = Mode.SOLO
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_apply_seats(1, _seat_payload())
	for i in bots:
		add_bot()
	joined.emit()
	roster_changed.emit()


## A guided practice round: you and two easy-going sparring bots, no clock.
func start_practice() -> void:
	start_solo(0)
	practice = true
	var saved := settings.duplicate()
	settings = Rules.DEFAULT_SETTINGS.duplicate()
	settings.target = 99
	for name in ["Coach Pip", "Coach Bea"]:
		add_bot()
		var id: int = players.keys().min()
		players[id].name = name
	start_match()
	settings = saved


func host_lan() -> bool:
	leave()
	var port := int(LGSettings.get_value("lan", "port"))
	var peer := LanNet.create_host(port, GameConfig.MAX_PLAYERS - 1)
	if peer == null:
		status.emit("Couldn't host on port %d. Is another game already hosting?" % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_HOST
	lan_address = LanNet.local_address()
	join_code = JoinCode.encode(lan_address, port, port) if lan_address != "" else ""
	_apply_seats(1, _seat_payload())
	_beacon.start_advertising(_beacon_info(), int(LGSettings.get_value("lan", "beacon_port")))
	joined.emit()
	roster_changed.emit()
	return true


func browse_lan() -> void:
	_beacon.start_listening(int(LGSettings.get_value("lan", "beacon_port")))


func stop_browsing() -> void:
	if mode == Mode.NONE:
		_beacon.stop()


func join_lan(address: String, port: int) -> bool:
	leave()
	var peer := LanNet.create_client(address, port)
	if peer == null:
		status.emit("Couldn't reach %s." % address)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_CLIENT
	status.emit("Connecting to %s..." % address)
	return true


func join_lan_code(code: String) -> bool:
	var port := int(LGSettings.get_value("lan", "port"))
	var target := JoinCode.decode(code, port)
	if target.is_empty():
		status.emit("That code doesn't look right.")
		return false
	return join_lan(target.ip, target.port)


func host_online() -> bool:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	var code: String = await LGOnline.host_room_async(GameConfig.GAME_ID)
	if code == "":
		status.emit(LGOnline.last_error)
		return false
	mode = Mode.ONLINE_HOST
	join_code = code
	_apply_seats(1, _seat_payload())
	joined.emit()
	roster_changed.emit()
	return true


func join_online(code: String) -> bool:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	if not await LGOnline.join_room_async(GameConfig.GAME_ID, code):
		status.emit("No room with code %s." % LGOnline.normalize_code(code))
		return false
	# A code nobody is using opens a new, empty room with us as its host.
	# Don't sit in it waiting for a host who isn't coming.
	if LGOnline.bridge.multiplayer_peer.get_unique_id() == 1:
		leave()
		status.emit("No room with code %s. Check the code with the host." % LGOnline.normalize_code(code))
		return false
	mode = Mode.ONLINE_CLIENT
	join_code = LGOnline.normalize_code(code)
	# connected_to_server has already sent the hello: the bridge announced
	# the host while joining.
	return true


## Ends the session. Couch players stay seated for the next one.
func leave(reason := "") -> void:
	var was := mode
	get_tree().paused = false
	_beacon.stop()
	if is_online() or LGOnline.bridge:
		# The bridge's peer can't be closed directly; leaving the room does it.
		LGOnline.leave_room()
	elif multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	players.clear()
	join_code = ""
	in_match = false
	match_config = {}
	loaded_peers.clear()
	matches_played = 0
	practice = false
	_pending_hello.clear()
	if was != Mode.NONE:
		left.emit(reason)


# --- Host: lobby management ---------------------------------------------

func add_bot() -> void:
	if not is_host() or players.size() >= GameConfig.MAX_PLAYERS:
		return
	var id := -1
	while players.has(id):
		id -= 1
	var used_names := []
	var used_looks := []
	for p in players.values():
		used_names.append(p.name)
		used_looks.append(p.look)
	var name := "Bot"
	for n in GameConfig.BOT_NAMES:
		if not n in used_names:
			name = n
			break
	players[id] = {
		"name": name, "look": _free_look(used_looks), "blaster": randi() % Rules.BLASTERS.size(),
		"slot": _free_slot(), "bot": true, "peer": 0, "seat": 0,
	}
	_broadcast_roster()


func remove_bot() -> void:
	if not is_host():
		return
	var bot_ids := players.keys().filter(_is_bot)
	if bot_ids.is_empty():
		return
	bot_ids.sort()
	players.erase(bot_ids[0])
	_broadcast_roster()


func set_setting(key: String, value: Variant) -> void:
	if not is_host():
		return
	settings[key] = value
	_broadcast_roster()


func human_count() -> int:
	return players.values().filter(func(p): return not p.bot).size()


func can_start() -> bool:
	return is_host() and players.size() >= GameConfig.MIN_PLAYERS and not in_match


## Why the host can't start yet, or "".
func start_blocker() -> String:
	if players.size() < GameConfig.MIN_PLAYERS:
		return "A match needs at least %d campers. Add a bot or wait for friends." % GameConfig.MIN_PLAYERS
	return ""


## Host: deals out the match and tells everyone to load the arena.
func start_match() -> void:
	if not can_start():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var config := {
		"seed": rng.randi(),
		"players": players.duplicate(true),
		"settings": settings.duplicate(),
		"practice": practice,
	}
	_beacon.update_info({"state": "playing"})
	loaded_peers.clear()
	for peer_id in multiplayer.get_peers():
		if not _pending_hello.has(peer_id):
			_h_start_match.rpc_id(peer_id, config)
	_h_start_match(config)


## Host: deals a fresh match with the same players.
func restart_match() -> void:
	# A double press on "Play again" would deal two matches back to back.
	if is_host() and not LGScenes.is_busy():
		get_tree().paused = false
		in_match = false
		start_match()


## Host: everyone goes back to the lobby after a match.
func return_to_lobby() -> void:
	if not is_host() or not in_match or LGScenes.is_busy():
		return
	get_tree().paused = false
	practice = false
	_beacon.update_info({"state": "lobby"})
	for peer_id in multiplayer.get_peers():
		_h_return_to_lobby.rpc_id(peer_id)
	_h_return_to_lobby()


## Host of an online room: reports the match to the game server for stats
## and leaderboards. Each device's first player is the signed-in account;
## bots and couch guests aren't reported.
func report_match(result: Dictionary) -> void:
	if mode != Mode.ONLINE_HOST or LGOnline.bridge == null or bool(result.get("practice", false)):
		return
	matches_played += 1
	var stats: Dictionary = result.get("stats", {})
	var standings: Array = result.get("standings", [])
	var reported := []
	for row in standings:
		var id := int(row[0])
		var p: Dictionary = match_config.get("players", {}).get(id, {})
		if p.is_empty() or bool(p.get("bot", false)) or int(p.get("seat", 0)) != 0:
			continue
		var uid := LGOnline.user_id_for_peer(int(p.peer))
		if uid == "":
			continue
		var s: Dictionary = stats.get(id, {})
		var won := false
		if not bool(result.tie):
			won = int(result.winner) == id or (int(result.team) >= 0 and int(row[4]) == int(result.team))
		reported.append({
			"user_id": uid,
			"tags": int(s.get("tags", 0)),
			"outs": int(s.get("outs", 0)),
			"captures": int(s.get("captures", 0)),
			"won": won,
		})
	if reported.is_empty():
		return
	LGOnline.rpc_async("%s.match_report" % GameConfig.GAME_ID, {
		"match_id": LGOnline.bridge.match_id,
		"round": matches_played,
		"mode": Rules.MODE_KEYS[int(result.mode)],
		"players": reported,
	})


## Called by the game scene once it is in the tree. The host learns which
## peers are ready through Session (always present) rather than the game
## scene, which may not exist yet on the host when a fast client reports.
func report_loaded() -> void:
	if is_host():
		loaded_peers[1] = true
		peer_loaded.emit(1)
	else:
		_c_match_loaded.rpc_id(1)


# --- Network events -----------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending_hello[id] = Time.get_ticks_msec()
		get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(_check_hello.bind(id))


func _check_hello(id: int) -> void:
	if _pending_hello.has(id):
		_pending_hello.erase(id)
		_kick(id, "No hello from this game version.")


func _on_peer_disconnected(id: int) -> void:
	_pending_hello.erase(id)
	if not is_host():
		# Online rooms only say the host's presence left (ENet also sends
		# server_disconnected). Deferred: this runs inside the peer's poll.
		if id == 1 and is_online():
			leave.call_deferred("The host left the game.")
		return
	var names := []
	for aid in players.keys():
		if not players[aid].bot and int(players[aid].peer) == id:
			names.append(players[aid].name)
			players.erase(aid)
	loaded_peers.erase(id)
	if names.is_empty():
		return
	_broadcast_roster()
	status.emit("%s left." % " and ".join(names))
	var game := get_tree().current_scene
	if in_match and game and game.has_method("on_player_left"):
		game.on_player_left(id)


func _on_connected_to_server() -> void:
	_send_hello()


func _send_hello() -> void:
	local_seats[0].name = player_name()
	_c_hello.rpc_id(1, GameConfig.version(), GameConfig.PROTOCOL, _seat_payload())


func _on_connection_failed() -> void:
	status.emit("Couldn't connect to the host.")
	leave("Couldn't connect to the host.")


func _on_server_disconnected() -> void:
	leave("The host left the game.")


func _on_beacon_hosts(hosts: Array) -> void:
	hosts_found.emit(hosts.filter(func(h): return str(h.get("game", "")) == GameConfig.GAME_ID))


## A couch player's controller was unplugged: they leave their seat (between
## matches; mid-match their camper just stands still until it's back).
func _on_joy_connection_changed(device: int, connected: bool) -> void:
	if connected or in_match:
		return
	var seat := seat_for_pad(device)
	if seat > 0:
		remove_local_seat(seat)
		status.emit("A controller was disconnected, so Player %d left." % (seat + 1))


# --- RPCs ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _c_hello(version: String, protocol: int, seats: Array) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	_pending_hello.erase(id)
	if protocol != GameConfig.PROTOCOL:
		_kick(id, "This game is version %s. Update Foam Frenzy to play together." % GameConfig.version())
		return
	if in_match:
		_kick(id, "A match is already under way. Join after it ends.")
		return
	if players.size() >= GameConfig.MAX_PLAYERS and not players.values().any(func(p): return p.bot):
		_kick(id, "This game is full.")
		return
	_apply_seats(id, seats)
	var names := []
	for aid in players:
		if int(players[aid].peer) == id and not players[aid].bot:
			names.append(players[aid].name)
	status.emit("%s joined." % " and ".join(names))
	if version != GameConfig.version():
		status.emit("%s has version %s (you have %s)." % [names[0] if not names.is_empty() else "A player", version, GameConfig.version()])


@rpc("any_peer", "reliable")
func _c_seats(seats: Array) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and not in_match and not _pending_hello.has(id) and players.values().any(func(p): return not p.bot and int(p.peer) == id):
		_apply_seats(id, seats)


@rpc("any_peer", "reliable")
func _c_match_loaded() -> void:
	if is_host() and in_match:
		var id := multiplayer.get_remote_sender_id()
		loaded_peers[id] = true
		peer_loaded.emit(id)


@rpc("authority", "reliable")
func _h_roster(p_players: Dictionary, p_settings: Dictionary, p_code: String) -> void:
	var first := players.is_empty()
	players = p_players
	settings = p_settings
	join_code = p_code
	if first:
		joined.emit()
	roster_changed.emit()
	settings_changed.emit()


@rpc("authority", "reliable")
func _h_kicked(reason: String) -> void:
	leave(reason)


@rpc("authority", "reliable")
func _h_start_match(config: Dictionary) -> void:
	in_match = true
	match_config = config
	LGInput.filter_claimed_pads = false
	LGScenes.change_scene("res://game/game.tscn", func(node): node.set("config", config))


@rpc("authority", "reliable")
func _h_return_to_lobby() -> void:
	in_match = false
	match_config = {}
	LGScenes.change_scene("res://game/ui/lobby.tscn")


func _broadcast_roster() -> void:
	if not is_host():
		return
	if mode != Mode.SOLO:
		for peer_id in multiplayer.get_peers():
			if not _pending_hello.has(peer_id):
				_h_roster.rpc_id(peer_id, players, settings, join_code)
	_beacon.update_info({"players": players.size()})
	roster_changed.emit()
	settings_changed.emit()


func _kick(id: int, reason: String) -> void:
	_h_kicked.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(_disconnect_peer.bind(id))


func _disconnect_peer(id: int) -> void:
	# Online rooms can't drop a player; the kicked game leaves by itself.
	if is_online() or not multiplayer.has_multiplayer_peer():
		return
	if id in multiplayer.get_peers():
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _drop_a_bot() -> bool:
	var bots := players.keys().filter(_is_bot)
	if bots.is_empty():
		return false
	players.erase(bots.min())
	return true


func _is_bot(id: int) -> bool:
	return bool(players[id].bot)


func _free_slot() -> int:
	var used := []
	for p in players.values():
		used.append(int(p.get("slot", -1)))
	for i in GameConfig.MAX_PLAYERS:
		if not i in used:
			return i
	return 0


func _free_look(used: Array) -> int:
	var free := []
	for i in GameConfig.LOOKS.size():
		if not i in used:
			free.append(i)
	return free.pick_random() if not free.is_empty() else 0


func _unique_name(name: String) -> String:
	if name == "":
		name = "Camper"
	var names := []
	for p in players.values():
		names.append(p.name)
	var out := name
	var n := 2
	while out in names:
		out = "%s %d" % [name, n]
		n += 1
	return out


func _beacon_info() -> Dictionary:
	return {
		"game": GameConfig.GAME_ID,
		"version": GameConfig.version(),
		"protocol": GameConfig.PROTOCOL,
		"name": "%s's arena" % player_name(),
		"port": int(LGSettings.get_value("lan", "port")),
		"players": players.size(),
		"max": GameConfig.MAX_PLAYERS,
		"state": "lobby",
		"code": join_code,
	}

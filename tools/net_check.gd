extends Node
## Plays a short match between two copies of the game, online through a real
## game server (for example the LinuxGroove game-server Compose setup on
## localhost) or over the local network with "lan". Run both at once:
##   godot --headless --path . tools/net_check.tscn -- host /tmp/code [lan]
##   godot --headless --path . tools/net_check.tscn -- join /tmp/code [lan]
## Online, the joiner first tries a code nobody is using, which must fail, and
## the host checks the server recorded the match for both players. Each prints
## "NET OK" and exits 0 when its side worked.

const TIMEOUT := 40.0

var _role := ""
var _code_file := ""
var _lan := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_role = args[0] if args.size() > 0 else "host"
	_code_file = args[1] if args.size() > 1 else "/tmp/foam-frenzy-net-code"
	_lan = "lan" in args
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS)
	LGInput.extend_ui_actions()
	# Two copies on one machine would share a device id, and so an account.
	Nakama._device_id = _random_device_id()
	LGSettings.set_value("online", "enabled", true, false)
	LGSettings.set_value("player", "name", "Host" if _role == "host" else "Guest", false)
	LGSettings.set_value("tutorial", "welcomed", true, false)
	LGSettings.set_value("tutorial", "howto_seen", true, false)
	Session.local_seats[0].name = Session.player_name()
	Session.status.connect(_on_status)
	# Scene changes would free this node if it stayed the current scene.
	get_tree().current_scene = null
	var ok: bool
	if _role == "host":
		ok = await _host()
	else:
		ok = await _join()
	print("NET %s %s" % ["OK" if ok else "FAILED", _role])
	Session.leave()
	get_tree().quit(0 if ok else 1)


func _host() -> bool:
	if not (Session.host_lan() if _lan else await Session.host_online()):
		return _fail("could not host: %s" % LGOnline.last_error)
	var f := FileAccess.open(_code_file, FileAccess.WRITE)
	f.store_string(Session.join_code)
	f.close()
	print("room code ", Session.join_code)
	if not await _until(func(): return Session.players.size() >= 2):
		return _fail("the guest never arrived")
	Session.add_bot()
	Session.start_match()
	if not await _until(func(): return _game() != null and _game().host != null and _game().host.phase == Rules.Phase.PLAY):
		return _fail("the match never started")
	var guest_id := -1
	for id in _game().host.actors:
		if not Session.players.get(id, {}).get("bot", true) and int(id) != Session.actor_id(1, 0):
			guest_id = int(id)
	if guest_id < 0:
		return _fail("no guest camper in the match")
	var guest_user := LGOnline.user_id_for_peer(int(Session.players[guest_id].peer))
	var start: Vector2 = _game().host.actors[guest_id].pos
	if not await _until(func(): return start.distance_to(_game().host.actors[guest_id].pos) > 1.0):
		return _fail("the guest's moves never reached the host")
	print("the guest walked %.1f m on the host (%s to %s)" % [start.distance_to(_game().host.actors[guest_id].pos), start, _game().host.actors[guest_id].pos])
	_game().host._finish()
	await get_tree().create_timer(3.0).timeout
	if _lan:
		return true
	for user in [LGOnline.session.user_id, guest_user]:
		var ids := [NakamaStorageObjectId.new("foam-frenzy.stats", "stats", user)]
		var res = await LGOnline.client.read_storage_objects_async(LGOnline.session, ids)
		if res.is_exception() or res.objects.is_empty():
			return _fail("no stats on the server for %s after the match" % user)
		var stats: Dictionary = JSON.parse_string(res.objects[0].value)
		print("server stats for %s: %s" % ["the host" if user == LGOnline.session.user_id else "the guest", stats])
		if int(stats.get("matches", 0)) < 1:
			return _fail("the match report wasn't recorded")
	return true


func _join() -> bool:
	if not _lan:
		if await Session.join_online("QQQQQQ"):
			return _fail("joined a room nobody opened")
		print("an unused code was refused")
		LGOnline.disconnect_online()
	if not await _until(func(): return FileAccess.file_exists(_code_file) and FileAccess.get_file_as_string(_code_file) != ""):
		return _fail("no room code from the host")
	var code := FileAccess.get_file_as_string(_code_file).strip_edges()
	# On the network, join the host's address the way picking a found host
	# does (a join code can name an interface this machine can't reach).
	var lan_port := int(LGSettings.get_value("lan", "port"))
	var joined: bool = Session.join_lan("127.0.0.1", lan_port) if _lan else await Session.join_online(code)
	if not joined:
		return _fail("could not join %s" % code)
	if not await _until(func(): return _game() != null and _game().phase == Rules.Phase.PLAY):
		return _fail("the match never started here")
	# Walk towards the middle so the host can see the moves arrive.
	var me = _game().locals.values()[0]
	var before: Vector2 = me.pos
	var key := KEY_A if before.x > _game().grid.world_size().x * 0.5 else KEY_D
	_key(key, true)
	await get_tree().create_timer(2.0).timeout
	_key(key, false)
	print("walked from %s to %s" % [before, me.pos])
	if not await _until(func(): return _game() != null and not _game().result.is_empty()):
		return _fail("no result from the host")
	print("result from the host: winner %s, %d standings" % [_game().result.get("winner"), _game().result.get("standings", []).size()])
	# When the host goes, this copy must leave the match, not wait forever.
	if not await _until(func(): return Session.mode == Session.Mode.NONE):
		return _fail("still in the match after the host left")
	print("left the match when the host did")
	return true


func _on_status(text: String) -> void:
	print("  (%s) %s" % [_role, text])


func _key(key: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	ev.keycode = key
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _game() -> Game:
	return get_tree().current_scene as Game


func _until(cond: Callable) -> bool:
	var t := 0.0
	while not cond.call():
		if t > TIMEOUT:
			return false
		await get_tree().create_timer(0.2).timeout
		t += 0.2
	return true


func _fail(why: String) -> bool:
	printerr("net check (%s): %s" % [_role, why])
	return false


static func _random_device_id() -> String:
	var hex := Crypto.new().generate_random_bytes(16).hex_encode()
	return "%s-%s-%s-%s-%s" % [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20, 12)]

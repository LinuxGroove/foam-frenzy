class_name Game
extends Node3D
## One match: the arena, every camper, the darts, the HUD, and every match
## message between the host and the players' devices.
##
## The same scene runs on every device. On the host it also owns a MatchHost,
## which decides everything; elsewhere it only shows what the host sends.
## All match RPCs live on this node (/root/Game) so their paths match.

signal status_changed
signal match_event(kind: int, a: int, b: int)
signal game_over(result: Dictionary)

const MUSIC := ["res://assets/kenney/audio/music/alpha_dance.ogg",
	"res://assets/kenney/audio/music/drumming_sticks.ogg",
	"res://assets/kenney/audio/music/mission_plausible.ogg"]
const VOICE := "res://assets/kenney/audio/voice/%s.ogg"
const SFX_PICKUP := ["res://assets/kenney/audio/sfx/pickup1.ogg", "res://assets/kenney/audio/sfx/pickup2.ogg"]
const SFX_RESPAWN := "res://assets/kenney/audio/sfx/powerUp2.ogg"
const SFX_OUT := "res://assets/kenney/audio/sfx/impactSoft_heavy_000.ogg"

## Set by Session before the scene enters the tree.
var config := {}
var my_peer := 1
var grid: ArenaGrid
var arena: ArenaView
var host: MatchHost
var camera: PartyCamera
var hud: Hud
var darts: DartField

## actor id -> {name, look, slot, team, blaster, bot, peer, seat}
var roster := {}
var views := {}
var locals := {}
var flag_views: Array[FlagView] = []
var settings := {}
var mode := Rules.Mode.FFA
var practice := false
var phase := Rules.Phase.LOADING
var countdown := 0.0
var clock := -1.0
var scores := {}
var team_scores := [0, 0]
var overtime := false
## The host's match clock; doors run on it.
var match_time := 0.0
var result := {}
var flags_state := []
## actor id -> {"tags", "outs"}, counted from the tag events every device sees.
var tally := {}

var _last_count := -1


func _ready() -> void:
	name = "Game"
	my_peer = multiplayer.get_unique_id()
	settings = Rules.DEFAULT_SETTINGS.duplicate()
	settings.merge(config.get("settings", {}), true)
	mode = int(settings.mode)
	practice = bool(config.get("practice", false))
	grid = ArenaGrid.make(str(settings.arena))
	arena = ArenaView.new()
	add_child(arena)
	arena.build(grid, mode == Rules.Mode.CTF)
	darts = DartField.new()
	add_child(darts)
	darts.setup(grid, _listener)
	var players: Dictionary = config.get("players", {})
	var teams := Rules.assign_teams(players.keys(), mode)
	for id in players:
		var p: Dictionary = players[id].duplicate()
		p["team"] = int(teams[id])
		roster[id] = p
	camera = PartyCamera.new()
	add_child(camera)
	camera.arena_size = grid.world_size()
	camera.snap_to(Vector3(grid.world_size().x * 0.5, 0, grid.world_size().y * 0.5), 30.0)
	for id in roster:
		_make_view(id)
	if mode == Rules.Mode.CTF:
		for team in 2:
			var f := FlagView.new()
			add_child(f)
			f.setup(team)
			f.apply(0, grid.bases[team])
			flag_views.append(f)
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	var seats := locals.keys()
	seats.sort_custom(func(a, b): return locals[a].seat.index < locals[b].seat.index)
	for id in seats:
		hud.add_seat_card(locals[id], actor_color(id))
	if Session.is_host():
		host = MatchHost.new()
		host.name = "Host"
		add_child(host)
		host.setup(config, self)
		host.ended.connect(Session.report_match)
	Session.left.connect(_on_session_left)
	LGAudio.play_music(MUSIC[int(config.get("seed", 0)) % MUSIC.size()], -8.0)
	Session.report_loaded()


func _make_view(id: int) -> void:
	var p: Dictionary = roster[id]
	var local: bool = not bool(p.get("bot", false)) and int(p.get("peer", 0)) == my_peer
	var v := CamperView.new()
	add_child(v)
	v.setup(id, str(p.name), int(p.look), actor_color(id), int(p.team), int(p.get("blaster", 0)), local, mode == Rules.Mode.HOARDER)
	views[id] = v
	if local:
		var lc := LocalCamper.new()
		lc.name = "Local%d" % int(p.get("seat", 0))
		add_child(lc)
		lc.setup(self, id, Session.seat_input(int(p.get("seat", 0))), v, int(p.get("slot", 0)), int(p.get("blaster", 0)))
		locals[id] = lc


func _on_session_left(reason: String) -> void:
	LGScenes.change_scene("res://game/ui/title.tscn", func(node): node.set("message", reason))


## Stops this match from following the session, before starting a new one
## from inside the match (the practice round's "Play with bots").
func detach_session() -> void:
	if Session.left.is_connected(_on_session_left):
		Session.left.disconnect(_on_session_left)


## Host (MatchHost asks): true once every player's device has the arena up,
## so nobody misses the countdown.
func everyone_loaded() -> bool:
	var connected := multiplayer.get_peers()
	for id in roster:
		var p: Dictionary = roster[id]
		if bool(p.get("bot", false)):
			continue
		var peer := int(p.get("peer", 0))
		if peer != my_peer and peer in connected and not Session.loaded_peers.has(peer):
			return false
	return true


## Host: a player's device dropped out mid-match (from Session).
func on_player_left(peer: int) -> void:
	if host:
		host.on_player_left(peer)


func _process(delta: float) -> void:
	if phase == Rules.Phase.PLAY:
		match_time += delta
	arena.update_doors(match_time, phase == Rules.Phase.PLAY)
	var pts: Array[Vector3] = []
	var lead := Vector3.ZERO
	for id in locals:
		var lc: LocalCamper = locals[id]
		if lc.placed:
			pts.append(Vector3(lc.pos.x, 0, lc.pos.y))
			lead = Vector3(lc.aim.x, 0, lc.aim.y) * 2.5
	camera.points = pts
	camera.lead = lead
	if phase == Rules.Phase.COUNTDOWN:
		var n := int(ceil(countdown))
		if n != _last_count and n > 0 and n <= 3:
			_last_count = n
			_voice(str(n))


# --- Helpers for the HUD and local campers --------------------------------

func actor_name(id: int) -> String:
	return str(roster.get(id, {}).get("name", "?"))


func actor_team(id: int) -> int:
	return int(roster.get(id, {}).get("team", -1))


## Team colour in team modes, the player's own colour otherwise.
func actor_color(id: int) -> Color:
	var team := actor_team(id)
	if team >= 0 and Rules.is_team_mode(mode):
		return GameConfig.TEAM_COLORS[team]
	return GameConfig.slot_color(int(roster.get(id, {}).get("slot", 0)))


func is_local(id: int) -> bool:
	return locals.has(id)


## Nudges a stick aim towards the nearest opponent in a narrow cone.
func assisted_aim(id: int, from: Vector2, dir: Vector2, level: int) -> Vector2:
	var cone := deg_to_rad(9.0 if level == 1 else 18.0)
	var strength := 0.55 if level == 1 else 0.85
	var team := actor_team(id)
	var best := Vector2.ZERO
	var best_angle := cone
	var range_m := float(Rules.blaster(int(roster.get(id, {}).get("blaster", 0))).range)
	for oid in views:
		var v: CamperView = views[oid]
		if oid == id or not v.alive or (team >= 0 and actor_team(oid) == team and Rules.is_team_mode(mode)):
			continue
		var to := Vector2(v.position.x, v.position.z) - from
		if to.length() > range_m:
			continue
		var angle := absf(dir.angle_to(to))
		if angle < best_angle and grid.clear_line(from, from + to, match_time):
			best_angle = angle
			best = to.normalized()
	if best == Vector2.ZERO:
		return dir
	return dir.slerp(best, strength).normalized()


func _listener() -> Vector3:
	return Vector3(camera.position.x, 0, camera.position.z - 8.0) if camera else Vector3.ZERO


func _voice(line: String, volume := -2.0) -> void:
	LGAudio.play_sfx(VOICE % line, volume)


# --- Sending --------------------------------------------------------------

## Host: sends a match message to one device (calls locally for the host's
## own device; skips devices that haven't loaded the arena yet).
func send(peer: int, method: String, args: Array) -> void:
	if peer <= 0:
		return
	if peer == my_peer:
		callv(method, args)
		return
	if not Session.loaded_peers.has(peer) or not peer in multiplayer.get_peers():
		return
	var call_args := [peer, method]
	call_args.append_array(args)
	callv("rpc_id", call_args)


## Host: sends a match message to every device in the match.
func broadcast(method: String, args: Array) -> void:
	var peers := {my_peer: true}
	for id in roster:
		var p: Dictionary = roster[id]
		if not bool(p.get("bot", false)):
			peers[int(p.get("peer", 0))] = true
	for peer in peers:
		send(peer, method, args)


func to_host(method: String, args: Array) -> void:
	if Session.is_host():
		callv(method, args)
	elif 1 in multiplayer.get_peers():
		var call_args := [1, method]
		call_args.append_array(args)
		callv("rpc_id", call_args)


func _sender() -> int:
	var s := multiplayer.get_remote_sender_id()
	return my_peer if s == 0 else s


# --- Player -> host ---------------------------------------------------------

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _c_state(id: int, pos: Vector2, yaw: float, moving: bool) -> void:
	if host:
		host.on_state(_sender(), id, pos, yaw, moving)


@rpc("any_peer", "call_remote", "reliable")
func _c_fire(id: int, origin: Vector2, yaw: float) -> void:
	if host:
		host.on_fire(_sender(), id, origin, yaw)


@rpc("any_peer", "call_remote", "reliable")
func _c_dive(id: int) -> void:
	if host:
		host.on_dive(_sender(), id)


@rpc("any_peer", "call_remote", "reliable")
func _c_taunt(id: int) -> void:
	if host:
		host.on_taunt(_sender(), id)


# --- Host -> players --------------------------------------------------------

@rpc("authority", "call_remote", "unreliable_ordered", 1)
func _h_snapshot(time: float, actors: Array, p_flags: Array) -> void:
	if phase == Rules.Phase.ENDED:
		return
	# Keep the door clock close to the host's.
	if absf(time - match_time) > 0.25:
		match_time = time
	for e in actors:
		var id := int(e[0])
		var v: CamperView = views.get(id)
		if v == null:
			continue
		v.apply(e)
		if locals.has(id):
			locals[id].apply(e)
		var carrying := int(e[4]) & MatchHost.F_FLAG != 0
		v.set_carrying(1 - actor_team(id) if carrying and actor_team(id) >= 0 else -1)
	flags_state = p_flags
	for i in mini(p_flags.size(), flag_views.size()):
		flag_views[i].apply(int(p_flags[i][0]), Vector2(p_flags[i][1], p_flags[i][2]))


@rpc("authority", "call_remote", "reliable")
func _h_status(p_phase: int, p_countdown: float, p_clock: float, p_scores: Dictionary, p_team_scores: Array, p_overtime: bool) -> void:
	var was := phase
	phase = p_phase
	countdown = p_countdown
	clock = p_clock
	scores = p_scores
	team_scores = p_team_scores
	if p_overtime and not overtime:
		_voice("suddenDeath")
	overtime = p_overtime
	if was != Rules.Phase.PLAY and phase == Rules.Phase.PLAY:
		_voice("go")
		hud.announce("GO!", Color("7ee36b"))
	status_changed.emit()


@rpc("authority", "call_remote", "reliable")
func _h_darts(list: Array) -> void:
	darts.fired(list, match_time)
	for e in list:
		var v: CamperView = views.get(int(e[1]))
		if v and not locals.has(int(e[1])):
			v.show_fire()


@rpc("authority", "call_remote", "reliable")
func _h_dart_ends(list: Array) -> void:
	darts.landed(list)
	for e in list:
		var victim := int(e[3])
		if locals.has(victim):
			camera.shake(0.25)
			hud.flash_hit(locals[victim].seat.index)


@rpc("authority", "call_remote", "reliable")
func _h_pickups(added: Array, removed: Array) -> void:
	darts.pickups_changed(added, removed)
	for e in removed:
		if locals.has(int(e[1])):
			LGAudio.play_sfx(SFX_PICKUP[randi() % SFX_PICKUP.size()], -12.0, 0.15)


@rpc("authority", "call_remote", "reliable")
func _h_respawn(id: int, pos: Vector2, yaw: float) -> void:
	if locals.has(id):
		locals[id].place(pos, yaw)
		if phase == Rules.Phase.PLAY:
			LGAudio.play_sfx(SFX_RESPAWN, -10.0)
	var v: CamperView = views.get(id)
	if v:
		darts.puff(Vector3(pos.x, 0.4, pos.y), actor_color(id))


@rpc("authority", "call_remote", "reliable")
func _h_correct(id: int, pos: Vector2) -> void:
	if locals.has(id):
		locals[id].pos = pos


@rpc("authority", "call_remote", "reliable")
func _h_event(kind: int, a: int, b: int) -> void:
	match kind:
		MatchHost.Ev.TAG:
			_count(b, "outs")
			if a != 0 and a != b:
				_count(a, "tags")
			var v: CamperView = views.get(b)
			if v:
				v.show_out()
				darts.puff(v.position + Vector3(0, 0.8, 0), actor_color(b))
			LGAudio.play_sfx(SFX_OUT, -4.0, 0.1)
			if locals.has(b):
				camera.shake(0.6)
		MatchHost.Ev.CAPTURE:
			_voice("captured" if _mine(a) else "enemyCaptured")
		MatchHost.Ev.FLAG_TAKEN:
			LGAudio.play_sfx("res://assets/kenney/audio/sfx/twoTone1.ogg", -6.0)
		MatchHost.Ev.FLAG_RETURNED:
			LGAudio.play_sfx("res://assets/kenney/audio/sfx/confirmation_001.ogg", -8.0)
	match_event.emit(kind, a, b)


@rpc("authority", "call_remote", "reliable")
func _h_game_over(res: Dictionary) -> void:
	phase = Rules.Phase.ENDED
	result = res
	darts.flying.clear()
	LGAudio.stop_music()
	var won := false
	if not res.get("tie", false):
		for id in locals:
			if int(res.winner) == id or (int(res.team) >= 0 and actor_team(id) == int(res.team)):
				won = true
	if res.get("tie", false):
		_voice("itsATie")
	else:
		_voice("youWin" if won else ("victory" if locals.is_empty() else "gameOver"))
	LGAudio.play_sfx("res://assets/kenney/audio/jingles/%s.ogg" % ("win" if won else "lose"), -4.0)
	game_over.emit(res)


func _count(id: int, key: String) -> void:
	if not tally.has(id):
		tally[id] = {"tags": 0, "outs": 0}
	tally[id][key] += 1


## True if `id` is on the same side as one of this device's players.
func _mine(id: int) -> bool:
	for lid in locals:
		if lid == id or (actor_team(lid) >= 0 and actor_team(lid) == actor_team(id)):
			return true
	return false

extends Node
## Headless tests: run with
##   godot --headless --path . tests/run_tests.tscn
## Add `-- --games=N` to play N bot matches per mode and arena (default 1).
## Exits non-zero on failure.

var failures := 0
var checks := 0


func _ready() -> void:
	var games := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--games="):
			games = maxi(1, arg.substr(8).to_int())
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGTheme.apply(get_tree().root)
	LGInput.register_actions(GameConfig.ACTIONS)
	LGInput.extend_ui_actions()
	LGSettings.set_value("player", "name", "Tester", false)
	LGSettings.set_value("tutorial", "howto_seen", true, false)
	printerr("- _test_join_codes")
	_test_join_codes()
	printerr("- _test_rules")
	_test_rules()
	printerr("- _test_arenas")
	_test_arenas()
	printerr("- _test_host_rules")
	_test_host_rules()
	printerr("- _test_loading_wait")
	_test_loading_wait()
	printerr("- _test_seats")
	await _test_seats()
	printerr("- _test_scene_switcher")
	await _test_scene_switcher()
	printerr("- _test_screen_fit")
	await _test_screen_fit()
	printerr("- _test_option_rows")
	await _test_option_rows()
	printerr("- _test_couch_lobby")
	await _test_couch_lobby()
	printerr("- _test_tutorial_ui")
	await _test_tutorial_ui()
	printerr("- _test_title_menu")
	await _test_title_menu()
	printerr("- _test_leaderboard_panel")
	_test_leaderboard_panel()
	printerr("- _test_version")
	_test_version()
	printerr("- _test_network_check")
	_test_network_check()
	printerr("- _test_offline_menus")
	await _test_offline_menus()
	printerr("- _test_name_maker")
	_test_name_maker()
	printerr("- _test_quick_match_bots")
	await _test_quick_match_bots()
	printerr("- _test_match_scene")
	await _test_match_scene()
	printerr("- _test_practice")
	await _test_practice()
	printerr("- _test_bot_matches")
	_test_bot_matches(games)
	print("\n%d checks, %d failed" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", what)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _press(action: String) -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		Input.parse_input_event(ev)
		Input.flush_buffered_events()
		await get_tree().process_frame


# --- Pure rules --------------------------------------------------------------

func _test_join_codes() -> void:
	for case in [["192.168.1.23", 24680], ["10.0.0.5", 24680], ["172.16.4.200", 31000]]:
		var code := JoinCode.encode(case[0], case[1], 24680)
		var back := JoinCode.decode(JoinCode.pretty(code).to_lower(), 24680)
		check(back.get("ip") == case[0] and back.get("port") == case[1], "join code round trip %s" % [case])
	check(JoinCode.decode("not a code!", 24680).is_empty(), "bad join code is rejected")
	for case in [["192.168.0.1", 24680], ["8.8.8.8", 40000]]:
		var code := JoinCode.encode(case[0], case[1], 24680)
		for pair in [["0", "O"], ["1", "I"], ["2", "Z"], ["5", "S"], ["8", "B"]]:
			code = code.replace(pair[0], pair[1])
		var back := JoinCode.decode(code, 24680)
		check(back.get("ip") == case[0] and back.get("port") == case[1], "a code typed with look-alike letters still works %s" % [case])


func _test_rules() -> void:
	check(Rules.target_score({"mode": Rules.Mode.FFA}) == 15, "free-for-all plays to 15 tags")
	check(Rules.target_score({"mode": Rules.Mode.CTF}) == 3, "capture the flag plays to 3")
	check(Rules.target_score({"mode": Rules.Mode.HOARDER}) == 0, "dart hoarder plays to the buzzer")
	check(Rules.target_score({"mode": Rules.Mode.TEAMS, "target": 7}) == 7, "a set score to win overrides the usual")
	var teams := Rules.assign_teams([12, -1, 4, -2, 5, -3], Rules.Mode.TEAMS)
	var count := [0, 0]
	for id in teams:
		count[teams[id]] += 1
	check(count == [3, 3], "teams are balanced (%s)" % [count])
	check(Rules.assign_teams([4, 5], Rules.Mode.FFA).values() == [-1, -1], "nobody has a team in free-for-all")
	check(Rules.assign_teams([5, 4, -1], Rules.Mode.CTF) == Rules.assign_teams([-1, 4, 5], Rules.Mode.CTF), "every device deals the same teams")
	var rng := RandomNumberGenerator.new()
	for i in Rules.BLASTERS.size():
		var b := Rules.blaster(i)
		var yaws := Rules.dart_yaws(b, 0.0, rng)
		check(yaws.size() == int(b.darts), "%s fires %d darts a shot" % [b.name, b.darts])
		for y in yaws:
			check(absf(y) <= deg_to_rad(float(b.spread)) * 0.5 + 0.05, "%s darts stay in the spread" % b.name)
	var w := Rules.winner(Rules.Mode.FFA, {4: 3, 5: 3, -1: 1}, {}, [0, 0])
	check(w.tie and w.winner == -1, "equal top scores are a tie")
	w = Rules.winner(Rules.Mode.TEAMS, {}, {}, [5, 2])
	check(not w.tie and w.team == 0, "the team with more tags wins")
	var medals := Rules.medals(Rules.Mode.FFA, {
		4: {"tags": 5, "outs": 1, "shots": 20, "hits": 4, "pickups": 9},
		5: {"tags": 1, "outs": 4, "shots": 10, "hits": 6, "pickups": 2},
	})
	var by_key := {}
	for m in medals:
		by_key[m.key] = m.id
	check(by_key.get("tagger") == 4 and by_key.get("sharp") == 5 and by_key.get("magnet") == 4 and by_key.get("untouchable") == 4,
		"medals go to the right players (%s)" % [by_key])
	check(not by_key.has("runner") and not by_key.has("hoarder"), "mode medals only in their modes")


func _test_arenas() -> void:
	for id in ArenaGrid.ARENA_IDS:
		var g := ArenaGrid.make(id)
		check(g.rows.size() == 15 and g.width == 22, "%s is 22 by 15 tiles" % id)
		var mirrored := true
		for row in g.rows:
			for x in g.width / 2:
				var a := row[x]
				var b := row[g.width - 1 - x]
				if ArenaGrid.MIRROR.get(a, a) != b:
					mirrored = false
		check(mirrored, "%s is the same on both sides" % id)
		check(g.spawns.size() == 8, "%s has 8 spawn points" % id)
		check(g.bases.size() == 2 and not g.blocked(g.bases[0], 0.4, 0.0) and not g.blocked(g.bases[1], 0.4, 0.0), "%s bases are on open floor" % id)
		var from: Vector2 = g.spawns["1"]
		var reachable := true
		for key in g.spawns:
			if g.path(from, g.spawns[key]).is_empty() and from.distance_to(g.spawns[key]) > 0.1:
				reachable = false
		check(reachable, "every spawn in %s can be reached from every other" % id)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var inside := 0
		for i in 400:
			var p := g.random_floor(rng)
			for step in 30:
				p = g.move(p, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.1, 1.5), Rules.CAMPER_RADIUS, float(i))
			if g.blocked(p, Rules.CAMPER_RADIUS * 0.9, float(i)):
				inside += 1
		check(inside == 0, "moving never ends up inside a wall in %s (%d did)" % [id, inside])
		var size := g.world_size()
		var hit := g.raycast(Vector2(3, size.y * 0.5), Vector2(-20, size.y * 0.5), 0.0)
		check(hit.hit and hit.point.x >= 1.9, "a dart stops at the outer wall in %s" % id)
	var lab := ArenaGrid.make("lab")
	check(lab.doors.size() >= 2, "the lab has doors")
	var open_and_shut := false
	for t in range(0, 15):
		if lab.door_closed(0, float(t)) != lab.door_closed(0, 0.0):
			open_and_shut = true
	check(open_and_shut, "lab doors open and shut over time")


func _new_host(players: Dictionary, settings: Dictionary, seed := 5) -> MatchHost:
	var host := MatchHost.new()
	host.auto_step = false
	host.setup({"seed": seed, "players": players, "settings": settings}, NetStub.new())
	return host


func _test_host_rules() -> void:
	var players := {
		4: {"name": "Ann", "look": 0, "slot": 0, "bot": false, "peer": 1, "seat": 0, "blaster": 0},
		5: {"name": "Ben", "look": 1, "slot": 1, "bot": false, "peer": 1, "seat": 1, "blaster": 0},
		8: {"name": "Cy", "look": 2, "slot": 2, "bot": false, "peer": 2, "seat": 0, "blaster": 0},
	}
	var host := _new_host(players, {"mode": Rules.Mode.FFA, "arena": "gym"})
	for i in 300:
		host.step(1.0 / 60.0)
	check(host.phase == Rules.Phase.PLAY, "the match starts after the countdown")
	var a: Dictionary = host.actors[4]
	var start: Vector2 = a.pos
	host.on_state(2, 4, start + Vector2(0.3, 0), 0.0, true)
	check(a.pos == start, "a device can't move someone else's camper")
	var net: NetStub = host.net
	net.sent.erase("_h_correct")
	host.on_state(1, 4, start + Vector2(15, 0), 0.0, true)
	check(a.pos == start and net.sent.has("_h_correct"), "a camper reported too far away is pulled back")
	a.ammo = 0
	var darts_before := host.darts.size()
	host.on_fire(1, 4, a.pos, 0.0)
	check(host.darts.size() == darts_before, "no darts, no shot")
	# A dart fired point blank at a shielded camper doesn't count.
	var b: Dictionary = host.actors[8]
	a.ammo = 5
	a.fire_cd = 0.0
	a.shield = 0.0
	b.pos = host.grid.move(a.pos, Vector2(0, 2.0), Rules.CAMPER_RADIUS, host.time)
	b.shield = 5.0
	b.dive = 0.0
	var hp := int(b.hp)
	a.yaw = Rules.dir_yaw(b.pos - a.pos)
	host.try_fire(4)
	for i in 30:
		host.step(1.0 / 60.0)
		b.shield = 5.0
	check(int(b.hp) == hp, "a just-respawned camper can't be tagged")
	# Teams without friendly fire: a teammate's darts pass by.
	var team_players := {
		4: players[4], 5: players[5],
		-1: {"name": "Bot", "look": 3, "slot": 3, "bot": true, "peer": 0, "seat": 0, "blaster": 0},
		-2: {"name": "Bot2", "look": 4, "slot": 4, "bot": true, "peer": 0, "seat": 0, "blaster": 0},
	}
	host = _new_host(team_players, {"mode": Rules.Mode.TEAMS, "arena": "gym", "friendly_fire": false})
	for i in 240:
		host.step(1.0 / 60.0)
	var mates := []
	for id in host.actors:
		if host.actors[id].team == host.actors[4].team and id != 4:
			mates.append(id)
	if not mates.is_empty():
		var shooter: Dictionary = host.actors[4]
		var mate: Dictionary = host.actors[mates[0]]
		host._bots.erase(mates[0])
		mate.shield = 0.0
		mate.pos = host.grid.move(shooter.pos, Vector2(0, 1.6), Rules.CAMPER_RADIUS, host.time)
		shooter.yaw = Rules.dir_yaw(mate.pos - shooter.pos)
		shooter.ammo = 5
		shooter.fire_cd = 0.0
		var mate_hp := int(mate.hp)
		host.try_fire(4)
		for i in 20:
			host.step(1.0 / 60.0)
		check(int(mate.hp) == mate_hp, "teammates' darts don't tag without friendly fire")
	# A player's device dropping out takes their campers out of the arena.
	host.on_player_left(1)
	check(host.actors[4].out and host.actors[5].out, "a dropped device's campers leave the match")


class SlowNet extends NetStub:
	var ready := false

	func everyone_loaded() -> bool:
		return ready


func _test_loading_wait() -> void:
	var host := MatchHost.new()
	host.auto_step = false
	var net := SlowNet.new()
	host.setup({"seed": 1, "players": {-1: {"name": "A", "look": 0, "bot": true}, -2: {"name": "B", "look": 1, "bot": true}},
		"settings": {"mode": 0, "arena": "gym"}}, net)
	for i in 120:
		host.step(1.0 / 60.0)
	check(host.phase == Rules.Phase.LOADING, "the countdown waits for every device to load the arena")
	net.ready = true
	host.step(1.0 / 60.0)
	check(host.phase == Rules.Phase.COUNTDOWN, "the countdown starts once everyone has loaded")
	host = MatchHost.new()
	host.auto_step = false
	host.setup({"seed": 1, "players": {-1: {"name": "A", "look": 0, "bot": true}}, "settings": {}}, SlowNet.new())
	for i in int(MatchHost.LOAD_TIMEOUT * 60.0) + 2:
		host.step(1.0 / 60.0)
	check(host.phase != Rules.Phase.LOADING, "a device that never loads doesn't hold up the match forever")


# --- Couch seats ----------------------------------------------------------------

func _test_seats() -> void:
	Session.start_solo(2)
	check(Session.players.has(Session.actor_id(1, 0)), "the first player sits at seat 0")
	var seat := Session.add_local_seat(7)
	check(seat == 1 and Session.players.has(Session.actor_id(1, 1)), "a controller adds a couch player")
	check(LGInput.claimed_pads.get(7) == 1, "the couch player's controller is claimed")
	check(Session.add_local_seat(7) == -1, "a controller can't join twice")
	check(Session.seat_input(1).device == 7 and not Session.seat_input(1).keyboard, "a couch player reads only their controller")
	check(Session.seat_input(0).keyboard, "the first player has the keyboard and mouse")
	Session.add_local_seat(8)
	Session.add_local_seat(9)
	check(Session.add_local_seat(10) == -1, "at most %d players share one screen" % GameConfig.MAX_LOCAL)
	var slots := {}
	for p in Session.players.values():
		slots[int(p.slot)] = true
	check(slots.size() == Session.players.size(), "everyone has their own colour")
	Session.remove_local_seat(1)
	check(not LGInput.claimed_pads.has(7) and LGInput.claimed_pads.get(8) == 1, "seats move up when a couch player leaves")
	check(Session.players.size() == 2 + 3, "the roster follows the seats")
	# The keyboard belongs to seat 0 only.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	Input.flush_buffered_events()
	check(Session.seat_input(0).strength("move_up") > 0.9, "W moves the keyboard player")
	check(Session.seat_input(1).strength("move_up") == 0.0, "W doesn't move a couch player")
	var up := key.duplicate() as InputEventKey
	up.pressed = false
	Input.parse_input_event(up)
	Input.flush_buffered_events()
	for i in range(Session.local_seats.size() - 1, 0, -1):
		Session.remove_local_seat(i)
	Session.leave()
	await _frames(2)


# --- Scenes and menus ---------------------------------------------------------

## A burst of scene changes must leave exactly one scene, the last one asked for.
func _test_scene_switcher() -> void:
	var tree := get_tree()
	await tree.process_frame
	var placeholder := Node.new()
	placeholder.name = "Placeholder"
	tree.root.add_child(placeholder)
	tree.current_scene = placeholder
	var made := []
	for n in ["SceneA", "SceneB", "SceneC"]:
		var node := Node.new()
		node.name = n
		var packed := PackedScene.new()
		packed.pack(node)
		node.free()
		made.append(packed)
	LGScenes.change_scene(made[0])
	LGScenes.change_scene(made[1])
	LGScenes.change_scene(made[2])
	await _wait_scene(placeholder)
	var found := []
	for c in tree.root.get_children():
		if str(c.name).begins_with("Scene") or c.name == "Placeholder":
			found.append(str(c.name))
	check(found == ["SceneC"], "a burst of scene changes leaves only the last scene (got %s)" % [found])
	for c in tree.root.get_children():
		if str(c.name).begins_with("Scene"):
			c.free()
	tree.current_scene = self


func _wait_scene(old: Node) -> void:
	var waited := 0
	while (LGScenes.is_busy() or get_tree().current_scene == old) and waited < 600:
		await get_tree().process_frame
		waited += 1
	await get_tree().process_frame


## A menu taller than the screen shrinks to fit and stays centred.
func _test_screen_fit() -> void:
	check(is_equal_approx(LGScreenFit.scale_for(Vector2(400, 400), Vector2(800, 800)), 1.0), "a menu that fits isn't scaled")
	check(is_equal_approx(LGScreenFit.scale_for(Vector2(400, 1600), Vector2(800, 800)), 0.5), "a tall menu shrinks to fit")
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	var col := LGUi.centered_column(ui, 400)
	LGScreenFit.center(col)
	for i in 14:
		col.add_child(LGUi.button("Button %d" % i, func(): pass))
	await _frames(4)
	var view := get_viewport().get_visible_rect()
	var xf := col.get_global_transform()
	var top := xf * Vector2.ZERO
	var bottom := xf * col.size
	check(top.y >= -1.0 and bottom.y <= view.size.y + 1.0, "every button of a tall menu is on screen (%s to %s in %s)" % [top, bottom, view.size])
	check(absf((top.y + bottom.y) * 0.5 - view.size.y * 0.5) < 4.0, "a shrunk menu stays centred")
	col.get_child(0).queue_free()
	await _frames(1)
	check(col.get_children().all(func(c): return c is Control), "the fitter isn't one of the menu's buttons")
	layer.queue_free()
	await _frames(1)


## Option rows by controller: left and right move between panels until A is
## pressed on a row; then they change its value, and A again finishes.
func _test_option_rows() -> void:
	Session.start_solo(3)
	var lobby: Node = (load("res://game/ui/lobby.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lobby)
	await _frames(3)
	var row: LGCycler = lobby._cyclers["mode"]
	var before: Variant = row.value()
	row.grab_focus()
	await _frames(1)
	await _press("ui_left")
	var owner := get_viewport().gui_get_focus_owner()
	check(row.value() == before, "left on a row that isn't being edited keeps its value")
	check(owner != null and owner != row and owner.get_global_rect().position.x < row.get_global_rect().position.x,
		"left on a match rule moves focus to the left panel (focus on %s)" % [owner])
	row.grab_focus()
	await _frames(1)
	await _press("ui_accept")
	check(row.editing, "A starts editing a row")
	await _press("ui_right")
	check(row.value() != before and Session.settings.mode == row.value(), "right while editing changes the value")
	await _press("ui_accept")
	check(not row.editing, "A again finishes editing")
	Session.set_setting("mode", Rules.Mode.FFA)
	lobby.free()
	Session.leave()
	check(not LGScenes.is_busy(), "a freed lobby doesn't react when the session ends")


func _test_couch_lobby() -> void:
	Session.start_solo(2)
	var lobby: Node = (load("res://game/ui/lobby.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(lobby)
	await _frames(2)
	check(LGInput.filter_claimed_pads, "in the lobby, couch players' controllers don't drive the menus")
	Session.add_local_seat(11)
	await _frames(2)
	check(lobby._cards.size() == 1 and lobby._seat_box.visible, "a couch player gets a card in the lobby")
	Session.set_seat_value(1, "blaster", 2)
	await _frames(1)
	check("Foam Cannon" in lobby._cards[1]._what.text, "the card shows the couch player's blaster")
	Session.remove_local_seat(1)
	await _frames(2)
	check(lobby._cards.is_empty(), "the card goes when the couch player leaves")
	lobby.free()
	check(not LGInput.filter_claimed_pads, "leaving the lobby lets every controller drive menus again")
	Session.leave()


func _button_texts(title: Node) -> Array:
	return title._col.get_children().filter(func(c): return c is Button).map(func(b): return b.text)


## The title menu keeps local play and the tutorial on their own screens.
func _test_title_menu() -> void:
	LGSettings.set_value("tutorial", "welcomed", true, false)
	var title: Node = load("res://game/ui/title.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	var main := _button_texts(title)
	for t in ["Play with bots", "Local network play", "Play online", "How to play"]:
		check(t in main, "title menu has %s" % t)
	for t in ["Practice round", "Host on this network", "Join on this network"]:
		check(not t in main, "%s moved off the title menu" % t)
	title._show_howto_menu()
	check(_button_texts(title) == ["Tutorial", "Practice round", "Back"], "how to play holds the tutorial and practice")
	await get_tree().process_frame
	title._show_local()
	check(_button_texts(title) == ["Host on this network", "Join on this network", "Back"], "local network play holds host and join")
	await get_tree().process_frame
	var online_was: bool = LGSettings.get_value("online", "enabled")
	LGSettings.set_value("online", "enabled", true, false)
	title._show_online()
	check("Leaderboards" in _button_texts(title), "play online offers leaderboards")
	LGSettings.set_value("online", "enabled", online_was, false)
	# Let the menu's deferred focus land before freeing it.
	await get_tree().process_frame
	title.queue_free()
	await get_tree().process_frame


## Versions: YYYY.WW.MINOR, plus +commits.ghash between releases. A run from
## source asks tools/version.sh, so it reports the commit it was built from.
func _test_version() -> void:
	for v in ["2026.41.0", "2026.41.12", "2026.41.0+3.g1a2b3c4d", "0.1.0"]:
		check(LGVersion.is_valid(v), "%s is a valid version" % v)
	for v in ["v2026.41.0", "2026.41", "2026.41.0-3-g1a2b3c4d", "", "2026.41.0+" + "x".repeat(30)]:
		check(not LGVersion.is_valid(v), "%s is not a valid version" % v)
	var v := GameConfig.version()
	check(LGVersion.is_valid(v), "this run's version %s is valid" % v)
	var out := []
	OS.execute("sh", [ProjectSettings.globalize_path("res://tools/version.sh")], out)
	check(not out.is_empty() and str(out[0]).strip_edges() == v, "a run from source reports tools/version.sh's version")


## The network check ignores loopback, link-local and container bridges.
func _test_network_check() -> void:
	var iface := func(name: String, addrs: Array) -> Dictionary: return {"name": name, "addresses": addrs}
	check(not LGNetwork.is_up_in([]), "no interfaces: offline")
	check(not LGNetwork.is_up_in([iface.call("lo", ["127.0.0.1", "::1"])]), "loopback only: offline")
	check(not LGNetwork.is_up_in([iface.call("wlan0", ["169.254.3.4", "fe80::1"])]), "link-local only: offline")
	check(not LGNetwork.is_up_in([iface.call("lxdbr0", ["10.152.39.1"]), iface.call("docker0", ["172.17.0.1"])]), "container bridges only: offline")
	check(LGNetwork.is_up_in([iface.call("lo", ["127.0.0.1"]), iface.call("wlp1s0", ["192.168.1.220"])]), "Wi-Fi address: online")
	check(LGNetwork.is_up_in([iface.call("enp3s0", ["2001:db8::5"])]), "global IPv6 address: online")


## With no network the online and local screens say so and turn their
## buttons off, and come back on by themselves; sign-in doesn't even try.
func _test_offline_menus() -> void:
	LGNetwork.forced = false
	var t0 := Time.get_ticks_msec()
	var ok: bool = await LGOnline.connect_async("Tester", GameConfig.GAME_ID)
	check(not ok and LGOnline.last_error == LGNetwork.OFFLINE_TEXT, "sign-in refuses without a network")
	check(Time.get_ticks_msec() - t0 < 200, "and says so straight away")
	var online_was: bool = LGSettings.get_value("online", "enabled")
	LGSettings.set_value("online", "enabled", true, false)
	var title: Node = load("res://game/ui/title.tscn").instantiate()
	add_child(title)
	await get_tree().process_frame
	for screen in ["_show_online", "_show_local"]:
		title.call(screen)
		await get_tree().process_frame
		var buttons: Array = title._net_controls.filter(func(c): return c is BaseButton)
		check(buttons.size() >= 2 and buttons.all(func(b): return b.disabled), "%s: network buttons are off offline" % screen)
		check(title._net_label.visible and title._net_label.text.contains("not connected"), "%s: says there's no network" % screen)
		var back: Button = title._col.get_children().filter(func(c): return c is Button and c.text == "Back")[0]
		check(not back.disabled, "%s: Back still works" % screen)
		LGNetwork.forced = true
		title._apply_network(false)
		check(buttons.all(func(b): return not b.disabled) and not title._net_label.visible, "%s: buttons come back with the network" % screen)
		LGNetwork.forced = false
		await get_tree().process_frame
	LGNetwork.forced = null
	LGSettings.set_value("online", "enabled", online_was, false)
	await get_tree().process_frame
	title.queue_free()
	await get_tree().process_frame


## Bot names: player-like, unique, short enough for a name tag.
func _test_name_maker() -> void:
	var used := ["MossyOtter"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for i in 200:
		var n := LGNameMaker.make(used, rng)
		check(n.length() <= 16, "name %s fits in 16 letters" % n)
		check(not n.to_lower() in used.map(func(u): return u.to_lower()), "name %s is unique" % n)
		used.append(n)
	var a := RandomNumberGenerator.new()
	a.seed = 7
	var b := RandomNumberGenerator.new()
	b.seed = 7
	check(LGNameMaker.make([], a) == LGNameMaker.make([], b), "the same seed makes the same name")
	check(LGNameMaker.make(["Ab"], null, 16, ["A"], ["b"]).begins_with("Ab"), "taken names get a number")


## Quick match with nobody else around: you and a random number of named bots,
## and a countdown that only the host acts on.
func _test_quick_match_bots() -> void:
	Session.start_quick_solo()
	var size := Session.players.size()
	check(Session.quick and Session.mode == Session.Mode.SOLO, "quick match falls back to a solo game")
	check(size >= GameConfig.QUICK_MATCH_SIZE.x and size <= GameConfig.QUICK_MATCH_SIZE.y, "quick match has %d players" % size)
	var names: Array = Session.players.values().map(func(p): return p.name)
	var bots: Array = Session.players.values().filter(func(p): return p.bot)
	check(not bots.is_empty() and bots.size() == size - Session.local_seats.size(), "everyone else is a bot")
	check(bots.all(func(p): return not p.name in GameConfig.BOT_NAMES), "quick-match bots get made-up names")
	check(names.all(func(n): return names.count(n) == 1), "player names are unique")
	check(Session.can_start(), "a quick-match game can start")
	var left := Session.quick_seconds_left()
	check(left > Session.QUICK_COUNTDOWN - 1.0 and left <= Session.QUICK_COUNTDOWN, "the countdown is running (%.1f s)" % left)
	Session.leave()
	check(not Session.quick and Session.quick_seconds_left() == 0.0, "leaving ends quick match")
	# A guest learns the countdown from the host, but never acts on it.
	Session._h_countdown(5.0)
	check(Session.quick and Session.quick_seconds_left() > 4.0, "the host's countdown reaches a guest")
	Session._quick_start_msec = 1
	Session._process(0.0)
	check(not Session.in_match, "only the host starts the match")
	Session.leave()
	# Ordinary bots keep the game's own names.
	Session.start_solo(1)
	check(Session.players.values().filter(func(p): return p.bot)[0].name in GameConfig.BOT_NAMES, "bots outside quick match keep their usual names")
	Session.leave()
	await get_tree().process_frame


## Leaderboard rows: the top list, you highlighted, and your rank below it.
func _test_leaderboard_panel() -> void:
	var panel := LGLeaderboardPanel.new()
	panel.setup("foam-frenzy", "Tester", [["wins_weekly", "Wins this week"], ["wins", "Wins, all time"], ["tags", "Campers tagged"]])
	panel.build()
	panel.show_board({"top": [], "mine": null})
	check(panel._list.get_child_count() == 1 and panel._mine.text != "", "an empty board says so")
	var top := []
	for i in 10:
		top.append({"rank": i + 1, "name": "P%d" % i, "score": 20 - i, "me": false})
	panel.show_board({"top": top, "mine": {"rank": 14, "name": "Tester", "score": 3, "me": true}})
	check(panel._list.get_child_count() == 10, "ten rows on a full board")
	check(panel._mine.text.contains("#14"), "your rank shows when you're below the top ten")
	top[2].me = true
	panel.show_board({"top": top, "mine": top[2]})
	check(panel._mine.text == "", "no separate line when you're in the top ten")
	panel.free()
	# Your own record, above the boards.
	var title_script: Script = load("res://game/ui/title.gd")
	var rec := LGLeaderboardPanel.new()
	rec.setup("foam-frenzy", "Tester", [["wins", "All time"]], title_script.record_text)
	rec.build()
	check(rec._record.visible, "the record line shows when the game gives one")
	rec.show_record({})
	check(rec._record.text.begins_with("No online matches yet"), "a player with no online games is told how to start a record")
	rec.show_record({"matches": 1, "wins": 0, "tags": 31, "outs": 6, "captures": 2})
	check(rec._record.text == "Your online record: 1 match, 0 wins, 31 tags, 6 outs, 2 flag captures.", "the record reads: %s" % rec._record.text)
	rec.free()
	var plain := LGLeaderboardPanel.new()
	plain.setup("foam-frenzy", "Tester", [["wins", "All time"]])
	plain.build()
	check(not plain._record.visible, "no record line without a record function")
	plain.free()


func _test_tutorial_ui() -> void:
	var howto := HowToPanel.new()
	add_child(howto)
	var closed := [false]
	howto.closed.connect(func(): closed[0] = true)
	howto.open()
	await _frames(1)
	var pages := HowToPanel.pages().size()
	for i in pages:
		howto._go(1)
	check(closed[0] and not howto.visible, "how to play closes after the last page (%d pages)" % pages)
	check(bool(LGSettings.get_value("tutorial", "howto_seen")), "opening how to play is remembered")
	howto.queue_free()
	await _frames(1)


# --- A whole match on screen ----------------------------------------------------

func _start_scene_match(mode: int) -> Game:
	var old := get_tree().current_scene
	Session.start_solo(3)
	Session.set_setting("mode", mode)
	Session.start_match()
	await _wait_scene(old)
	return get_tree().current_scene as Game


func _test_match_scene() -> void:
	# The test runner stays alive while scenes come and go.
	get_tree().current_scene = null
	var game: Game = await _start_scene_match(Rules.Mode.CTF)
	check(game != null, "the match scene loads")
	if game == null:
		return
	var waited := 0
	while game.phase != Rules.Phase.PLAY and waited < 600:
		await get_tree().process_frame
		waited += 1
	check(game.phase == Rules.Phase.PLAY, "the countdown runs and the match starts")
	check(game.locals.size() == 1 and game.hud._seat_cards.size() == 1, "this device's player has a camper and a corner card")
	var lc: LocalCamper = game.locals.values()[0]
	check(lc.placed and lc.ammo == int(Rules.DEFAULT_SETTINGS.darts_per_life), "the camper is placed with a full load of darts")
	check(game.flag_views.size() == 2, "capture the flag shows both flags")
	lc.fire_cd = 0.0
	lc._fire()
	await _frames(3)
	check(game.host.actors[lc.id].stats.shots >= 1, "firing reaches the host")
	game.hud.open_pause()
	check(game.hud.pause.visible and get_tree().paused, "pause stops a match on this device alone")
	game.hud.pause.close()
	check(not get_tree().paused, "resume carries on")
	game.host._finish()
	await get_tree().create_timer(ResultsPanel.SHOW_AFTER + 0.3).timeout
	check(game.hud.results.visible, "the results come up when the match ends")
	check(game.hud.blocks_input(), "the results stop the campers moving")
	Session.return_to_lobby()
	await _wait_scene(game)
	check(get_tree().current_scene.name == "Lobby", "back to the lobby after a match")
	var lobby := get_tree().current_scene
	Session.leave()
	await _wait_scene(lobby)
	check(get_tree().current_scene.name == "Title", "leaving goes back to the title screen")
	var count := 0
	for c in get_tree().root.get_children():
		if c.name in ["Game", "Lobby", "Title"]:
			count += 1
	check(count == 1, "only one screen is up at a time")


## Plays the practice round the way a player would and checks the guide.
func _test_practice() -> void:
	var old := get_tree().current_scene
	Session.start_practice()
	await _wait_scene(old)
	var game := get_tree().current_scene as Game
	check(game != null and game.practice, "the practice round loads")
	if game == null:
		return
	check(game.roster.size() == 3, "practice is you and two coaches")
	var waited := 0
	while game.phase != Rules.Phase.PLAY and waited < 600:
		await get_tree().process_frame
		waited += 1
	var guide: PracticeGuide = game.hud.guide
	var lc: LocalCamper = game.locals.values()[0]
	check(guide._step == 0, "the guide starts on walking")
	for i in 30:
		lc.pos = game.grid.move(lc.pos, Vector2(0.5, 0) if (i / 8) % 2 == 0 else Vector2(-0.5, 0), Rules.CAMPER_RADIUS, 0.0)
		await get_tree().physics_frame
	await _frames(2)
	check(guide._step == 1, "walking moves the guide on to firing (walked %.1f)" % guide._walked)
	game.host.actors[lc.id].ammo = 10
	for i in 3:
		await get_tree().create_timer(0.4).timeout
		lc.fire_cd = 0.0
		lc._fire()
	await get_tree().create_timer(0.3).timeout
	check(guide._step == 2, "three shots move the guide on to picking up (shots %d)" % guide._shots)
	game.host.actors[lc.id].ammo += 1
	await get_tree().create_timer(0.3).timeout
	check(guide._step == 3, "picking up a dart moves the guide on to diving")
	for i in 2:
		lc.dive_t = 0.2
		await _frames(2)
		lc.dive_t = 0.0
		await _frames(2)
	check(guide._step == 4, "two dives move the guide on to tagging")
	var coach: int = game.roster.keys().filter(func(id): return id < 0)[0]
	game._h_event(MatchHost.Ev.TAG, lc.id, coach)
	game._h_event(MatchHost.Ev.TAG, lc.id, coach)
	await _frames(2)
	check(guide.blocking(), "tagging a coach out twice finishes the practice round")
	check(bool(LGSettings.get_value("tutorial", "practiced")), "finishing practice is remembered")
	Session.leave()
	await _wait_scene(game)
	LGSettings.set_value("tutorial", "practiced", false, false)


# --- Bot matches ---------------------------------------------------------------

func _test_bot_matches(games: int) -> void:
	for mode in Rules.MODE_NAMES.size():
		for arena in ArenaGrid.ARENA_IDS:
			var captures := 0
			for g in games:
				captures += _bot_match(mode, arena, 100 + g * 17 + mode * 3)
			if mode == Rules.Mode.CTF:
				check(captures > 0, "bots capture flags in %s" % arena)


func _bot_match(mode: int, arena: String, seed: int) -> int:
	var players := {}
	for i in 6:
		players[-(i + 1)] = {"name": "Bot%d" % i, "look": i, "slot": i, "bot": true, "blaster": i % 4, "skill": 1}
	var host := _new_host(players, {"mode": mode, "arena": arena, "minutes": 3}, seed)
	var what := "%s on %s (seed %d)" % [Rules.MODE_NAMES[mode], arena, seed]
	var dt := 1.0 / 30.0
	var steps := 0
	var stuck_in_walls := 0
	var max_darts := 0
	while host.phase != Rules.Phase.ENDED and steps < int(5.0 * 60.0 / dt):
		host.step(dt)
		steps += 1
		max_darts = maxi(max_darts, host.darts.size())
		if steps % 30 == 0:
			for id in host.actors:
				var a: Dictionary = host.actors[id]
				if a.alive and host.grid.blocked(a.pos, Rules.CAMPER_RADIUS * 0.5, host.time):
					stuck_in_walls += 1
	check(host.phase == Rules.Phase.ENDED, "%s ends" % what)
	check(stuck_in_walls == 0, "no camper is ever inside a wall in %s (%d)" % [what, stuck_in_walls])
	check(max_darts <= Rules.MAX_DARTS_IN_FLIGHT and host.pickups.size() <= Rules.MAX_PICKUPS, "dart counts stay capped in %s" % what)
	var r := host.result
	check(r.get("standings", []).size() == 6, "everyone is in the standings for %s" % what)
	var tags := 0
	for id in host.actors:
		tags += int(host.actors[id].stats.tags)
	check(tags > 0, "bots tag each other in %s" % what)
	if mode == Rules.Mode.HOARDER:
		var ok := true
		for row in r.standings:
			if int(row[1]) != int(host.actors[row[0]].ammo):
				ok = false
		check(ok, "dart hoarder scores are the darts held at the end")
	if not bool(r.tie):
		if Rules.is_team_mode(mode):
			check(int(r.team) >= 0 and r.team_scores[r.team] > r.team_scores[1 - int(r.team)], "the winning team has the higher score in %s" % what)
		else:
			check(int(r.winner) == int(r.standings[0][0]), "the winner tops the standings in %s" % what)
	for m in r.get("medals", []):
		check(host.actors.has(m.id), "medal %s goes to a player in the match" % m.key)
	var captures := 0
	for id in host.actors:
		captures += int(host.actors[id].stats.captures)
	return captures

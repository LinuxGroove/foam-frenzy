extends Node
## Saves screenshots of menus or a match, for checking the look without a
## screen (run under xvfb-run, optionally with --resolution WxH):
##   godot --path . tools/screenshot.tscn -- out_prefix [options] [seconds...]
## Options:
##   title | welcome | settings | about | keyboard | howto   the title screen
##   lobby | lobby_edit | couch                             the lobby
##   mode=ctf arena=lab couch practice pause results scores  a match
## Or every menu, arena and mode, as JPEGs in <dir>/<group>/<name>.jpg with a
## README.md listing them (or one group, or only the README: --index=<dir>):
##   godot --path . --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots [group=lobby]
## The campers on this device play themselves there, and the player's own
## settings file is put back afterwards. Godot needs a Vulkan driver to draw
## the game as players see it (Mesa's lavapipe works with no GPU: apt install
## mesa-vulkan-drivers); with only OpenGL the arenas come out paler.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var prefix := args[0] if args.size() > 0 else "/tmp/shot"
	var times := []
	var opts := {}
	for i in range(1, args.size()):
		var a: String = args[i]
		if a.is_valid_float():
			times.append(float(a))
		elif "=" in a:
			opts[a.get_slice("=", 0)] = a.get_slice("=", 1)
		else:
			opts[a] = true
	if times.is_empty():
		times = [6.0]
	LGSettings.register_defaults(GameConfig.SETTING_DEFAULTS)
	LGInput.register_actions(GameConfig.ACTIONS)
	LGInput.extend_ui_actions()
	LGTheme.apply(get_tree().root, 22)
	if prefix.begins_with("--index="):
		_write_index(_absolute(prefix.trim_prefix("--index=")))
		get_tree().quit()
		return
	if prefix.begins_with("--all="):
		await _all(_absolute(prefix.trim_prefix("--all=")), str(opts.get("group", "")))
		return
	LGSettings.set_value("player", "name", "Ken", false)
	Session.local_seats[0].name = "Ken"
	if not opts.has("welcome"):
		LGSettings.set_value("tutorial", "welcomed", true, false)
		LGSettings.set_value("tutorial", "howto_seen", true, false)
	if opts.has("couch"):
		# Pretend two more controllers joined (ids no real pad uses).
		for pad in [90, 91]:
			Session.local_seats.append({"pad": pad, "name": "Player %d" % (Session.local_seats.size() + 1),
				"look": 4 + pad % 5, "blaster": pad % 4})
	get_tree().current_scene = null
	for menu in ["title", "welcome", "settings", "about", "keyboard", "howto", "lobby", "lobby_edit"]:
		if opts.has(menu):
			await _menus(prefix, opts)
			get_tree().quit()
			return
	if opts.has("practice"):
		Session.start_practice()
	else:
		Session.start_solo(5)
		if opts.has("mode"):
			Session.set_setting("mode", Rules.MODE_KEYS.find(str(opts.mode)))
		if opts.has("arena"):
			Session.set_setting("arena", str(opts.arena))
		Session.start_match()
	var t := 0.0
	var n := 0
	for when in times:
		await get_tree().create_timer(when - t, true).timeout
		t = when
		var game: Game = get_tree().current_scene as Game
		if game and n == times.size() - 1:
			if opts.has("pause"):
				game.hud.open_pause()
				await get_tree().create_timer(0.3, true).timeout
			if opts.has("results") and game.host:
				game.host._finish()
				await get_tree().create_timer(2.0, true).timeout
			if opts.has("scores"):
				Input.action_press("scores")
				await get_tree().create_timer(0.4, true).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, n])
		n += 1
	get_tree().quit()


func _menus(prefix: String, opts: Dictionary) -> void:
	var lobby: bool = opts.has("lobby") or opts.has("lobby_edit")
	if lobby:
		Session.start_solo(3)
	LGScenes.change_scene("res://game/ui/%s.tscn" % ("lobby" if lobby else "title"))
	await get_tree().create_timer(4.0).timeout
	var scene := get_tree().current_scene
	if opts.has("settings"):
		scene._show_settings()
	if opts.has("about"):
		scene._show_about()
	if opts.has("keyboard"):
		scene._show_name(false)
		await get_tree().create_timer(0.3).timeout
		var edit: LineEdit = scene._col.find_children("*", "LineEdit", true, false)[0]
		var kb := OnScreenKeyboard.open(edit, false)
		for ch in "Ken 0O":
			kb._type(ch)
	if opts.has("lobby_edit"):
		var c: LGCycler = scene._cyclers["mode"]
		c.grab_focus()
		c.set_editing(true)
	if opts.has("howto"):
		scene._show_howto()
		await get_tree().create_timer(0.5).timeout
		var panel: HowToPanel = scene._ui.get_child(scene._ui.get_child_count() - 1)
		for page in HowToPanel.pages().size():
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s_howto%d.png" % [prefix, page])
			panel._go(1)
			await get_tree().create_timer(0.2).timeout
		return
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_menu.png" % prefix)


# --- Every screen (--all) ----------------------------------------------------

const TITLE := "res://game/ui/title.tscn"
const LOBBY := "res://game/ui/lobby.tscn"
## The groups --all makes, in order, with their headings in the README.
const GROUPS := [
	["menus", "Title and menus"],
	["lobby", "The lobby"],
	["arenas", "The arenas"],
	["matches", "Every arena and mode"],
	["in-match", "During a match"],
	["couch", "Couch play"],
	["practice", "The practice round"],
]
## The lobby shots, one per mode (in Rules.MODE_KEYS order): arena, bots, and
## the blaster picked.
const LOBBY_ARENAS := ["gym", "lab", "lab", "gym"]
const LOBBY_BOTS := [3, 5, 7, 4]
## The couch matches: name, players on this device, mode key, arena.
const COUCH := [["two", 2, "ffa", "gym"], ["three", 3, "ctf", "lab"], ["four", 4, "teams", "lab"]]
## Made-up games and players for the screens that would need a network.
const SAMPLE_HOSTS := [
	{"name": "Sam's arena", "players": 3, "max": 8, "state": "lobby", "address": "192.168.1.20", "port": 24680},
	{"name": "Riley's arena", "players": 6, "max": 8, "state": "playing", "address": "192.168.1.31", "port": 24680},
]
const SAMPLE_BOARD := [["Moxie", 31], ["Juniper", 27], ["Ken", 22], ["Otto", 19], ["Wren", 15],
	["Basil", 12], ["Pippa", 9], ["Rocco", 7], ["Tilly", 4], ["Ziggy", 2]]
const SAMPLE_RECORD := {"matches": 23, "wins": 6, "tags": 141, "outs": 98, "captures": 4}

## Where --all saves its pictures.
var _root := ""


func _absolute(dir: String) -> String:
	return dir if dir.begins_with("/") else ProjectSettings.globalize_path("res://").path_join(dir)


## Every shot --all makes, in order: [group, name, caption]. The README lists
## them from this.
static func _plan() -> Array:
	var out := []
	for m in [["title", "The title screen"], ["message", "The title screen after the host left a game"],
			["name", "Choosing a name the first time"], ["keyboard", "Typing a name with a controller"],
			["welcome", "The welcome for new players"], ["howto", "How to play"]]:
		out.append(["menus", m[0], m[1]])
	var pages := HowToPanel.pages()
	for i in pages.size():
		out.append(["menus", "tutorial-%d" % (i + 1), "Tutorial, page %d of %d: %s" % [i + 1, pages.size(), pages[i].title]])
	for m in [["local", "Local network play"], ["local-offline", "Local network play with no network"],
			["join", "Joining a game on this network (made-up games)"], ["online", "Play online"],
			["online-off", "Play online with online play turned off"],
			["leaderboards", "Leaderboards (made-up scores)"], ["quick-match", "Quick match, looking for players"],
			["settings", "Settings"], ["about", "About Foam Frenzy"]]:
		out.append(["menus", m[0], m[1]])
	for m in Rules.MODE_KEYS.size():
		out.append(["lobby", "bots-" + Rules.MODE_KEYS[m], "A match with bots: %s in %s, with the %s" % [
			Rules.MODE_NAMES[m], ArenaGrid.LAYOUTS[LOBBY_ARENAS[m]].name, Rules.blaster(m).name]])
	for m in [["changing-rules", "Changing the mode"], ["couch", "Three players on one screen"],
			["network-host", "Hosting on the local network, with the join code"],
			["quick-match", "Quick match with nobody else around: bots, and a countdown to the start"]]:
		out.append(["lobby", m[0], m[1]])
	for id in ArenaGrid.ARENA_IDS:
		out.append(["arenas", id, "%s: %s" % [ArenaGrid.LAYOUTS[id].name, ArenaGrid.LAYOUTS[id].about]])
	for id in ArenaGrid.ARENA_IDS:
		for m in Rules.MODE_KEYS.size():
			out.append(["matches", "%s-%s" % [id, Rules.MODE_KEYS[m]], "%s: %s" % [ArenaGrid.LAYOUTS[id].name, Rules.MODE_NAMES[m]]])
	for m in [["countdown", "The countdown"], ["tip", "A tip for new players"],
			["scoreboard-teams", "The scoreboard in Team Battle"], ["pause", "The pause menu"],
			["pause-controls", "The pause menu with the controls"], ["tagged-out", "Tagged out, and back in a moment"],
			["out-of-darts", "Out of darts"], ["final-seconds", "The last ten seconds"],
			["results-teams", "Results: Team Battle"], ["scoreboard-ffa", "The scoreboard in a free-for-all"],
			["results-ffa", "Results: Free-for-all"], ["flag-capture", "A flag capture"],
			["results-ctf", "Results: Capture the Flag"],
			["results-hoarder", "Results: Dart Hoarder"], ["first-tutorial", "The tutorial, before a new player's first match"]]:
		out.append(["in-match", m[0], m[1]])
	for c in COUCH:
		var m := Rules.MODE_KEYS.find(c[2])
		out.append(["couch", c[0], "%s players on one screen: %s in %s" % [str(c[0]).capitalize(), Rules.MODE_NAMES[m], ArenaGrid.LAYOUTS[c[3]].name]])
	var steps := PracticeGuide.STEPS.size() - 1
	for i in steps:
		var step: Dictionary = PracticeGuide.STEPS[i]
		out.append(["practice", step.key, "Step %d of %d: %s" % [i + 1, steps, step.text]])
	out.append(["practice", "done", "The end of the practice round"])
	return out


## Every group (or one), then the README.
func _all(root: String, only_group: String) -> void:
	_root = root
	var saved: Variant = _keep_settings()
	_fresh_settings()
	# The same shots whatever this machine's network is doing.
	LGNetwork.forced = true
	# Scene changes replace the current scene; this one stays to drive them.
	get_tree().current_scene = null
	for g in GROUPS:
		if only_group != "" and g[0] != only_group:
			continue
		DirAccess.make_dir_recursive_absolute(_root.path_join(g[0]))
		match g[0]:
			"menus":
				await _shoot_menus()
			"lobby":
				await _shoot_lobby()
			"arenas":
				await _shoot_arenas()
			"matches":
				await _shoot_matches()
			"in-match":
				await _shoot_in_match()
			"couch":
				await _shoot_couch()
			"practice":
				await _shoot_practice()
	_quiet()
	Session.leave()
	_write_index(_root)
	_restore_settings(saved)
	get_tree().quit()


## The menus save settings as they go; this keeps the player's own file.
func _keep_settings() -> Variant:
	if not FileAccess.file_exists(LGSettings.PATH):
		return null
	return FileAccess.get_file_as_bytes(LGSettings.PATH)


func _restore_settings(saved: Variant) -> void:
	if saved == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LGSettings.PATH))
		return
	var f := FileAccess.open(LGSettings.PATH, FileAccess.WRITE)
	if f:
		f.store_buffer(saved)


## A player who has been through the tutorial, with tips off and no game
## server to reach (the quick match shot brings its own).
func _fresh_settings() -> void:
	LGSettings._cfg = ConfigFile.new()
	for v in [["player", "name", "Ken"], ["video", "fullscreen", false],
			["tutorial", "welcomed", true], ["tutorial", "howto_seen", true],
			["tutorial", "practiced", true], ["tutorial", "hints", false],
			["online", "host", "127.0.0.1"], ["online", "port", 1], ["online", "scheme", "http"]]:
		LGSettings.set_value(v[0], v[1], v[2], false)
	Session._reset_seats()


## Saves what's on screen as <group>/<name>.jpg.
func _shot(group: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_jpg(_root.path_join(group).path_join(name + ".jpg"), 0.85)
	print("Saved ", group, "/", name, ".jpg")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


## Stops the screen showing now from following the session, so starting the
## next shot's session doesn't send it to the title screen first.
func _quiet() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	for c in Session.left.get_connections():
		if c.callable.get_object() == scene:
			Session.left.disconnect(c.callable)


## Waits until the scene called `scene_name` is up (a match is "Game").
func _arrive(scene_name: String) -> Node:
	var waited := 0.0
	while waited < 30.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		var scene := get_tree().current_scene
		if scene != null and scene.name == scene_name and not LGScenes.is_busy():
			return scene
	push_error("%s never came up" % scene_name)
	return get_tree().current_scene


func _go_to(path: String, scene_name: String, setup := Callable()) -> Node:
	_quiet()
	LGScenes.change_scene(path, setup)
	var scene: Node = await _arrive(scene_name)
	await _wait(1.2)
	return scene


## A fresh match with bots (and this device's couch seats), its campers
## playing themselves.
func _match(mode: int, arena: String, bots := 7) -> Game:
	_quiet()
	Session.start_solo(bots)
	Session.set_setting("mode", mode)
	Session.set_setting("arena", arena)
	Session.start_match()
	var game: Game = await _arrive("Game")
	game.add_child(Autopilot.new(game))
	return game


## Waits for the match to start, then `seconds` more.
func _play_for(game: Game, seconds: float) -> void:
	var waited := 0.0
	while game.phase != Rules.Phase.PLAY and waited < 20.0:
		await _wait(0.05)
		waited += 0.05
	await _wait(seconds)


## Waits (for a while at most) until this device's campers are all back in
## play, so the camera is on them.
func _all_in(game: Game) -> void:
	var waited := 0.0
	while game.locals.values().any(func(lc): return not lc.alive) and waited < 6.0:
		await _wait(0.1)
		waited += 0.1
	if waited > 0.0:
		await _wait(1.2)


func _remove_couch() -> void:
	for i in range(Session.local_seats.size() - 1, 0, -1):
		Session.remove_local_seat(i)


func _shoot_menus() -> void:
	var t: Node = await _go_to(TITLE, "Title")
	await _shot("menus", "title")
	t = await _go_to(TITLE, "Title", func(n): n.set("message", "The host left the game."))
	await _shot("menus", "message")
	t = await _go_to(TITLE, "Title")
	await _menu(t._show_name.bind(true), "name")
	t._show_name(false)
	await _wait(0.3)
	var edit: LineEdit = t._col.find_children("*", "LineEdit", true, false)[0]
	edit.text = ""
	var kb := OnScreenKeyboard.open(edit, false)
	for ch in "Ken":
		kb._type(ch)
	await _wait(0.4)
	await _shot("menus", "keyboard")
	kb.get_parent().queue_free()
	await _menu(t._show_welcome, "welcome")
	await _menu(t._show_howto_menu, "howto")
	t._show_tutorial()
	await _wait(0.5)
	var panel: HowToPanel = t._ui.get_child(t._ui.get_child_count() - 1)
	for page in HowToPanel.pages().size():
		await _shot("menus", "tutorial-%d" % (page + 1))
		panel._go(1)
		await _wait(0.3)
	await _menu(t._show_local, "local")
	LGNetwork.forced = false
	await _menu(t._show_local, "local-offline")
	LGNetwork.forced = true
	t._show_join()
	await _wait(0.5)
	var hosts := []
	for h in SAMPLE_HOSTS:
		var host: Dictionary = h.duplicate()
		host.protocol = GameConfig.PROTOCOL
		hosts.append(host)
	t._on_hosts(hosts)
	await _wait(0.3)
	await _shot("menus", "join")
	Session.stop_browsing()
	await _menu(t._show_online, "online")
	LGSettings.set_value("online", "enabled", false, false)
	await _menu(t._show_online, "online-off")
	LGSettings.set_value("online", "enabled", true, false)
	# With no network the boards give up at once; then they get made-up rows.
	LGNetwork.forced = false
	t._show_leaderboards()
	await _wait(0.6)
	LGNetwork.forced = true
	for c in t._col.get_children():
		if c is LGLeaderboardPanel:
			var top := []
			for i in SAMPLE_BOARD.size():
				top.append({"rank": i + 1, "name": SAMPLE_BOARD[i][0], "score": SAMPLE_BOARD[i][1], "me": SAMPLE_BOARD[i][0] == "Ken"})
			c.show_record(SAMPLE_RECORD)
			c.show_board({"top": top, "mine": top[2]})
	await _wait(0.3)
	await _shot("menus", "leaderboards")
	# Settings as a new player finds them, not as these shots need them.
	LGSettings.set_value("online", "host", OnlineServer.HOST, false)
	LGSettings.set_value("tutorial", "hints", true, false)
	LGSettings._cfg.set_value("video", "fullscreen", true)
	await _menu(t._show_settings, "settings")
	LGSettings.set_value("online", "host", "127.0.0.1", false)
	LGSettings.set_value("tutorial", "hints", false, false)
	LGSettings._cfg.set_value("video", "fullscreen", false)
	await _menu(t._show_about, "about")
	await _quick_match_search(t)


func _menu(show: Callable, name: String) -> void:
	show.call()
	await _wait(0.6)
	await _shot("menus", name)


## The quick match search, against a local "server" that never answers.
func _quick_match_search(t: Node) -> void:
	var server := TCPServer.new()
	server.listen(0, "127.0.0.1")
	LGSettings.set_value("online", "port", server.get_local_port(), false)
	t._show_online()
	t._quick_match()
	await _wait(1.0)
	# As if it had been looking for a while.
	t._search_since = Time.get_ticks_msec() - 14000
	await _wait(0.3)
	await _shot("menus", "quick-match")
	Session.cancel_quick_match()
	server.stop()
	# The search gives up without its server and goes back to online play.
	var waited := 0.0
	while t._search_since != 0 and waited < 20.0:
		await _wait(0.2)
		waited += 0.2
	LGSettings.set_value("online", "port", 1, false)


func _shoot_lobby() -> void:
	var lobby: Node
	for m in Rules.MODE_KEYS.size():
		_quiet()
		Session.start_solo(LOBBY_BOTS[m])
		Session.set_setting("mode", m)
		Session.set_setting("arena", LOBBY_ARENAS[m])
		Session.set_seat_value(0, "blaster", m)
		lobby = await _go_to(LOBBY, "Lobby")
		await _shot("lobby", "bots-" + Rules.MODE_KEYS[m])
	var c: LGCycler = lobby._cyclers["mode"]
	c.grab_focus()
	c.set_editing(true)
	await _wait(0.3)
	await _shot("lobby", "changing-rules")
	c.set_editing(false)
	Session.set_seat_value(0, "blaster", 0)
	_quiet()
	Session.leave()
	for pad in [90, 91]:
		Session.add_local_seat(pad)
	Session.start_solo(3)
	Session.set_setting("mode", Rules.Mode.TEAMS)
	Session.set_setting("arena", "lab")
	await _go_to(LOBBY, "Lobby")
	await _shot("lobby", "couch")
	_quiet()
	Session.leave()
	_remove_couch()
	Session.settings = Rules.DEFAULT_SETTINGS.duplicate()
	if Session.host_lan():
		var port := int(LGSettings.get_value("lan", "port"))
		# A typical home network's code, not this machine's.
		Session.join_code = JoinCode.encode("192.168.86.143", port, port)
		Session.add_bot()
		Session.add_bot()
		await _go_to(LOBBY, "Lobby")
		await _shot("lobby", "network-host")
	_quiet()
	Session.start_quick_solo()
	await _go_to(LOBBY, "Lobby")
	await _shot("lobby", "quick-match")
	_quiet()
	Session.leave()


## Each arena from high up, with no HUD.
func _shoot_arenas() -> void:
	for id in ArenaGrid.ARENA_IDS:
		var game := await _match(Rules.Mode.FFA, id)
		await _play_for(game, 6.0)
		game.hud.visible = false
		game.camera.set_process(false)
		var size := game.grid.world_size()
		var center := Vector3(size.x * 0.5, 0.0, size.y * 0.5)
		var pitch := deg_to_rad(64.0)
		game.camera.position = center + Vector3(0.0, sin(pitch), cos(pitch)) * 41.0
		game.camera.look_at(center, Vector3.UP)
		await _wait(0.2)
		await _shot("arenas", id)


func _shoot_matches() -> void:
	for id in ArenaGrid.ARENA_IDS:
		for m in Rules.MODE_KEYS.size():
			var game := await _match(m, id)
			await _play_for(game, 8.0)
			await _all_in(game)
			await _shot("matches", "%s-%s" % [id, Rules.MODE_KEYS[m]])


func _shoot_in_match() -> void:
	# Team Battle with tips on, as for a new player.
	LGSettings.set_value("tutorial", "hints", true, false)
	LGSettings.set_value("tutorial", "seen", "", false)
	var game := await _match(Rules.Mode.TEAMS, "gym")
	var waited := 0.0
	while (game.phase != Rules.Phase.COUNTDOWN or game.countdown > 1.2) and waited < 20.0:
		await _wait(0.05)
		waited += 0.05
	await _shot("in-match", "countdown")
	await _play_for(game, 3.5)
	await _shot("in-match", "tip")
	await _wait(3.0)
	await _scoreboard("scoreboard-teams")
	game.hud.open_pause()
	await _wait(0.4)
	await _shot("in-match", "pause")
	game.hud.pause._toggle_help()
	await _wait(0.3)
	await _shot("in-match", "pause-controls")
	game.hud.pause.close()
	game.hud.hide_hint()
	var me: int = game.locals.keys()[0]
	var lc: LocalCamper = game.locals[me]
	var foe: int = game.roster.keys().filter(func(id): return game.actor_team(id) != game.actor_team(me))[0]
	game.host._tag_out(game.host.actors[me], game.host.actors[foe])
	await _wait(0.8)
	await _shot("in-match", "tagged-out")
	waited = 0.0
	while not lc.alive and waited < 10.0:
		await _wait(0.1)
		waited += 0.1
	await _wait(1.0)
	game.hud.hide_hint()
	game.host.actors[me].ammo = 0
	await _wait(0.2)
	lc.fire_cd = 0.0
	lc._fire()
	await _wait(0.7)
	await _shot("in-match", "out-of-darts")
	game.hud.hide_hint()
	game.host.clock = 9.4
	await _wait(1.2)
	await _shot("in-match", "final-seconds")
	await _results(game, "results-teams")
	LGSettings.set_value("tutorial", "hints", false, false)
	for key in ["ffa", "ctf", "hoarder"]:
		game = await _match(Rules.MODE_KEYS.find(key), "gym" if key == "ctf" else "lab")
		await _play_for(game, 10.0)
		if key == "ffa":
			await _scoreboard("scoreboard-ffa")
		if key == "ctf":
			await _capture(game)
		await _results(game, "results-" + key)
	LGSettings.set_value("tutorial", "howto_seen", false, false)
	game = await _match(Rules.Mode.FFA, "lab")
	await _wait(1.5)
	await _shot("in-match", "first-tutorial")
	LGSettings.set_value("tutorial", "howto_seen", true, false)


func _scoreboard(name: String) -> void:
	Input.action_press("scores")
	await _wait(0.4)
	await _shot("in-match", name)
	Input.action_release("scores")


## A capture, scored by the rules: this device's camper gets home with the
## other team's flag while its own flag is safe.
func _capture(game: Game) -> void:
	var me: int = game.locals.keys()[0]
	var lc: LocalCamper = game.locals[me]
	var waited := 0.0
	while not lc.alive and waited < 10.0:
		await _wait(0.1)
		waited += 0.1
	var host := game.host
	var a: Dictionary = host.actors[me]
	var theirs := 1 - int(a.team)
	for team in 2:
		var carrier: int = host.flags[team].carrier
		if carrier != 0:
			host.actors[carrier].flag = -1
		if host.flags[team].state != 0:
			host._return_flag(team, 0)
	host.flags[theirs].state = 1
	host.flags[theirs].carrier = me
	a.flag = theirs
	lc.pos = game.grid.bases[a.team]
	a.pos = lc.pos
	await _wait(0.7)
	await _shot("in-match", "flag-capture")


## Runs the clock out, so the match ends the way the rules end it (a tie
## goes to overtime first).
func _results(game: Game, name: String) -> void:
	game.host.clock = 0.05
	var waited := 0.0
	while game.phase != Rules.Phase.ENDED and waited < 20.0:
		await _wait(0.1)
		waited += 0.1
	if game.phase != Rules.Phase.ENDED:
		game.host._finish()
	await _wait(ResultsPanel.SHOW_AFTER + 0.8)
	await _shot("in-match", name)


func _shoot_couch() -> void:
	for c in COUCH:
		_quiet()
		Session.leave()
		_remove_couch()
		for i in int(c[1]) - 1:
			Session.add_local_seat(90 + i)
		var game := await _match(Rules.MODE_KEYS.find(c[2]), c[3], GameConfig.MAX_PLAYERS - int(c[1]))
		await _play_for(game, 7.0)
		await _all_in(game)
		await _shot("couch", c[0])
	_quiet()
	Session.leave()
	_remove_couch()


## Each step of the guide in turn (held there while the shot is taken), then
## the end of the round.
func _shoot_practice() -> void:
	_quiet()
	Session.start_practice()
	var game: Game = await _arrive("Game")
	game.add_child(Autopilot.new(game))
	await _play_for(game, 1.0)
	var guide: PracticeGuide = game.hud.guide
	guide.set_process(false)
	guide._shots = 1
	guide._dives = 1
	guide._tags = 1
	for i in PracticeGuide.STEPS.size() - 1:
		guide._step = i
		guide._show()
		guide._panel.visible = true
		await _wait(1.6)
		await _shot("practice", PracticeGuide.STEPS[i].key)
	guide._finish()
	await _wait(0.5)
	await _shot("practice", "done")


## A README.md beside the screenshots, listing the ones that are there.
func _write_index(root: String) -> void:
	var lines := ["# Screenshots", "", "Every menu, arena and mode of Foam Frenzy, made with:", "",
		"    xvfb-run -a -s \"-screen 0 1280x720x24\" godot --path . --resolution 1280x720 tools/screenshot.tscn -- --all=docs/screenshots", "",
		"In the match shots the player's own campers play themselves. Godot needs a Vulkan driver to draw them as the game looks (Mesa's lavapipe works with no GPU: `apt install mesa-vulkan-drivers`).", ""]
	var plan := _plan()
	for g in GROUPS:
		if not DirAccess.dir_exists_absolute(root.path_join(g[0])):
			continue
		var files := Array(DirAccess.get_files_at(root.path_join(g[0]))).filter(func(f): return f.ends_with(".jpg"))
		if files.is_empty():
			continue
		lines.append_array(["## %s" % g[1], ""])
		var listed := []
		for p in plan:
			if p[0] == g[0] and files.has(p[1] + ".jpg"):
				listed.append([p[1], p[2]])
		# Anything not in the plan goes last, under its file name.
		for f in files:
			var n: String = f.trim_suffix(".jpg")
			if not listed.any(func(x): return x[0] == n):
				listed.append([n, n])
		for x in listed:
			lines.append_array(["**%s**" % x[1], "", "![%s](%s/%s.jpg)" % [x[1], g[0], x[0]], ""])
	var out := FileAccess.open(root.path_join("README.md"), FileAccess.WRITE)
	if out:
		out.store_string("\n".join(lines))


## Plays this device's campers the way bots play, so the shots have some
## action in them. Runs after the campers' own (idle) controls each tick.
class Autopilot extends Node:
	var game: Game
	var _brains := {}
	var _send_t := 0.0

	func _init(p_game: Game) -> void:
		game = p_game
		process_physics_priority = 10

	func _physics_process(delta: float) -> void:
		if game.host == null or game.phase != Rules.Phase.PLAY or game.hud.blocks_input():
			return
		_send_t -= delta
		var send := _send_t <= 0.0
		if send:
			_send_t = LocalCamper.SEND_EVERY
		for id in game.locals:
			var lc: LocalCamper = game.locals[id]
			# The camper's own sends would report it standing still.
			lc._send_t = 1.0
			if not lc.placed or not lc.alive:
				continue
			if not _brains.has(id):
				var brain := BotBrain.new()
				brain.setup(game.host, id, 2, false)
				_brains[id] = brain
			var intent: Dictionary = _brains[id].think(delta)
			var move: Vector2 = intent.get("move", Vector2.ZERO)
			lc.yaw = float(intent.get("yaw", lc.yaw))
			lc.aim = Rules.yaw_dir(lc.yaw)
			if intent.get("dive", false) and lc.dive_cd <= 0.0:
				lc.dive_t = Rules.DIVE_TIME
				lc.dive_cd = Rules.DIVE_COOLDOWN
				lc._dive_dir = move.normalized() if move.length() > 0.2 else lc.aim
				game.to_host("_c_dive", [id])
			# A dive moves the camper by itself.
			if lc.dive_t <= 0.0:
				lc.pos = game.grid.move(lc.pos, move * Rules.MOVE_SPEED * delta, Rules.CAMPER_RADIUS, game.match_time)
			lc.moving = move.length() > 0.1 or lc.dive_t > 0.0
			if intent.get("fire", false) and lc.fire_cd <= 0.0 and lc.ammo > 0:
				lc._fire()
			lc.view.set_local(lc.pos, lc.yaw, lc.moving, lc.dive_t > 0.0)
			lc._show_aim(true)
			if send:
				game.to_host("_c_state", [id, lc.pos, lc.yaw, lc.moving])

extends Node
## Saves screenshots of menus or a match, for checking the look without a
## screen (run under xvfb-run, optionally with --resolution WxH):
##   godot --path . tools/screenshot.tscn -- out_prefix [options] [seconds...]
## Options:
##   title | welcome | settings | about | keyboard | howto   the title screen
##   lobby | lobby_edit | couch                             the lobby
##   mode=ctf arena=lab couch practice pause results scores  a match

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

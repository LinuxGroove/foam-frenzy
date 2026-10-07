extends Node
## The title screen: play with bots, local network play, online play and
## leaderboards, how to play (tutorial and practice), settings and quit.

const LOBBY := "res://game/ui/lobby.tscn"
const TITLE_COLOR := Color("ffd23f")

## Shown once when arriving here, e.g. why the last game ended.
var message := ""

var _ui: Control
var _col: VBoxContainer
var _status: Label
var _hosts_box: VBoxContainer
var _about_scroll: ScrollContainer
## Set once a button has started leaving this screen (or a join is under
## way), so a double press can't start a second session or scene change.
var _leaving := false


func _ready() -> void:
	LGInput.filter_claimed_pads = false
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_ui)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.12, 0.45)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.add_child(shade)
	var version := LGUi.label("v%s" % GameConfig.version(), "HintLabel")
	_ui.add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	_col = LGUi.centered_column(_ui, 560)
	# Every button stays on screen however short the screen is.
	LGScreenFit.center(_col)
	# Methods, not lambdas: a lambda stays connected to the autoload after this
	# screen is freed and would keep running.
	Session.status.connect(_on_status)
	Session.hosts_found.connect(_on_hosts)
	LGAudio.play_music("res://assets/kenney/audio/music/wacky_waiting.ogg", -8.0)
	if str(LGSettings.get_value("player", "name")).strip_edges() == "":
		_show_name(true)
	elif not bool(LGSettings.get_value("tutorial", "welcomed", false)):
		_show_welcome()
	else:
		_show_main()


func _on_status(text: String) -> void:
	if _status and is_instance_valid(_status):
		_status.text = text


func _clear() -> void:
	# Detach before freeing: queue_free alone leaves the old buttons in the tree
	# until frame end, so focus_first would grab one that is about to vanish.
	for c in _col.get_children():
		_col.remove_child(c)
		c.queue_free()
	_hosts_box = null
	_about_scroll = null


func _add_title() -> void:
	var title := LGUi.label("Foam Frenzy", "HeaderLarge")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TITLE_COLOR)
	title.add_theme_font_override("font", load("res://assets/kenney/fonts/Kenney Blocks.ttf"))
	_col.add_child(title)
	var tag := LGUi.label("Foam darts, pillow forts and up to eight friends.\nEvery dart you fire is one someone else can pick up.", "HintLabel")
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(tag)


func _add_status(text := "") -> void:
	_status = LGUi.label(text, "HintLabel")
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(_status)


func _show_main() -> void:
	_clear()
	_add_title()
	_col.add_child(LGUi.button("Play with bots", _play_solo))
	_col.add_child(LGUi.button("Local network play", _show_local))
	_col.add_child(LGUi.button("Play online", _show_online))
	_col.add_child(LGUi.button("How to play", _show_howto_menu))
	_col.add_child(LGUi.button("Settings", _show_settings))
	_col.add_child(LGUi.button("Your name: %s" % Session.player_name(), _show_name.bind(false)))
	_col.add_child(LGUi.button("About Foam Frenzy", _show_about))
	var quit := LGUi.button("Quit", _quit)
	quit.theme_type_variation = "DangerButton"
	_col.add_child(quit)
	_add_status(message)
	message = ""
	LGUi.focus_first(_col)


func _quit() -> void:
	get_tree().quit()


func _show_name(first_time: bool) -> void:
	_clear()
	_add_title()
	_col.add_child(LGUi.label("What should we call you?", "HeaderMedium"))
	var edit := LineEdit.new()
	edit.max_length = 16
	edit.placeholder_text = "Your name"
	edit.text = str(LGSettings.get_value("player", "name"))
	edit.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(edit)
	_col.add_child(edit)
	var save := func():
		var n := edit.text.strip_edges()
		if n == "":
			n = "Camper %d" % randi_range(10, 99)
		LGSettings.set_value("player", "name", n)
		if first_time:
			LGSettings.set_value("player", "look", randi() % GameConfig.LOOKS.size())
		Session.local_seats[0].name = n
		Session.local_seats[0].look = Session.player_look()
		if not bool(LGSettings.get_value("tutorial", "welcomed", false)):
			_show_welcome()
		else:
			_show_main()
	edit.text_submitted.connect(func(_t): save.call())
	_col.add_child(LGUi.button("OK", save))
	if not first_time:
		_col.add_child(LGUi.button("Back", _show_main))
	edit.grab_focus.call_deferred()


## Claims the screen for one action that leaves it; false if one is running.
func _claim() -> bool:
	if _leaving or LGScenes.is_busy():
		return false
	_leaving = true
	return true


func _play_practice() -> void:
	if _claim():
		Session.start_practice()


func _show_howto_menu() -> void:
	_clear()
	_col.add_child(LGUi.label("How to play", "HeaderMedium"))
	_col.add_child(LGUi.button("Tutorial", _show_tutorial))
	_col.add_child(LGUi.button("Practice round", _play_practice))
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


## The pages open over the menu, which hides so focus stays on the pages.
func _show_tutorial() -> void:
	_col.visible = false
	var panel := HowToPanel.new()
	_ui.add_child(panel)
	panel.closed.connect(_on_howto_closed.bind(panel))
	panel.open()


func _on_howto_closed(panel: HowToPanel) -> void:
	panel.queue_free()
	_col.visible = true
	LGUi.focus_first(_col)


## Shown once the first time the menu appears. The tutorial comes first, then
## the practice round, so new players learn the goal before they're in a match.
func _show_welcome() -> void:
	LGSettings.set_value("tutorial", "welcomed", true)
	_clear()
	_add_title()
	var l := LGUi.label("New here? Start with the tutorial: a few pages on the goal and the controls. Then try the practice round against two friendly coaches.", "HintLabel")
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_col.add_child(l)
	_col.add_child(LGUi.button("Tutorial", _welcome_tutorial))
	_col.add_child(LGUi.button("Practice round", _play_practice))
	_col.add_child(LGUi.button("Not now", _show_main))
	LGUi.focus_first(_col)


func _welcome_tutorial() -> void:
	_show_howto_menu()
	_show_tutorial()


func _play_solo() -> void:
	if not _claim():
		return
	Session.start_solo(3)
	LGScenes.change_scene(LOBBY)


func _show_local() -> void:
	_clear()
	_col.add_child(LGUi.label("Local network play", "HeaderMedium"))
	_col.add_child(LGUi.label("Play with others on the same Wi-Fi or wired network.", "HintLabel"))
	_col.add_child(LGUi.button("Host on this network", _host_lan))
	_col.add_child(LGUi.button("Join on this network", _show_join))
	_col.add_child(LGUi.button("Back", _show_main))
	_add_status()
	LGUi.focus_first(_col)


func _host_lan() -> void:
	if not _claim():
		return
	if Session.host_lan():
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false


func _show_join() -> void:
	_clear()
	_col.add_child(LGUi.label("Join on this network", "HeaderMedium"))
	_col.add_child(LGUi.label("Games hosted nearby show up here.", "HintLabel"))
	_hosts_box = VBoxContainer.new()
	_hosts_box.add_theme_constant_override("separation", 8)
	_col.add_child(_hosts_box)
	_on_hosts([])
	_col.add_child(LGUi.label("Or type the host's join code:", "HintLabel"))
	var code := LineEdit.new()
	code.placeholder_text = "ABCD-EFGH"
	code.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(code, true)
	_col.add_child(code)
	var join := func():
		if not _claim():
			return
		if Session.join_lan_code(code.text):
			_wait_for_join()
		else:
			_leaving = false
	code.text_submitted.connect(func(_t): join.call())
	_col.add_child(LGUi.button("Join with code", join))
	_col.add_child(LGUi.button("Back", _back_from_join))
	_add_status()
	Session.browse_lan()
	LGUi.focus_first(_col)


func _back_from_join() -> void:
	Session.stop_browsing()
	_show_local()


func _on_hosts(hosts: Array) -> void:
	if _hosts_box == null or not is_instance_valid(_hosts_box):
		return
	for c in _hosts_box.get_children():
		_hosts_box.remove_child(c)
		c.queue_free()
	if hosts.is_empty():
		_hosts_box.add_child(LGUi.label("Looking for games...", "HintLabel"))
		return
	for h in hosts:
		var playing := str(h.get("state", "lobby")) != "lobby"
		var text := "%s  (%d/%d)%s" % [h.get("name", "An arena"), int(h.get("players", 0)), int(h.get("max", GameConfig.MAX_PLAYERS)), "  playing" if playing else ""]
		var b := LGUi.button(text, _join_host.bind(h))
		b.disabled = playing or int(h.get("protocol", 0)) != GameConfig.PROTOCOL
		_hosts_box.add_child(b)


func _join_host(h: Dictionary) -> void:
	if not _claim():
		return
	if Session.join_lan(str(h.address), int(h.get("port", LGSettings.get_value("lan", "port")))):
		_wait_for_join()
	else:
		_leaving = false


func _wait_for_join() -> void:
	_status.text = "Joining..."
	var result: Array = await _first_of_joined_or_left()
	if result[0] == "joined":
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false
		if is_instance_valid(_status):
			_status.text = str(result[1]) if str(result[1]) != "" else "Couldn't join."


func _first_of_joined_or_left() -> Array:
	var out := []
	var on_joined := func(): if out.is_empty(): out.append_array(["joined", ""])
	var on_left := func(reason: String): if out.is_empty(): out.append_array(["left", reason])
	Session.joined.connect(on_joined)
	Session.left.connect(on_left)
	var waited := 0.0
	while out.is_empty() and waited < 10.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	Session.joined.disconnect(on_joined)
	Session.left.disconnect(on_left)
	if out.is_empty():
		Session.leave()
		return ["left", "The host didn't answer."]
	return out


func _show_online() -> void:
	_clear()
	_col.add_child(LGUi.label("Play online", "HeaderMedium"))
	if not LGOnline.is_enabled():
		var info := LGUi.label("Online play goes through a LinuxGroove game server. Add its address in Settings to turn it on.", "HintLabel")
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_col.add_child(info)
		_col.add_child(LGUi.button("Settings", _show_settings))
		_col.add_child(LGUi.button("Back", _show_main))
		LGUi.focus_first(_col)
		return
	var info2 := LGUi.label("Host a room and share its code, or type a friend's code to join. Couch players come along.", "HintLabel")
	info2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_col.add_child(info2)
	_col.add_child(LGUi.button("Host an online room", _host_online))
	var code := LineEdit.new()
	code.placeholder_text = "Room code"
	code.max_length = 8
	code.custom_minimum_size = Vector2(520, 56)
	LGUi.gamepad_text_entry(code, true)
	_col.add_child(code)
	_col.add_child(LGUi.button("Join with code", _join_online.bind(code)))
	_col.add_child(LGUi.button("Leaderboards", _show_leaderboards))
	_col.add_child(LGUi.button("Back", _show_main))
	_add_status()
	LGUi.focus_first(_col)


func _show_leaderboards() -> void:
	_clear()
	_col.add_child(LGUi.label("Leaderboards", "HeaderMedium"))
	_col.add_child(LGUi.label("From online matches.", "HintLabel"))
	var panel := LGLeaderboardPanel.new()
	panel.setup(GameConfig.GAME_ID, Session.player_name(), [
		["wins_weekly", "Wins this week"],
		["wins", "Wins, all time"],
		["tags", "Campers tagged"],
	], record_text)
	_col.add_child(panel)
	_col.add_child(LGUi.button("Back", _show_online))
	LGUi.focus_first(_col)


## The player's online record, from the stats the server keeps per match.
static func record_text(stats: Dictionary) -> String:
	var matches := int(stats.get("matches", 0))
	if matches == 0:
		return "No online matches yet. Finish one to start your record."
	var parts := [
		_count(matches, "match", "matches"),
		_count(int(stats.get("wins", 0)), "win", "wins"),
		_count(int(stats.get("tags", 0)), "tag", "tags"),
		_count(int(stats.get("outs", 0)), "out", "outs"),
	]
	var captures := int(stats.get("captures", 0))
	if captures > 0:
		parts.append(_count(captures, "flag capture", "flag captures"))
	return "Your online record: %s." % ", ".join(parts)


static func _count(n: int, one: String, many: String) -> String:
	return "%d %s" % [n, one if n == 1 else many]


func _host_online() -> void:
	if not _claim():
		return
	_status.text = "Connecting..."
	if await Session.host_online():
		LGScenes.change_scene(LOBBY)
	else:
		_leaving = false


func _join_online(code: LineEdit) -> void:
	if not _claim():
		return
	_status.text = "Connecting..."
	if await Session.join_online(code.text):
		_wait_for_join()
	else:
		_leaving = false


func _show_settings() -> void:
	_clear()
	_col.add_child(LGUi.label("Settings", "HeaderMedium"))
	var panel := SettingsPanel.new()
	_col.add_child(panel)
	for row in [["Aim assist", "play", "aim_assist", [[0, "Off"], [1, "A little"], [2, "A lot"]]],
			["Auto-fire with the right stick", "play", "auto_fire", SettingsPanel.ON_OFF],
			["Screen shake", "play", "shake", SettingsPanel.ON_OFF],
			["Tips during play", "tutorial", "hints", SettingsPanel.ON_OFF]]:
		panel.add_child(LGCycler.make(row[0], row[3], LGSettings.get_value(row[1], row[2]), _set_value.bind(row[1], row[2])))
	_col.add_child(LGUi.button("Back", _show_main))
	LGUi.focus_first(_col)


func _set_value(value: Variant, section: String, key: String) -> void:
	LGSettings.set_value(section, key, value)


## Credits. Up and down scroll the page, since Back is the only button.
func _show_about() -> void:
	_clear()
	_col.add_child(LGUi.label("About Foam Frenzy", "HeaderMedium"))
	_about_scroll = ScrollContainer.new()
	_about_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_about_scroll.custom_minimum_size = Vector2(620, 480)
	_col.add_child(_about_scroll)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "GlassPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_about_scroll.add_child(panel)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = ABOUT_TEXT % GameConfig.version()
	panel.add_child(text)
	var back := LGUi.button("Back", _show_main)
	_col.add_child(back)
	back.grab_focus.call_deferred()


func _input(event: InputEvent) -> void:
	if _about_scroll == null or not is_instance_valid(_about_scroll):
		return
	var step := 0
	if event.is_action_pressed("ui_down", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -1
	if step != 0:
		_about_scroll.scroll_vertical += step * 60
		get_viewport().set_input_as_handled()


const ABOUT_TEXT := """[center][b]Foam Frenzy[/b]  v%s
A LinuxGroove game

[b]Created by[/b]
Ken VanDine

[b]Art, sound, music and fonts[/b]
Kenney (kenney.nl)
Released under CC0. Thank you, Kenney!

Blocky Characters, Blaster Kit, Mini Arena, Prototype Kit,
Crosshair Pack, Medals, Input Prompts, UI Pack - Adventure,
Kenney Fonts, Music Loops, Music Jingles, Synth Voice,
Impact Sounds, Interface Sounds, Digital Audio,
Sci-Fi Sounds, Foley Sounds

[b]Made with[/b]
Godot Engine (godotengine.org), MIT
Nakama Godot client by Heroic Labs, Apache-2.0

Copyright (c) 2026 The LinuxGroove team
Foam Frenzy is free software under the MIT license.[/center]"""

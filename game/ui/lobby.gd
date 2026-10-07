extends Node
## The lobby before a match: who's playing, bots, each player's look and
## blaster, couch players on extra controllers, the match rules, the join
## code, and the host's Start button.
##
## Menus are driven by the first player (keyboard, mouse, or their
## controller). Every other controller here belongs to a couch player, who
## steers only their own card: d-pad left and right change their look, up and
## down their blaster, B leaves. Start on a new controller adds a player.

const RULE_ROWS := [
	["mode", "Mode", []],
	["arena", "Arena", []],
	["minutes", "Time", [[2, "2 min"], [3, "3 min"], [5, "5 min"], [8, "8 min"], [0, "No limit"]]],
	["target", "Score to win", [[0, "Usual"], [5, "5"], [10, "10"], [15, "15"], [20, "20"], [30, "30"], [50, "50"]]],
	["bot_skill", "Bot skill", [[0, "Easy"], [1, "Normal"], [2, "Hard"]]],
	["darts_per_life", "Darts to start with", [[3, "3"], [6, "6"], [10, "10"], [20, "20"]]],
	["friendly_fire", "Friendly fire", [[false, "Off"], [true, "On"]]],
]
const STICK := 0.6
const REPEAT := 0.28

var _roster: VBoxContainer
var _cyclers := {}
var _code: Label
var _status: Label
var _about: Label
var _start: Button
var _add_bot: Button
var _remove_bot: Button
var _look: LGCycler
var _blaster: LGCycler
var _blaster_about: Label
var _preview: LookPreview
var _seat_box: HBoxContainer
var _join_hint: Label
var _cards := {}
## Per pad: {"buttons": {button: bool}, "repeat": seconds}
var _pads := {}


func _ready() -> void:
	LGInput.filter_claimed_pads = true
	add_child(MenuBackdrop.new())
	var layer := CanvasLayer.new()
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(ui)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.05, 0.12, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	ui.add_child(margin)
	# The lobby lays out at the size it needs and scales down on short screens.
	LGScreenFit.fill(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	margin.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := LGUi.label(_title_text(), "HeaderMedium")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_code = LGUi.label("", "HeaderMedium")
	_code.add_theme_color_override("font_color", Color("ffd23f"))
	head.add_child(_code)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)
	_build_players(body)
	_build_rules(body)
	# Couch players' cards, side by side under the panels.
	_seat_box = HBoxContainer.new()
	_seat_box.add_theme_constant_override("separation", 12)
	col.add_child(_seat_box)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	col.add_child(bottom)
	_status = LGUi.label("", "HintLabel")
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bottom.add_child(_status)
	var leave := LGUi.button("Leave", _leave, 200)
	leave.theme_type_variation = "DangerButton"
	bottom.add_child(leave)
	_start = LGUi.button("Start the match", _start_match, 300)
	bottom.add_child(_start)
	# Methods, not lambdas: a lambda stays connected to the autoload after the
	# lobby is freed, so an old lobby would still send everyone to the title
	# screen when a later session ends.
	Session.roster_changed.connect(_refresh)
	Session.settings_changed.connect(_refresh)
	Session.seats_changed.connect(_refresh_seats)
	Session.status.connect(_on_status)
	Session.left.connect(_on_left)
	LGAudio.play_music("res://assets/kenney/audio/music/cheerful_annoyance.ogg", -8.0)
	_refresh()
	_refresh_seats()
	if Session.is_host():
		_start.grab_focus.call_deferred()
	else:
		_look.grab_focus.call_deferred()


func _exit_tree() -> void:
	LGInput.filter_claimed_pads = false


func _build_players(body: HBoxContainer) -> void:
	# No scrolling here: the whole lobby scales down instead (LGScreenFit), so
	# the roster and your picks are always in view.
	var left := PanelContainer.new()
	left.theme_type_variation = "DarkPanel"
	left.custom_minimum_size.x = 500
	body.add_child(left)
	var lcol := VBoxContainer.new()
	lcol.add_theme_constant_override("separation", 8)
	left.add_child(lcol)
	lcol.add_child(LGUi.label("Campers", "HeaderMedium"))
	_roster = VBoxContainer.new()
	_roster.add_theme_constant_override("separation", 0)
	lcol.add_child(_roster)
	var bots := HBoxContainer.new()
	bots.add_theme_constant_override("separation", 10)
	lcol.add_child(bots)
	_add_bot = LGUi.button("Add bot", _on_add_bot, 210)
	_remove_bot = LGUi.button("Remove bot", _on_remove_bot, 210)
	bots.add_child(_add_bot)
	bots.add_child(_remove_bot)
	lcol.add_child(LGUi.label("You", "HeaderMedium"))
	var me := HBoxContainer.new()
	me.add_theme_constant_override("separation", 10)
	lcol.add_child(me)
	var seat0: Dictionary = Session.local_seats[0]
	_preview = LookPreview.make(int(seat0.look), int(seat0.blaster), GameConfig.slot_color(_my_slot(0)), Vector2(130, 160))
	me.add_child(_preview)
	var picks := VBoxContainer.new()
	picks.alignment = BoxContainer.ALIGNMENT_CENTER
	picks.add_theme_constant_override("separation", 6)
	me.add_child(picks)
	var looks := []
	for i in GameConfig.LOOKS.size():
		looks.append([i, "Camper %d" % (i + 1)])
	_look = LGCycler.make("Look", looks, int(seat0.look), _on_look, 330)
	picks.add_child(_look)
	var blasters := []
	for i in Rules.BLASTERS.size():
		blasters.append([i, Rules.BLASTERS[i].name])
	_blaster = LGCycler.make("Blaster", blasters, int(seat0.blaster), _on_blaster, 330)
	picks.add_child(_blaster)
	_blaster_about = LGUi.label("", "HintLabel")
	_blaster_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blaster_about.custom_minimum_size.x = 330
	picks.add_child(_blaster_about)
	_join_hint = LGUi.label("", "HintLabel")
	_join_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_join_hint.custom_minimum_size.x = 440
	lcol.add_child(_join_hint)


func _build_rules(body: HBoxContainer) -> void:
	var right := PanelContainer.new()
	right.theme_type_variation = "DarkPanel"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(right)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	right.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)
	box.add_child(LGUi.label("Match rules", "HeaderMedium"))
	for row in RULE_ROWS:
		var key: String = row[0]
		var options: Array = row[2]
		match key:
			"mode":
				options = []
				for i in Rules.MODE_NAMES.size():
					options.append([i, Rules.MODE_NAMES[i]])
			"arena":
				options = []
				for a in ArenaGrid.ARENA_IDS:
					options.append([a, ArenaGrid.title_of(a)])
		var c := LGCycler.make(row[1], options, Session.settings.get(key), _set_rule.bind(key), 500)
		_cyclers[key] = c
		box.add_child(c)
	_about = LGUi.label("", "HintLabel")
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size.x = 480
	box.add_child(_about)


func _set_rule(value: Variant, key: String) -> void:
	Session.set_setting(key, value)


func _on_add_bot() -> void:
	Session.add_bot()


func _on_remove_bot() -> void:
	Session.remove_bot()


func _start_match() -> void:
	Session.start_match()


func _on_look(v: Variant) -> void:
	Session.set_seat_value(0, "look", int(v))


func _on_blaster(v: Variant) -> void:
	Session.set_seat_value(0, "blaster", int(v))


func _on_status(text: String) -> void:
	_status.text = text


func _on_left(reason: String) -> void:
	LGScenes.change_scene("res://game/ui/title.tscn", func(n): n.set("message", reason))


func _title_text() -> String:
	match Session.mode:
		Session.Mode.SOLO:
			return "A match with bots"
		Session.Mode.LAN_HOST, Session.Mode.ONLINE_HOST:
			return "Your arena"
	return "Joined an arena"


## This device's seat `seat` in the roster: its colour slot.
func _my_slot(seat: int) -> int:
	var id := Session.actor_id(Session.local_id(), seat)
	return int(Session.players.get(id, {}).get("slot", seat))


func _refresh() -> void:
	for c in _roster.get_children():
		_roster.remove_child(c)
		c.queue_free()
	var ids: Array = Session.players.keys()
	# People first in join order, then bots.
	ids.sort_custom(func(a, b): return (a if a > 0 else 100000000 - a) < (b if b > 0 else 100000000 - b))
	for id in ids:
		var p: Dictionary = Session.players[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = GameConfig.slot_color(int(p.get("slot", 0)))
		swatch.custom_minimum_size = Vector2(22, 22)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var tags := []
		if p.get("bot", false):
			tags.append("bot")
		elif int(p.peer) == Session.local_id():
			tags.append("you" if int(p.seat) == 0 else "couch")
		if not p.get("bot", false) and int(p.peer) == 1 and int(p.seat) == 0:
			tags.append("host")
		var name := LGUi.label("%s%s" % [p.name, ("  (%s)" % ", ".join(tags)) if not tags.is_empty() else ""])
		name.add_theme_font_size_override("font_size", 20)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var blaster := LGUi.label(str(Rules.blaster(int(p.get("blaster", 0))).name), "HintLabel")
		row.add_child(blaster)
		_roster.add_child(row)
	var host := Session.is_host()
	_add_bot.visible = host
	_remove_bot.visible = host
	_add_bot.disabled = Session.players.size() >= GameConfig.MAX_PLAYERS
	_remove_bot.disabled = not Session.players.values().any(func(p): return p.get("bot", false))
	for key in _cyclers:
		_cyclers[key].set_value(Session.settings.get(key))
		_cyclers[key].set_read_only(not host)
	var mode := int(Session.settings.get("mode", 0))
	var target := Rules.target_score(Session.settings)
	_about.text = "%s\n\n%s" % [Rules.MODE_BLURBS[mode], str(ArenaGrid.LAYOUTS.get(str(Session.settings.arena), {}).get("about", ""))]
	if mode != Rules.Mode.HOARDER and int(Session.settings.get("target", 0)) == 0:
		_about.text += "\n\nUsual score to win: %d." % target
	_start.visible = host
	_start.disabled = not Session.can_start()
	var blocker := Session.start_blocker()
	if Session.quick and Session.quick_seconds_left() > 0.0:
		if Session.mode == Session.Mode.SOLO:
			_status.text = "Nobody else was looking for a game, so it's you and some bots."
		elif host and blocker != "":
			_status.text = "Bots fill any empty spots when the countdown ends."
		elif not host:
			_status.text = "The match starts by itself when the countdown ends."
	elif host and blocker != "":
		_status.text = blocker
	elif not host:
		_status.text = "Waiting for the host to start the match."
	_refresh_code()
	_preview.set_color(GameConfig.slot_color(_my_slot(0)))
	for i in _cards:
		_cards[i].set_color(GameConfig.slot_color(_my_slot(i)))


func _refresh_code() -> void:
	if Session.quick:
		var left := ceili(Session.quick_seconds_left())
		_code.text = "Quick match: starts in %d s" % left if left > 0 else "Quick match"
		return
	match Session.mode:
		Session.Mode.LAN_HOST:
			_code.text = "Join code: %s" % JoinCode.pretty(Session.join_code) if Session.join_code != "" else "No network found"
		Session.Mode.ONLINE_HOST, Session.Mode.ONLINE_CLIENT:
			_code.text = "Room code: %s" % Session.join_code
		_:
			_code.text = ""


# --- Couch seats ---------------------------------------------------------

func _refresh_seats() -> void:
	var seat0: Dictionary = Session.local_seats[0]
	_preview.set_camper(int(seat0.look), int(seat0.blaster))
	_blaster_about.text = str(Rules.blaster(int(seat0.blaster)).about)
	for i in _cards.keys():
		if i >= Session.local_seats.size():
			_cards[i].queue_free()
			_cards.erase(i)
	for i in range(1, Session.local_seats.size()):
		if not _cards.has(i):
			var card := SeatCard.new()
			_seat_box.add_child(card)
			card.setup(i)
			_cards[i] = card
		_cards[i].show_seat(Session.local_seats[i], GameConfig.slot_color(_my_slot(i)))
	_seat_box.visible = Session.local_seats.size() > 1
	var room := Session.local_seats.size() < GameConfig.MAX_LOCAL
	_join_hint.visible = room
	_join_hint.text = "Playing on one screen? Press Start on another controller to join." if room else ""


func _process(delta: float) -> void:
	if Session.quick:
		# Keeps the quick-match countdown ticking.
		_refresh_code()
	var menu_pad := LGInput.menu_pad()
	for pad in Input.get_connected_joypads():
		var state: Dictionary = _pads.get(pad, {"buttons": {}, "repeat": 0.0})
		_pads[pad] = state
		var seat := Session.seat_for_pad(pad)
		if _pressed(pad, state, JOY_BUTTON_START):
			if seat < 0 and pad != menu_pad:
				if Session.add_local_seat(pad) < 0 and Session.local_seats.size() >= GameConfig.MAX_LOCAL:
					_status.text = "Up to %d players can share one screen." % GameConfig.MAX_LOCAL
			elif seat < 0 and Session.is_host() and not _start.disabled:
				_start.grab_focus()
		if seat <= 0:
			continue
		if _pressed(pad, state, JOY_BUTTON_B):
			Session.remove_local_seat(seat)
			continue
		var dir := _direction(pad, state, delta)
		if dir.x != 0:
			var look := wrapi(int(Session.local_seats[seat].look) + dir.x, 0, GameConfig.LOOKS.size())
			Session.set_seat_value(seat, "look", look)
		elif dir.y != 0:
			var b := wrapi(int(Session.local_seats[seat].blaster) + dir.y, 0, Rules.BLASTERS.size())
			Session.set_seat_value(seat, "blaster", b)
	for pad in _pads.keys():
		if not pad in Input.get_connected_joypads():
			_pads.erase(pad)


## True on the frame `button` went down on `pad`.
func _pressed(pad: int, state: Dictionary, button: int) -> bool:
	var down := Input.is_joy_button_pressed(pad, button)
	var was := bool(state.buttons.get(button, false))
	state.buttons[button] = down
	return down and not was


## A d-pad or stick step for a couch player's card, with key-repeat.
func _direction(pad: int, state: Dictionary, delta: float) -> Vector2i:
	var x := Input.get_joy_axis(pad, JOY_AXIS_LEFT_X)
	var y := Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y)
	var d := Vector2i.ZERO
	if Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_LEFT) or x < -STICK:
		d.x = -1
	elif Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_RIGHT) or x > STICK:
		d.x = 1
	elif Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_UP) or y < -STICK:
		d.y = -1
	elif Input.is_joy_button_pressed(pad, JOY_BUTTON_DPAD_DOWN) or y > STICK:
		d.y = 1
	if d == Vector2i.ZERO:
		state.repeat = 0.0
		return d
	state.repeat = float(state.repeat) - delta
	if float(state.repeat) > 0.0:
		return Vector2i.ZERO
	state.repeat = REPEAT
	return d


func _leave() -> void:
	# Session.left takes everyone back to the title screen.
	Session.leave("")


## A couch player's card: their look, blaster and how to change them.
class SeatCard extends PanelContainer:
	var index := 0
	var _preview: LookPreview
	var _name: Label
	var _what: Label
	var _color := Color.WHITE

	func setup(p_index: int) -> void:
		index = p_index
		theme_type_variation = "GlassPanel"
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		add_child(row)
		var seat: Dictionary = Session.local_seats[index]
		custom_minimum_size.x = 400
		_preview = LookPreview.make(int(seat.look), int(seat.blaster), _color, Vector2(80, 96))
		row.add_child(_preview)
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(col)
		_name = LGUi.label("", "NameLabel")
		col.add_child(_name)
		_what = LGUi.label("")
		col.add_child(_what)
		var help := HBoxContainer.new()
		help.add_theme_constant_override("separation", 14)
		col.add_child(help)
		var family := LGInput.family_for_joypad(int(seat.pad))
		help.add_child(_glyph_hint(family, [JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT], "Look"))
		help.add_child(_glyph_hint(family, [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN], "Blaster"))
		help.add_child(_glyph_hint(family, [JOY_BUTTON_B], "Leave"))

	func show_seat(seat: Dictionary, color: Color) -> void:
		_color = color
		_name.text = str(seat.name)
		_name.add_theme_color_override("font_color", color.lightened(0.2))
		_what.text = "Camper %d with the %s" % [int(seat.look) + 1, Rules.blaster(int(seat.blaster)).name]
		_preview.set_camper(int(seat.look), int(seat.blaster))

	func set_color(color: Color) -> void:
		if color != _color:
			_color = color
			_name.add_theme_color_override("font_color", color.lightened(0.2))
			_preview.set_color(color)

	static func _glyph_hint(family: String, buttons: Array, text: String) -> Control:
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		for b in buttons:
			var icon := TextureRect.new()
			icon.custom_minimum_size = Vector2(28, 28)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture = LGInput.pad_glyph(family, b)
			box.add_child(icon)
		var l := LGUi.label(" " + text, "HintLabel")
		box.add_child(l)
		return box

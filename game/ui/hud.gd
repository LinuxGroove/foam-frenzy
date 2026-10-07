class_name Hud
extends CanvasLayer
## The in-match overlay: the clock and scores, a corner card for each player
## on this device (foam left, darts, score, respawn), the tag feed, big
## announcements, the scoreboard, tips, and the pause, how-to-play and
## results screens.

const FEED_MAX := 5
const FEED_TIME := 5.0
## Tips wrap at this width, so they stay clear of the corner cards.
const HINT_WIDTH := 560
const CORNERS := [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_TOP_LEFT, Control.PRESET_TOP_RIGHT]

var game: Game
var root: Control
var pause: PauseMenu
var howto: HowToPanel
var results: ResultsPanel
var hints: Hints
var guide: PracticeGuide
var scoreboard: Scoreboard
var practice := false

var _top: PanelContainer
var _clock: Label
var _goal: Label
var _team_labels: Array[Label] = []
var _seat_cards := {}
var _feed: VBoxContainer
var _announce: Label
var _announce_t := 0.0
var _waiting: Label
var _hint: PanelContainer
var _hint_row: HBoxContainer
var _hint_t := 0.0
var _flash: ColorRect
var _flash_t := 0.0


func setup(p_game: Game) -> void:
	game = p_game
	practice = game.practice
	layer = 10
	# The HUD keeps working while a solo match is paused.
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_flash = ColorRect.new()
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 0.25, 0.2, 0.0)
	root.add_child(_flash)
	_build_top()
	_build_feed()
	_build_announce()
	_waiting = LGUi.label("Waiting for everyone to reach the arena...", "HeaderMedium")
	_waiting.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_waiting.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_waiting.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_waiting)
	_build_hint()
	scoreboard = Scoreboard.new()
	root.add_child(scoreboard)
	scoreboard.setup(game)
	results = ResultsPanel.new()
	root.add_child(results)
	results.setup(game)
	pause = PauseMenu.new()
	root.add_child(pause)
	pause.setup(game)
	howto = HowToPanel.new()
	root.add_child(howto)
	if practice:
		guide = PracticeGuide.new()
		add_child(guide)
		guide.setup(game, self)
	else:
		hints = Hints.new()
		add_child(hints)
		hints.setup(game, self)
	game.status_changed.connect(_refresh_top)
	game.match_event.connect(_on_event)
	game.game_over.connect(_on_game_over)
	_refresh_top()
	# Someone who never opened the tutorial sees it before their first match.
	if not practice and not bool(LGSettings.get_value("tutorial", "howto_seen", false)):
		_first_howto.call_deferred()


## A match on this device alone waits while a new player reads the pages.
func _first_howto() -> void:
	if Session.mode == Session.Mode.SOLO:
		get_tree().paused = true
		howto.closed.connect(_unpause_after_howto, CONNECT_ONE_SHOT)
	howto.open()


func _unpause_after_howto() -> void:
	if not pause.visible:
		get_tree().paused = false


## Called by Game once its local campers exist.
func add_seat_card(lc: LocalCamper, color: Color) -> void:
	var card := SeatCard.new()
	root.add_child(card)
	root.move_child(card, _waiting.get_index())
	var index := _seat_cards.size()
	card.setup(game, lc, color, CORNERS[mini(index, CORNERS.size() - 1)])
	_seat_cards[lc.seat.index] = card


func blocks_input() -> bool:
	return pause.visible or howto.visible or results.visible or (guide != null and guide.blocking())


func open_pause() -> void:
	if pause.visible or results.visible or howto.visible or (guide != null and guide.blocking()):
		return
	pause.open()


func flash_hit(seat_index: int) -> void:
	var card: SeatCard = _seat_cards.get(seat_index)
	if card:
		card.flash_hit()
	# A screen-wide flash only makes sense when one person is playing here.
	if _seat_cards.size() == 1:
		_flash_t = 0.25


func flash_empty(seat_index: int) -> void:
	var card: SeatCard = _seat_cards.get(seat_index)
	if card:
		card.flash_empty()
	if hints:
		hints.on_empty()


## Big centre text, e.g. GO! or a capture.
func announce(text: String, color := Color.WHITE, seconds := 1.6) -> void:
	_announce.text = text
	_announce.add_theme_color_override("font_color", color)
	_announce.visible = true
	_announce.modulate.a = 1.0
	_announce.scale = Vector2(1.25, 1.25)
	_announce_t = seconds
	var tw := create_tween()
	tw.tween_property(_announce, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A one-time tip near the top of the screen, with the button glyph if `action` is set.
func show_hint(text: String, action := "", seconds := 8.0) -> void:
	for c in _hint_row.get_children():
		_hint_row.remove_child(c)
		c.queue_free()
	if action != "":
		_hint_row.add_child(ActionPrompt.make(action, text, 36, HINT_WIDTH - 60))
	else:
		var l := LGUi.label(text)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = HINT_WIDTH
		_hint_row.add_child(l)
	_hint.visible = true
	_hint_t = seconds


func hide_hint() -> void:
	_hint.visible = false
	_hint_t = 0.0


func _process(delta: float) -> void:
	_waiting.visible = game.phase == Rules.Phase.LOADING
	if game.phase == Rules.Phase.PLAY and game.clock > 0.0 and not get_tree().paused:
		game.clock = maxf(0.0, game.clock - delta)
	_update_clock()
	if game.phase == Rules.Phase.COUNTDOWN:
		var n := int(ceil(game.countdown))
		if n > 0 and _announce.text != str(n):
			announce(str(n), Color("ffe680"), 0.9)
	if _announce_t > 0.0:
		_announce_t -= delta
		_announce.modulate.a = clampf(_announce_t * 3.0, 0.0, 1.0)
		if _announce_t <= 0.0:
			_announce.visible = false
	if _hint_t > 0.0:
		_hint_t -= delta
		if _hint_t <= 0.0 or blocks_input():
			hide_hint()
	if _flash_t > 0.0:
		_flash_t = maxf(0.0, _flash_t - delta)
	_flash.color.a = _flash_t * 0.9
	for entry in _feed.get_children():
		var t: float = entry.get_meta("t") - delta
		entry.set_meta("t", t)
		entry.modulate.a = clampf(t, 0.0, 1.0)
		if t <= 0.0:
			entry.queue_free()
	var show_scores := Input.is_action_pressed("scores") and game.phase != Rules.Phase.ENDED and not blocks_input()
	scoreboard.visible = show_scores
	_top.visible = game.phase != Rules.Phase.LOADING and game.phase != Rules.Phase.ENDED


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	get_viewport().set_input_as_handled()
	if pause.visible:
		pause.close()
	else:
		open_pause()


# --- Building ---------------------------------------------------------------

func _build_top() -> void:
	_top = PanelContainer.new()
	_top.theme_type_variation = "GlassPanel"
	_top.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_top.position.y = 10
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_top.add_child(row)
	var team_mode := Rules.is_team_mode(game.mode)
	if team_mode:
		row.add_child(_team_label(0))
	var mid := VBoxContainer.new()
	mid.add_theme_constant_override("separation", 0)
	row.add_child(mid)
	_clock = LGUi.label("", "HeaderMedium")
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock.custom_minimum_size.x = 150
	mid.add_child(_clock)
	_goal = LGUi.label("", "HintLabel")
	_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(_goal)
	if team_mode:
		row.add_child(_team_label(1))


func _team_label(team: int) -> Label:
	var l := LGUi.label("", "HeaderMedium")
	l.add_theme_color_override("font_color", GameConfig.TEAM_COLORS[team].lightened(0.15))
	l.custom_minimum_size.x = 130
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if team == 0 else HORIZONTAL_ALIGNMENT_LEFT
	_team_labels.append(l)
	return l


func _build_feed() -> void:
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_feed.anchor_top = 0.2
	_feed.anchor_bottom = 0.2
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.offset_right = -14
	_feed.add_theme_constant_override("separation", 6)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_feed)


func _build_announce() -> void:
	_announce = LGUi.label("", "HeaderLarge")
	_announce.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_announce.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_announce.grow_vertical = Control.GROW_DIRECTION_BOTH
	_announce.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce.add_theme_constant_override("outline_size", 12)
	_announce.add_theme_font_size_override("font_size", 64)
	_announce.position.y -= 110
	_announce.visible = false
	root.add_child(_announce)
	_announce.resized.connect(func(): _announce.pivot_offset = _announce.size / 2.0)


func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.theme_type_variation = "GlassPanel"
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y = 104
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_hint)
	_hint_row = HBoxContainer.new()
	_hint.add_child(_hint_row)


# --- Refreshing --------------------------------------------------------------

func _update_clock() -> void:
	if practice:
		_clock.text = "Practice"
	elif game.overtime:
		_clock.text = "Overtime"
	elif game.clock < 0.0:
		_clock.text = ""
	else:
		var c := int(ceil(game.clock))
		_clock.text = "%d:%02d" % [c / 60, c % 60]
		_clock.modulate = Color("ff8a7a") if c <= 10 and game.phase == Rules.Phase.PLAY else Color.WHITE


func _refresh_top() -> void:
	if _team_labels.size() == 2:
		_team_labels[0].text = "Red %d" % int(game.team_scores[0])
		_team_labels[1].text = "%d Blue" % int(game.team_scores[1])
	var target := Rules.target_score(game.settings)
	match game.mode:
		Rules.Mode.FFA:
			_goal.text = _leader_text(target)
		Rules.Mode.TEAMS:
			_goal.text = "First team to %d tags" % target if target > 0 else "Most tags wins"
		Rules.Mode.CTF:
			_goal.text = "First to %d captures" % target if target > 0 else "Most captures wins"
		Rules.Mode.HOARDER:
			_goal.text = "Most darts at the buzzer"
	if practice:
		_goal.text = "Take your time"
	for card in _seat_cards.values():
		card.refresh()


func _leader_text(target: int) -> String:
	var best := 0
	var best_id := 0
	for id in game.scores:
		if int(game.scores[id]) > best:
			best = int(game.scores[id])
			best_id = id
	var goal := "First to %d tags" % target if target > 0 else "Most tags wins"
	if best_id == 0:
		return goal
	return "%s   %s leads with %d" % [goal, game.actor_name(best_id), best]


func _on_event(kind: int, a: int, b: int) -> void:
	match kind:
		MatchHost.Ev.TAG:
			if a != 0 and a != b:
				_feed_line([[game.actor_name(a), game.actor_color(a)], [" tagged ", Color.WHITE], [game.actor_name(b), game.actor_color(b)]], game.actor_color(a))
			else:
				_feed_line([[game.actor_name(b), game.actor_color(b)], [" is out", Color.WHITE]], game.actor_color(b))
			if game.is_local(a) and a != b:
				var card: SeatCard = _seat_cards.get(game.locals[a].seat.index)
				if card:
					card.cheer()
		MatchHost.Ev.FLAG_TAKEN:
			_feed_line([[game.actor_name(a), game.actor_color(a)], [" took the %s flag" % GameConfig.TEAM_NAMES[b].to_lower(), Color.WHITE]], GameConfig.TEAM_COLORS[b])
			if _is_my_team(b):
				announce("Your flag was taken!", GameConfig.TEAM_COLORS[b])
		MatchHost.Ev.FLAG_DROPPED:
			_feed_line([[game.actor_name(a), game.actor_color(a)], [" dropped the %s flag" % GameConfig.TEAM_NAMES[b].to_lower(), Color.WHITE]], GameConfig.TEAM_COLORS[b])
		MatchHost.Ev.FLAG_RETURNED:
			var who := game.actor_name(a) if a != 0 else "It"
			_feed_line([["The %s flag" % GameConfig.TEAM_NAMES[b].to_lower(), GameConfig.TEAM_COLORS[b]], [" went home" if a == 0 else " was saved by %s" % who, Color.WHITE]], GameConfig.TEAM_COLORS[b])
		MatchHost.Ev.CAPTURE:
			var team := game.actor_team(a)
			announce("%s team scores!" % GameConfig.TEAM_NAMES[team], GameConfig.TEAM_COLORS[team].lightened(0.2), 2.2)
			_feed_line([[game.actor_name(a), game.actor_color(a)], [" captured the flag!", Color.WHITE]], GameConfig.TEAM_COLORS[team])
		MatchHost.Ev.OVERTIME:
			announce("Overtime!\nNext score wins", Color("ffe680"), 2.5)
		MatchHost.Ev.LEAD:
			if b >= 0:
				_feed_line([["%s team takes the lead" % GameConfig.TEAM_NAMES[b], GameConfig.TEAM_COLORS[b]]], GameConfig.TEAM_COLORS[b])
			elif a != 0:
				_feed_line([[game.actor_name(a), game.actor_color(a)], [" takes the lead", Color.WHITE]], game.actor_color(a))
	_refresh_top()


func _is_my_team(team: int) -> bool:
	for id in game.locals:
		if game.actor_team(id) == team:
			return true
	return false


## One feed entry is its own bubble with a coloured edge, so lines never run
## together (a lesson from Lantern Out's chat).
func _feed_line(parts: Array, edge: Color) -> void:
	var bubble := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.05, 0.06, 0.1, 0.78)
	box.border_color = edge
	box.border_width_left = 6
	box.set_corner_radius_all(6)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	bubble.add_theme_stylebox_override("panel", box)
	bubble.size_flags_horizontal = Control.SIZE_SHRINK_END
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	bubble.add_child(row)
	for p in parts:
		var l := LGUi.label(str(p[0]))
		l.add_theme_font_size_override("font_size", 20)
		if p[1] != Color.WHITE:
			l.add_theme_color_override("font_color", (p[1] as Color).lightened(0.2))
		row.add_child(l)
	bubble.set_meta("t", FEED_TIME)
	_feed.add_child(bubble)
	while _feed.get_child_count() > FEED_MAX:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()


func _on_game_over(_res: Dictionary) -> void:
	pause.close()
	hide_hint()
	_announce.visible = false
	for card in _seat_cards.values():
		card.visible = false
	for c in _feed.get_children():
		c.queue_free()


# --- A local player's corner card -------------------------------------------

class SeatCard extends PanelContainer:
	var game: Game
	var lc: LocalCamper
	var _name: Label
	var _score: Label
	var _pips: Array[Panel] = []
	var _ammo: Label
	var _status: Label
	var _blaster: Label
	var _hit_t := 0.0
	var _empty_t := 0.0
	var _cheer_t := 0.0
	var _pip_on: StyleBoxFlat
	var _pip_off: StyleBoxFlat

	func setup(p_game: Game, p_lc: LocalCamper, color: Color, corner: int) -> void:
		game = p_game
		lc = p_lc
		theme_type_variation = "GlassPanel"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size.x = 270
		set_anchors_and_offsets_preset(corner)
		var right := corner in [Control.PRESET_BOTTOM_RIGHT, Control.PRESET_TOP_RIGHT]
		var bottom := corner in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT]
		grow_horizontal = Control.GROW_DIRECTION_BEGIN if right else Control.GROW_DIRECTION_END
		grow_vertical = Control.GROW_DIRECTION_BEGIN if bottom else Control.GROW_DIRECTION_END
		var dx := -14.0 if right else 14.0
		var dy := -14.0 if bottom else 14.0
		offset_left = dx
		offset_right = dx
		offset_top = dy
		offset_bottom = dy
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.05, 0.06, 0.1, 0.8)
		box.border_color = color
		box.set_border_width_all(0)
		box.border_width_top = 5
		box.set_corner_radius_all(10)
		box.set_content_margin_all(12)
		add_theme_stylebox_override("panel", box)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		add_child(col)
		var head := HBoxContainer.new()
		col.add_child(head)
		_name = LGUi.label(game.actor_name(lc.id), "NameLabel")
		_name.add_theme_color_override("font_color", color.lightened(0.2))
		_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_name.clip_text = true
		_name.custom_minimum_size.x = 120
		head.add_child(_name)
		_score = LGUi.label("")
		head.add_child(_score)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		_pip_on = StyleBoxFlat.new()
		_pip_on.bg_color = Color("fff6e0")
		_pip_on.set_corner_radius_all(4)
		_pip_off = StyleBoxFlat.new()
		_pip_off.bg_color = Color(1, 1, 1, 0.12)
		_pip_off.set_corner_radius_all(4)
		for i in Rules.HP:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(26, 18)
			pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(pip)
			_pips.append(pip)
		var gap := Control.new()
		gap.custom_minimum_size.x = 12
		row.add_child(gap)
		_ammo = LGUi.label("", "HeaderMedium")
		row.add_child(_ammo)
		_status = LGUi.label("", "HintLabel")
		col.add_child(_status)
		_blaster = LGUi.label(str(Rules.blaster(lc.blaster).name), "HintLabel")
		_blaster.modulate.a = 0.75
		col.add_child(_blaster)
		refresh()

	func flash_hit() -> void:
		_hit_t = 0.35

	func flash_empty() -> void:
		_empty_t = 1.6

	func cheer() -> void:
		_cheer_t = 0.6

	func refresh() -> void:
		var score := int(game.scores.get(lc.id, 0))
		match game.mode:
			Rules.Mode.HOARDER:
				_score.text = "Held %d" % score
			Rules.Mode.CTF:
				_score.text = "Points %d" % score
			_:
				_score.text = "Tags %d" % score

	func _process(delta: float) -> void:
		if lc == null or not is_instance_valid(lc):
			return
		for i in _pips.size():
			_pips[i].add_theme_stylebox_override("panel", _pip_on if i < lc.hp and lc.alive else _pip_off)
		_ammo.text = "%d darts" % lc.ammo if lc.ammo != 1 else "1 dart"
		_ammo.modulate = Color("ff8a7a") if lc.ammo == 0 else Color.WHITE
		_empty_t = maxf(0.0, _empty_t - delta)
		_hit_t = maxf(0.0, _hit_t - delta)
		_cheer_t = maxf(0.0, _cheer_t - delta)
		if not lc.placed:
			_status.text = ""
		elif not lc.alive:
			_status.text = "Back in %d" % ceili(lc.respawn) if lc.respawn > 0.0 else "Back in a moment"
		elif lc.carrying:
			_status.text = "You have the flag! Take it home."
		elif _empty_t > 0.0 or (lc.ammo == 0 and game.phase == Rules.Phase.PLAY):
			_status.text = "Out of darts! Grab some off the floor."
		else:
			_status.text = ""
		_status.visible = _status.text != ""
		var tint := Color.WHITE
		if _hit_t > 0.0:
			tint = Color(1.0, 0.55, 0.5)
		elif _cheer_t > 0.0:
			tint = Color(0.75, 1.0, 0.7)
		if _empty_t > 1.2 and int(_empty_t * 12.0) % 2 == 0:
			tint = Color(1.0, 0.8, 0.5)
		modulate = tint

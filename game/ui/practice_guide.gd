class_name PracticeGuide
extends Node
## Walks a new player through the practice match one skill at a time:
## moving, firing, picking darts back up, diving and tagging a coach out.
## The coaches are slow and fire rarely, and there's no clock.

const WALK_DISTANCE := 10.0
const SHOTS_NEEDED := 3
const DIVES_NEEDED := 2
const TAGS_NEEDED := 2

const STEPS := [
	{"key": "walk", "text": "Walk around the arena.", "action": "move_up"},
	{"key": "fire", "text": "Aim and fire a few darts.", "action": "fire"},
	{"key": "pickup", "text": "Walk over a dart on the floor to pick it up.", "action": ""},
	{"key": "dive", "text": "Dive twice. Nothing can hit you mid-dive.", "action": "dive"},
	{"key": "tag", "text": "Tag a coach out twice. Three hits each!", "action": "fire"},
	{"key": "done", "text": "", "action": ""},
]

var game: Game
var hud: Hud

var _step := 0
var _panel: PanelContainer
var _row: HBoxContainer
var _progress: Label
var _end: PanelContainer
var _end_col: VBoxContainer
var _walked := 0.0
var _last_pos := Vector2.INF
var _shots := 0
var _dives := 0
var _tags := 0
var _picked := false
var _last_ammo := -1
var _was_alive := false
var _was_diving := false
var _shown := -1


func setup(p_game: Game, p_hud: Hud) -> void:
	game = p_game
	hud = p_hud
	_build_panel()
	_build_end()
	game.match_event.connect(_on_event)


func blocking() -> bool:
	return _end.visible


func _on_event(kind: int, a: int, b: int) -> void:
	if kind == MatchHost.Ev.TAG and game.is_local(a) and a != b and STEPS[_step].key == "tag":
		_tags += 1


func _process(_delta: float) -> void:
	if _end.visible or game.locals.is_empty():
		return
	_panel.visible = game.phase == Rules.Phase.PLAY and not hud.pause.visible and not hud.howto.visible
	var lc := _player()
	if lc == null or not lc.placed:
		return
	_watch(lc)
	if _done(STEPS[_step].key):
		_step += 1
		LGAudio.play_sfx("res://assets/kenney/audio/sfx/confirmation_001.ogg", -6.0)
	if STEPS[_step].key == "done":
		_finish()
		return
	_show()


func _player() -> LocalCamper:
	for id in game.locals:
		if game.locals[id].seat.index == 0:
			return game.locals[id]
	return game.locals.values()[0]


func _watch(lc: LocalCamper) -> void:
	if _last_pos != Vector2.INF and lc.alive:
		_walked += minf(_last_pos.distance_to(lc.pos), 1.0)
	_last_pos = lc.pos
	if lc.alive and _was_alive and _last_ammo >= 0:
		if lc.ammo < _last_ammo:
			_shots += _last_ammo - lc.ammo
		elif lc.ammo > _last_ammo:
			_picked = true
	_last_ammo = lc.ammo
	_was_alive = lc.alive
	var diving := lc.dive_t > 0.0
	if diving and not _was_diving:
		_dives += 1
	_was_diving = diving


func _done(key: String) -> bool:
	match key:
		"walk":
			return _walked >= WALK_DISTANCE
		"fire":
			return _shots >= SHOTS_NEEDED
		"pickup":
			return _picked
		"dive":
			return _dives >= DIVES_NEEDED
		"tag":
			return _tags >= TAGS_NEEDED
	return false


func _progress_text(key: String) -> String:
	match key:
		"fire":
			return "%d / %d" % [mini(_shots, SHOTS_NEEDED), SHOTS_NEEDED]
		"dive":
			return "%d / %d" % [mini(_dives, DIVES_NEEDED), DIVES_NEEDED]
		"tag":
			return "%d / %d" % [mini(_tags, TAGS_NEEDED), TAGS_NEEDED]
	return ""


func _show() -> void:
	var step: Dictionary = STEPS[_step]
	_progress.text = "Step %d of %d   %s" % [_step + 1, STEPS.size() - 1, _progress_text(step.key)]
	if _shown == _step:
		return
	_shown = _step
	if step.key == "pickup":
		_picked = false
	for c in _row.get_children():
		_row.remove_child(c)
		c.queue_free()
	if step.action != "":
		_row.add_child(ActionPrompt.make(step.action, step.text, 40, Hud.HINT_WIDTH - 60))
	else:
		var l := LGUi.label(step.text)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = Hud.HINT_WIDTH
		_row.add_child(l)


func _finish() -> void:
	LGSettings.set_value("tutorial", "practiced", true)
	_panel.visible = false
	_end.visible = true
	LGUi.focus_first(_end_col)


func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "GlassPanel"
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.position.y = 104
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.root.add_child(_panel)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(col)
	_row = HBoxContainer.new()
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_row)
	_progress = LGUi.label("", "HintLabel")
	_progress.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_progress)


func _build_end() -> void:
	_end = PanelContainer.new()
	_end.theme_type_variation = "ParchmentPanel"
	_end.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end.custom_minimum_size = Vector2(600, 0)
	_end.visible = false
	hud.root.add_child(_end)
	_end_col = VBoxContainer.new()
	_end_col.add_theme_constant_override("separation", 14)
	_end.add_child(_end_col)
	var title := LGUi.label("Nice blasting!", "InkTitle")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_col.add_child(title)
	var text := LGUi.label("You're ready for a real match. Bots are a good start, then bring your friends.", "InkLabel")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.custom_minimum_size.x = 540
	_end_col.add_child(text)
	_end_col.add_child(LGUi.button("Play with bots", _play_with_bots, 540))
	_end_col.add_child(LGUi.button("Keep practising", _keep_going, 540))
	_end_col.add_child(LGUi.button("Back to the menu", _back, 540))


func _play_with_bots() -> void:
	game.detach_session()
	Session.start_solo(3)
	LGScenes.change_scene("res://game/ui/lobby.tscn")


func _keep_going() -> void:
	_end.visible = false
	set_process(false)


func _back() -> void:
	Session.leave("")

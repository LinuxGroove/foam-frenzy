class_name LGPlaytestSurvey
extends Control
## The questions at the end of a play test: ratings from 1 to 5, a few
## answers in the player's own words, the game's own questions for this
## round, and a little about the player. Every question can be skipped.
## Frees itself when done.

signal done(answers: Dictionary)

## [id, question]. Games drop ones that don't fit with options "skip".
const RATINGS := [
	["fun", "How much fun was it?"],
	["again", "How much do you want to play it again?"],
	["controls", "How good did the controls feel?"],
	["clarity", "How clear was it what to do next?"],
	["story", "How interesting was the story?"],
	["comfort", "How comfortable was it to play? (no dizziness or eye strain)"],
	["smooth", "How smoothly did it run?"],
]
const WRITTEN := [
	["friend", "What would you tell a friend about it?"],
	["best", "What was the best moment?"],
	["stop", "What nearly made you stop?"],
]
const ABOUT := [
	["before", "Played it before", [["", "-"], ["no", "No"], ["a_little", "A little"], ["a_lot", "A lot"]]],
	["genre", "Play games like this", [["", "-"], ["rarely", "Rarely"], ["sometimes", "Sometimes"], ["often", "Often"]]],
]
const WIDTH := 760
## The picked rating, clear in any game's theme.
const PICKED := Color(1.0, 0.78, 0.3)

var options := {}
var _list: VBoxContainer
var _ratings := {}
var _texts := {}
var _choices := {}
var _order: Array[String] = []


static func make(p_options := {}) -> LGPlaytestSurvey:
	var s := LGPlaytestSurvey.new()
	s.options = p_options
	s._build()
	return s


func _build() -> void:
	var col := LGPlaytestCard.frame(self, WIDTH)
	col.add_child(LGUi.label("Before you go", "HeaderMedium"))
	var hint := LGUi.label("A few quick questions about how it went. 1 is the least and 5 the most. Skip any you like.", "HintLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = WIDTH
	col.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(WIDTH, 460)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 12)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var skip: Array = options.get("skip", [])
	for r in RATINGS:
		if not r[0] in skip:
			_rating(r[0], r[1])
	for q in options.get("questions", []):
		if q.get("kind", "text") == "rating":
			_rating(q["id"], q["text"])
		else:
			_written(q["id"], q["text"])
	for w in WRITTEN:
		if not w[0] in skip:
			_written(w[0], w[1])
	_written("else", "Anything else?")
	for a in ABOUT:
		_choice(a[0], a[1], a[2])
	_written("name", "Your name, if you'd like us to know")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	row.add_child(LGUi.button("Done", submit, 260))
	row.add_child(LGUi.button("Skip the questions", skip_all, 260))
	col.add_child(row)


func _ready() -> void:
	LGUi.focus_first(_list)


func _question(text: String) -> void:
	var l := LGUi.label(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = WIDTH - 40
	_list.add_child(l)


func _rating(id: String, text: String) -> void:
	_question(text)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var group := ButtonGroup.new()
	group.allow_unpress = true
	var picked := StyleBoxFlat.new()
	picked.bg_color = PICKED
	picked.set_corner_radius_all(8)
	for n in range(1, 6):
		var b := Button.new()
		b.text = str(n)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(96, 52)
		for state in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(state, picked)
		for c in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(c, Color.BLACK)
		b.toggled.connect(_on_rating_toggled)
		row.add_child(b)
	_list.add_child(row)
	_ratings[id] = group
	_order.append(id)


func _on_rating_toggled(on: bool) -> void:
	if on:
		LGUi.click()


func _written(id: String, text: String) -> void:
	_question(text)
	var e := LineEdit.new()
	e.placeholder_text = "Type here (optional)"
	e.max_length = 1000
	e.custom_minimum_size = Vector2(WIDTH - 40, 48)
	LGUi.gamepad_text_entry(e)
	_list.add_child(e)
	_texts[id] = e
	_order.append(id)


func _choice(id: String, label: String, choices: Array) -> void:
	var c := LGCycler.make(label, choices, "", Callable(), WIDTH - 40)
	_list.add_child(c)
	_choices[id] = c
	_order.append(id)


## The question ids in order, for tests.
func questions() -> Array[String]:
	return _order


## Sets an answer as if the player gave it (a rating 1 to 5, text, or a choice).
func set_answer(id: String, value: Variant) -> void:
	if _ratings.has(id):
		for b in (_ratings[id] as ButtonGroup).get_buttons():
			b.button_pressed = int(value) == int(b.text)
	elif _texts.has(id):
		(_texts[id] as LineEdit).text = str(value)
	elif _choices.has(id):
		(_choices[id] as LGCycler).set_value(value)


## Only the questions answered: ratings as numbers, the rest as text.
func answers() -> Dictionary:
	var out := {}
	for id in _ratings:
		var picked := (_ratings[id] as ButtonGroup).get_pressed_button()
		if picked:
			out[id] = int(picked.text)
	for id in _texts:
		var t := (_texts[id] as LineEdit).text.strip_edges()
		if t != "":
			out[id] = t
	for id in _choices:
		var v: Variant = (_choices[id] as LGCycler).value()
		if v != null and str(v) != "":
			out[id] = v
	return out


func submit() -> void:
	var a := answers()
	a["answered"] = true
	done.emit(a)
	queue_free()


func skip_all() -> void:
	done.emit({"answered": false})
	queue_free()

class_name LGPlaytestNote
extends Control
## "What's happening?": the player tags this moment of a play test, with a
## few words if they like. Keys 1 to 6 pick a tag. Frees itself when done.

## [tag, note], or [] when cancelled.
signal done(picked: Array)

const TAGS := [
	["fun", "Fun"],
	["bored", "Bored"],
	["lost", "Lost"],
	["frustrated", "Frustrated"],
	["broken", "Broken"],
	["sick", "Feeling unwell"],
]

var note: LineEdit
var _column: VBoxContainer
var _tags: GridContainer


static func make() -> LGPlaytestNote:
	return LGPlaytestNote.new()


func _init() -> void:
	_column = LGPlaytestCard.frame(self, 620)
	_column.add_child(LGUi.label("What's happening?", "HeaderMedium"))
	var hint := LGUi.label("Pick what fits. Add a few words first if you like.", "HintLabel")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 620
	_column.add_child(hint)
	note = LineEdit.new()
	note.placeholder_text = "A few words (optional)"
	note.max_length = 300
	note.custom_minimum_size = Vector2(620, 48)
	LGUi.gamepad_text_entry(note)
	_column.add_child(note)
	_tags = GridContainer.new()
	_tags.columns = 3
	_tags.add_theme_constant_override("h_separation", 10)
	_tags.add_theme_constant_override("v_separation", 10)
	for t in TAGS:
		_tags.add_child(LGUi.button(t[1], pick.bind(t[0]), 200))
	_column.add_child(_tags)
	var cancel := LGUi.button("Cancel", cancel_note, 200)
	_column.add_child(cancel)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _ready() -> void:
	LGUi.focus_first(_tags)


func pick(tag: String) -> void:
	done.emit([tag, note.text.strip_edges()])
	queue_free()


func cancel_note() -> void:
	done.emit([])
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		cancel_note()
	elif event is InputEventKey and event.pressed and not event.echo:
		var i: int = event.physical_keycode - KEY_1
		if i >= 0 and i < TAGS.size():
			get_viewport().set_input_as_handled()
			pick(TAGS[i][0])

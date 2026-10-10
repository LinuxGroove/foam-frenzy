class_name LGPlaytestButton
extends Button
## "Note this moment" for a pause menu: shown only while a play test is
## recording, so players with a controller can note moments too.


static func make(width := 320) -> LGPlaytestButton:
	var b := LGPlaytestButton.new()
	b.text = "Note this moment"
	b.custom_minimum_size = Vector2(width, 56)
	return b


func _enter_tree() -> void:
	visible = LGPlaytest.recording()
	var p := LGPlaytest.current()
	if p and not p.recording_changed.is_connected(_on_recording_changed):
		# A method, so the connection goes away with the button.
		p.recording_changed.connect(_on_recording_changed)


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_recording_changed(on: bool) -> void:
	visible = on


func _on_pressed() -> void:
	LGUi.click()
	var p := LGPlaytest.current()
	if p:
		p.open_note()

extends Node
## Loads every script under addons/linuxgroove/, game/ and tests/ so parse and
## type errors show up without opening the editor. Runs as a scene so the
## autoloads exist:
##   godot --headless --path . tools/check_scripts.tscn

var failed := 0


func _ready() -> void:
	for dir in ["res://addons/linuxgroove", "res://game", "res://tests", "res://tools"]:
		_scan(dir)
	print("Checked scripts: %d failed" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _scan(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".gd"):
			var path := dir.path_join(f)
			var s: Script = load(path)
			if s == null or not s.can_instantiate():
				printerr("FAILED: ", path)
				failed += 1
	for sub in d.get_directories():
		_scan(dir.path_join(sub))

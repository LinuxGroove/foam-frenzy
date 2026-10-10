class_name LGPlaytestPack
extends RefCounted
## Turns a play test's folder into the one zip a tester sends, and packs
## sessions a crash cut short the next time the game starts.


## Zips `folder` (with the game's log) next to it and removes the folder.
## Returns the zip's path, or "" if it couldn't be written.
static func pack(folder: String, log_path := "") -> String:
	var info := read_json(folder.path_join("session.json"))
	var zip_path := folder.get_base_dir().path_join("%s-playtest-%s.zip" % [info.get("game", "game"), folder.get_file()])
	var zip := ZIPPacker.new()
	if zip.open(zip_path) != OK:
		push_warning("Play test: could not write %s" % zip_path)
		return ""
	for rel in _files(folder, ""):
		zip.start_file(rel)
		zip.write_file(FileAccess.get_file_as_bytes(folder.path_join(rel)))
		zip.close_file()
	if log_path != "" and FileAccess.file_exists(log_path):
		zip.start_file("godot.log")
		zip.write_file(FileAccess.get_file_as_bytes(log_path))
		zip.close_file()
	zip.close()
	_remove(folder)
	return zip_path


## Packs every unfinished session in `dir` (the game stopped without ending
## it), marked as ended suddenly with the log of the run that stopped.
## Returns the zips.
static func recover(dir: String) -> Array[String]:
	var zips: Array[String] = []
	var d := DirAccess.open(dir)
	if d == null:
		return zips
	for name in d.get_directories():
		var folder := dir.path_join(name)
		var info := read_json(folder.path_join("session.json"))
		if info.is_empty():
			continue
		info["ended_how"] = "suddenly"
		write_json(folder.path_join("session.json"), info)
		var zip := pack(folder, previous_log())
		if zip != "":
			zips.append(zip)
	return zips


## This run's log file.
static func current_log() -> String:
	return str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))


## The last run's log: Godot renames it with a date when the next run starts.
static func previous_log() -> String:
	var current := current_log()
	var dir := current.get_base_dir()
	var stem := current.get_file().get_basename()
	var best := ""
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for f in d.get_files():
		if f.begins_with(stem) and f != current.get_file() and f.get_extension() == "log" and f > best:
			best = f
	return dir.path_join(best) if best != "" else ""


static func read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


static func write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "  "))


static func _files(folder: String, rel: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(folder.path_join(rel))
	if d == null:
		return out
	for f in d.get_files():
		out.append(rel.path_join(f) if rel != "" else f)
	for sub in d.get_directories():
		out.append_array(_files(folder, rel.path_join(sub) if rel != "" else sub))
	return out


static func _remove(folder: String) -> void:
	var d := DirAccess.open(folder)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for sub in d.get_directories():
		_remove(folder.path_join(sub))
	DirAccess.remove_absolute(folder)

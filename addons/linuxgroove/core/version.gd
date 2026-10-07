class_name LGVersion
extends RefCounted
## The game's version is `application/config/version`. Builds get it from
## `tools/version.sh --stamp` in CI (2026.41.0 for a release tag, or
## 2026.41.0+3.g1a2b3c4d between releases). When the game runs from a source
## checkout instead, ask the same script, so the version shown, sent in
## hellos and reported to the game server matches the commit.

const SETTING := "application/config/version"
const SCRIPT := "res://tools/version.sh"


static func current() -> String:
	return str(ProjectSettings.get_setting(SETTING, "0.0.0"))


## Called once at startup (by LGSettings). Exported builds keep their
## stamped version.
static func stamp_from_source() -> void:
	if OS.has_feature("template") or not FileAccess.file_exists(SCRIPT):
		return
	var out := []
	if OS.execute("sh", [ProjectSettings.globalize_path(SCRIPT)], out) != 0 or out.is_empty():
		return
	var v := str(out[0]).strip_edges()
	if is_valid(v):
		ProjectSettings.set_setting(SETTING, v)


## MAJOR.MINOR.PATCH with optional +build metadata, as the game server accepts.
static func is_valid(v: String) -> bool:
	var re := RegEx.create_from_string("^\\d+(\\.\\d+){2}(\\+[0-9A-Za-z.]+)?$")
	return v.length() <= 32 and re.search(v) != null

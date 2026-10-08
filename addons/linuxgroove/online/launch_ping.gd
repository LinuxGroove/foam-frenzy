class_name LGLaunchPing
extends HTTPRequest
## One anonymous request each time the game starts, so the game server can
## count daily and total players of every game, online or not, and the
## systems and versions they play on (game-server docs/game-api.md, "Launch
## pings").
##
## It sends the game, a random install id made on the first run (not tied to
## the hardware or an account), the version, OS and CPU, and nothing else. It
## never signs in, never waits for an answer and never retries, so with no
## network or no server nothing happens. It stays quiet when DO_NOT_TRACK is
## set, in headless runs (tests, CI) and when running from source.

const PATH := "/launch"
const ID_FILE := "user://install_id"
const TIMEOUT := 5.0

## Sent already this run, so going back to the title doesn't send again.
static var sent := false

var _url := ""
var _body := ""


## Sends this run's ping in the background. Call it once at startup, after
## the game has registered its setting defaults (the server address).
static func send(game_id: String) -> void:
	if sent or not should_send():
		return
	var tree := Engine.get_main_loop() as SceneTree
	var address := url(tree.root.get_node_or_null("LGSettings"))
	if address == "":
		return
	sent = true
	var ping := LGLaunchPing.new()
	ping._url = address
	ping._body = JSON.stringify(body(game_id, install_id()))
	# Deferred: callers are usually in the middle of their own _ready.
	tree.root.add_child.call_deferred(ping)


func _ready() -> void:
	use_threads = true
	timeout = TIMEOUT
	request_completed.connect(_on_request_completed)
	if request(_url, ["Content-Type: application/json"], HTTPClient.METHOD_POST, _body) != OK:
		queue_free()


func _on_request_completed(_result: int, _code: int, _headers: PackedStringArray, _response: PackedByteArray) -> void:
	queue_free()


## Whether this run may send a ping at all.
static func should_send() -> bool:
	return not opted_out(OS.get_environment("DO_NOT_TRACK")) \
		and DisplayServer.get_name() != "headless" \
		and OS.has_feature("template") \
		and LGNetwork.is_up()


## DO_NOT_TRACK set to anything but empty, 0 or false turns pings off.
static func opted_out(do_not_track: String) -> bool:
	var v := do_not_track.strip_edges().to_lower()
	return v != "" and v != "0" and v != "false"


## Where pings go: the game server the game is set to use, or "" for none.
static func url(settings: Node) -> String:
	if settings == null:
		return ""
	var host := str(settings.get_value("online", "host")).strip_edges()
	if host == "":
		return ""
	return "%s://%s:%d%s" % [settings.get_value("online", "scheme"), host, int(settings.get_value("online", "port")), PATH]


## What a ping says.
static func body(game_id: String, install: String) -> Dictionary:
	return {
		"game": game_id,
		"install": install,
		"version": LGVersion.current(),
		"os": OS.get_name(),
		"distro": OS.get_distribution_name().left(128),
		"os_version": OS.get_version().left(64),
		"arch": Engine.get_architecture_name(),
	}


## This install's id: 32 random hex digits, made on the first run and kept.
static func install_id() -> String:
	var saved := FileAccess.get_file_as_string(ID_FILE).strip_edges()
	if is_install_id(saved):
		return saved
	var made := Crypto.new().generate_random_bytes(16).hex_encode()
	var f := FileAccess.open(ID_FILE, FileAccess.WRITE)
	if f:
		f.store_string(made)
	return made


static func is_install_id(id: String) -> bool:
	return id.length() == 32 and RegEx.create_from_string("^[0-9a-f]{32}$").search(id) != null

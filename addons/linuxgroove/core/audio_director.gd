extends Node
## Music and UI sound helper (autoload: LGAudio).
##
## Music cross-fades between two players on the "Music" bus. One-shot sounds
## use a small pool of players on the "SFX" bus. The buses come from
## `default_bus_layout.tres`; if a game has none they are created here.
##
## A game's pause menu calls [method pause_game] so the music and every sound
## in the game stop where they are while it's open.

const POOL_SIZE := 8
const FADE_TIME := 1.2
## The kinds of node whose sound [method pause_game] holds.
const PLAYERS := ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D"]

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current_music: AudioStreamPlayer
var _pool: Array[AudioStreamPlayer] = []
var _cache := {}
var _game_paused := false
## The players [method pause_game] paused, to pick up again.
var _held: Array[Node] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_bus("Music")
	_ensure_bus("SFX")
	_music_a = _make_player("Music")
	_music_b = _make_player("Music")
	for i in POOL_SIZE:
		_pool.append(_make_player("SFX"))


## Cross-fades to a track. Tracks loop unless `loop` is false (a sting or a
## jingle that should play once).
func play_music(stream_or_path: Variant, volume_db := 0.0, loop := true) -> void:
	var stream := _resolve(stream_or_path)
	if stream == null:
		return
	if _sounding(_current_music) and _current_music.stream == stream:
		return
	var next := _music_b if _current_music == _music_a else _music_a
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = loop
	next.stream = stream
	next.volume_db = -40.0
	next.play()
	var tween := create_tween().set_parallel()
	tween.tween_property(next, "volume_db", volume_db, FADE_TIME)
	if _sounding(_current_music):
		var old := _current_music
		tween.tween_property(old, "volume_db", -40.0, FADE_TIME)
		tween.chain().tween_callback(old.stop)
	_current_music = next


func stop_music() -> void:
	if _sounding(_current_music):
		var old := _current_music
		var tween := create_tween()
		tween.tween_property(old, "volume_db", -40.0, FADE_TIME)
		tween.tween_callback(old.stop)
	_current_music = null


## Plays a one-shot sound. `pitch_jitter` randomises pitch a little so
## repeated sounds (footsteps, clicks) don't sound mechanical.
func play_sfx(stream_or_path: Variant, volume_db := 0.0, pitch_jitter := 0.0) -> void:
	var stream := _resolve(stream_or_path)
	if stream == null:
		return
	var player := _free_player()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.play()


## Holds the music and every sound playing in the game where they are, or
## picks them up again. A pause menu calls it when the game really stops (not
## over a match that carries on for players on other devices). Sounds started
## while it holds, such as the menu's own, play as usual, and a scene change
## picks everything up again.
func pause_game(on: bool) -> void:
	if on == _game_paused:
		return
	_game_paused = on
	if on:
		for type in PLAYERS:
			for p in get_tree().root.find_children("*", type, true, false):
				if p.playing and not p.stream_paused:
					p.stream_paused = true
					_held.append(p)
		return
	for p in _held:
		# One the paused tree also stops starts again when the tree unpauses.
		if is_instance_valid(p) and p.is_inside_tree() and p.can_process():
			p.stream_paused = false
	_held.clear()


## Whether [method pause_game] is holding the game's sound.
func is_game_paused() -> bool:
	return _game_paused


## Playing, or held by [method pause_game] (a paused player isn't `playing`).
func _sounding(p: AudioStreamPlayer) -> bool:
	return p != null and (p.playing or p.stream_paused)


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not _sounding(p):
			return p
	return _pool[0]


func _resolve(stream_or_path: Variant) -> AudioStream:
	if stream_or_path is AudioStream:
		return stream_or_path
	if stream_or_path is String:
		var path: String = stream_or_path
		if not _cache.has(path):
			if not ResourceLoader.exists(path):
				push_warning("Audio: missing %s" % path)
				return null
			_cache[path] = load(path)
		return _cache[path]
	return null


func _make_player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, bus_name)
	AudioServer.set_bus_send(idx, "Master")

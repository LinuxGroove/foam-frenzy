class_name LGPlaytestCapture
extends RefCounted
## Small pictures of the game for a play test. A picture is taken every
## second and the last few are kept in memory; every third one is saved, and
## around marks and moments all of them are, so the seconds that matter play
## back smoothly while an hour still fits in a file small enough to send.
##
## On Forward+ and Mobile the picture is read back from the GPU without
## waiting for it, so taking one doesn't stutter the game. The Compatibility
## renderer has no way to do that and reads it directly.

## Width of a saved picture in pixels, and its JPEG quality.
const WIDTH := 640
const QUALITY := 0.6

var viewport: Viewport
var folder := ""
## Every nth picture is saved; the rest are kept only in the ring.
var save_every := 3
var ring_size := 12
## Pictures saved, and their bytes.
var saved := 0
var bytes := 0

var _ring: Array = []
var _count := 0
var _dense_until := -1
var _waiting := false
var _closed := false
var _tasks: Array[int] = []
var _mutex := Mutex.new()


func _init(p_viewport: Viewport, p_folder: String) -> void:
	viewport = p_viewport
	folder = p_folder


## Takes a picture, named by the session time `ms`. Does nothing while the
## last one is still on its way back from the GPU.
func grab(ms: int) -> void:
	if _closed or _waiting or viewport == null or DisplayServer.get_name() == "headless":
		return
	var tex := viewport.get_texture()
	if tex == null:
		return
	var rd := RenderingServer.get_rendering_device()
	if rd:
		var rid := RenderingServer.texture_get_rd_texture(tex.get_rid())
		if rid.is_valid():
			var fmt := rd.texture_get_format(rid)
			var image_format := image_format_for(fmt.format)
			if image_format >= 0:
				_waiting = true
				var err := rd.texture_get_data_async(rid, 0, _on_data.bind(ms, fmt.width, fmt.height, image_format))
				if err == OK:
					return
				_waiting = false
	var img := tex.get_image()
	if img:
		_prune()
		_tasks.append(WorkerThreadPool.add_task(_shrink.bind(ms, img)))


## Saves the pictures still in memory (the seconds before a mark or moment).
func keep_recent() -> void:
	if _closed:
		return
	_prune()
	_tasks.append(WorkerThreadPool.add_task(_save_ring))


## Saves every picture until the session time `ms`.
func dense_until(ms: int) -> void:
	_dense_until = maxi(_dense_until, ms)


## Waits for pictures still being saved. Pictures that arrive later are dropped.
func finish() -> void:
	_closed = true
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_ring.clear()


## The Image format for a GPU texture format, or -1 for ones read the slow way.
static func image_format_for(data_format: int) -> int:
	match data_format:
		RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM, RenderingDevice.DATA_FORMAT_R8G8B8A8_SRGB:
			return Image.FORMAT_RGBA8
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT:
			return Image.FORMAT_RGBAH
	return -1


## Called by the GPU readback, possibly from the render thread.
func _on_data(data: PackedByteArray, ms: int, w: int, h: int, image_format: int) -> void:
	_add_raw.call_deferred(data, ms, w, h, image_format)


func _add_raw(data: PackedByteArray, ms: int, w: int, h: int, image_format: int) -> void:
	_waiting = false
	if _closed:
		return
	_prune()
	_tasks.append(WorkerThreadPool.add_task(_from_data.bind(data, ms, w, h, image_format)))


func _from_data(data: PackedByteArray, ms: int, w: int, h: int, image_format: int) -> void:
	var px := 8 if image_format == Image.FORMAT_RGBAH else 4
	if data.size() < w * h * px:
		return
	var img := Image.create_from_data(w, h, false, image_format, data.slice(0, w * h * px))
	_shrink(ms, img)


## Runs on a worker thread: shrinks the picture, keeps it, and saves it if due.
func _shrink(ms: int, img: Image) -> void:
	if img.is_empty():
		return
	var hdr := img.get_format() == Image.FORMAT_RGBAH
	img.convert(Image.FORMAT_RGB8)
	if hdr:
		img.linear_to_srgb()
	var w := mini(WIDTH, img.get_width())
	img.resize(w, maxi(1, img.get_height() * w / img.get_width()), Image.INTERPOLATE_BILINEAR)
	var entry := {"ms": ms, "image": img, "saved": false}
	_mutex.lock()
	_count += 1
	_ring.append(entry)
	while _ring.size() > ring_size:
		_ring.pop_front()
	if _count % save_every == 1 or save_every <= 1 or ms <= _dense_until:
		_save(entry)
	_mutex.unlock()


func _save_ring() -> void:
	_mutex.lock()
	for entry in _ring:
		_save(entry)
	_mutex.unlock()


## Writes one picture. Call with the mutex held.
func _save(entry: Dictionary) -> void:
	if entry.saved:
		return
	entry.saved = true
	var buf: PackedByteArray = (entry.image as Image).save_jpg_to_buffer(QUALITY)
	var f := FileAccess.open(folder.path_join("%08d.jpg" % entry.ms), FileAccess.WRITE)
	if f:
		f.store_buffer(buf)
		saved += 1
		bytes += buf.size()


func _prune() -> void:
	var left: Array[int] = []
	for id in _tasks:
		if WorkerThreadPool.is_task_completed(id):
			WorkerThreadPool.wait_for_task_completion(id)
		else:
			left.append(id)
	_tasks = left

class_name PartyCamera
extends Camera3D
## One camera for everyone playing on this device. It looks down at the
## arena at a three-quarter angle and frames every local camper, pulling back
## as they spread apart. With one camper it leads a little towards their aim.

const PITCH := deg_to_rad(60.0)
const MIN_DISTANCE := 23.0
const MAX_DISTANCE := 50.0
const MARGIN := 5.0
const FOLLOW := 4.0

## Points to frame, refreshed by the game every frame.
var points: Array[Vector3] = []
var lead := Vector3.ZERO
var arena_size := Vector2(40, 30)

var _center := Vector3.ZERO
var _distance := MIN_DISTANCE
var _shake := 0.0
var _shake_t := 0.0


func _ready() -> void:
	fov = 42.0
	near = 0.5
	far = 200.0
	current = true


func snap_to(center: Vector3, distance := MIN_DISTANCE) -> void:
	_center = center
	_distance = distance
	_place(Vector3.ZERO)


## A small kick, for being hit or tagged out (Settings can turn it off).
func shake(amount: float) -> void:
	if bool(LGSettings.get_value("play", "shake", true)):
		_shake = maxf(_shake, amount)


func _process(delta: float) -> void:
	var goal_center := _center
	var goal_distance := _distance
	if not points.is_empty():
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in points:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		var mid := (lo + hi) * 0.5
		goal_center = Vector3(mid.x, 0.0, mid.y)
		if points.size() == 1:
			goal_center += lead
		var span := hi - lo + Vector2(MARGIN, MARGIN) * 2.0
		var aspect := get_viewport().get_visible_rect().size.aspect() if is_inside_tree() else 1.6
		var half_v := deg_to_rad(fov) * 0.5
		# Distance at which the span fits, both across and up the screen
		# (the ground is foreshortened by the pitch).
		var need_w := span.x * 0.5 / (tan(half_v) * aspect)
		var need_h := span.y * 0.5 * sin(PITCH) / tan(half_v)
		goal_distance = clampf(maxf(need_w, need_h), MIN_DISTANCE, MAX_DISTANCE)
	_center = _center.lerp(goal_center, minf(1.0, FOLLOW * delta))
	_distance = lerpf(_distance, goal_distance, minf(1.0, FOLLOW * 0.6 * delta))
	var offset := Vector3.ZERO
	if _shake > 0.01:
		_shake_t += delta * 40.0
		offset = Vector3(sin(_shake_t * 1.3), 0, cos(_shake_t * 1.7)) * _shake
		_shake = lerpf(_shake, 0.0, minf(1.0, 8.0 * delta))
	_place(offset)


func _place(offset: Vector3) -> void:
	var back := Vector3(0, sin(PITCH), cos(PITCH)) * _distance
	position = _center + back + offset
	look_at(_center + offset, Vector3.UP)


## Where a screen point lands on the floor plane at height y.
func ground_point(screen: Vector2, y := 0.0) -> Vector3:
	var from := project_ray_origin(screen)
	var dir := project_ray_normal(screen)
	if absf(dir.y) < 1e-4:
		return from
	var t := (y - from.y) / dir.y
	return from + dir * t

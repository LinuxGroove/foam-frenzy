class_name LGScreenFit
extends Node
## Shrinks a menu so every button stays on screen, however short the screen
## (handhelds with a tall menu, or a big "Text size"). Never grows it.
##
##   LGScreenFit.center(column)   a column inside a CenterContainer: scales
##                                around its middle
##   LGScreenFit.fill(root)       a full-screen layout: lays it out at a larger
##                                virtual size and scales it down to fit

enum Mode { CENTER, FILL }

const MIN_SCALE := 0.5

var target: Control
var mode := Mode.CENTER
var margin := Vector2(32, 48)
var scale := 1.0


static func center(control: Control, p_margin := Vector2(32, 48)) -> LGScreenFit:
	return _attach(control, Mode.CENTER, p_margin)


static func fill(control: Control) -> LGScreenFit:
	return _attach(control, Mode.FILL, Vector2.ZERO)


static func _attach(control: Control, p_mode: Mode, p_margin: Vector2) -> LGScreenFit:
	var fit := LGScreenFit.new()
	fit.name = "ScreenFit"
	fit.target = control
	fit.mode = p_mode
	fit.margin = p_margin
	# An internal child, so menus that clear their children keep it.
	control.add_child(fit, false, Node.INTERNAL_MODE_BACK)
	return fit


## The scale needed to show something of `need` size in `avail`, between
## MIN_SCALE and 1.
static func scale_for(need: Vector2, avail: Vector2) -> float:
	if need.x <= 0.0 or need.y <= 0.0:
		return 1.0
	return clampf(minf(avail.x / need.x, avail.y / need.y), MIN_SCALE, 1.0)


func _process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var view := target.get_viewport().get_visible_rect().size
	if mode == Mode.CENTER:
		# A container holding a menu taller than the screen grows past the
		# bottom edge unless it grows both ways, which would push the menu's
		# middle off centre.
		var holder := target.get_parent() as Control
		if holder and holder.grow_vertical != Control.GROW_DIRECTION_BOTH:
			holder.grow_horizontal = Control.GROW_DIRECTION_BOTH
			holder.grow_vertical = Control.GROW_DIRECTION_BOTH
		var s := scale_for(target.get_combined_minimum_size(), view - margin)
		if not is_equal_approx(target.scale.x, s):
			target.scale = Vector2(s, s)
		target.pivot_offset = target.size / 2.0
		scale = s
	else:
		# Lay out at the size the content needs (at least the screen), then
		# scale that down onto the screen.
		var need := target.get_combined_minimum_size()
		var s := scale_for(need, view)
		var virtual := view / s
		if not is_equal_approx(target.scale.x, s):
			target.scale = Vector2(s, s)
		if not target.size.is_equal_approx(virtual):
			target.set_deferred("size", virtual)
		target.position = Vector2.ZERO
		scale = s

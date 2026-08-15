extends "res://demos/shared/demo_base.gd"

## Crush test: drive a slab down onto the softbody, then lift it and see what comes back.
##
## This is the harsh case: a press pushes neighbours through each other, and jointed
## neighbours do not collide. Push far enough and part of the lattice can turn inside out.
## The inverted joints readout shows whether that happened; softness and shape joints
## decide how far the lattice gives.

const MAX_DEPTH := 0.95

var _softbody: SoftBody2D
var _press: AnimatableBody2D
var _softness := 60.0
var _reach := 2
var _rest_height := 1.0
var _rest_dirs := {}
var _press_top := 0.0
var _depth := 0.0
var _auto := 0.0
var _peak_fold := 0.0


func demo_title() -> String:
	return "6. Crush test"


func build() -> void:
	_peak_fold = 0.0
	_depth = 0.0
	_softbody = spawn_softbody(
		arena.get_center() + Vector2(0, 60),
		func(sb: SoftBody2D):
			sb.softness = _softness
			sb.joint_reach = _reach
			sb.gravity_scale = 1.0
			sb.can_sleep = false
	)

	_press = AnimatableBody2D.new()
	_press.sync_to_physics = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# Wider than the blob, so at full depth there is nowhere left to squeeze out to.
	rect.size = Vector2(1000, 60)
	shape.shape = rect
	_press.add_child(shape)
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-500, -30), Vector2(500, -30), Vector2(500, 30), Vector2(-500, 30)])
	visual.color = Color(0.85, 0.45, 0.35)
	_press.add_child(visual)
	world.add_child(_press)

	# Settle first, so rest height and rest joint directions describe the real resting shape.
	await get_tree().physics_frame
	for _i in 30:
		await get_tree().physics_frame
	_rest_height = maxf(_measure_height(), 1.0)
	_rest_dirs = _capture_joint_directions()
	_press_top = _measure_top() - 60.0
	_press.position = Vector2(_softbody.get_bones_center_position().x, _press_top)

	if controls.get_child_count() == 0:
		add_slider(
			"Crush (drag me down and back up)",
			0.0,
			1.0,
			0.0,
			func(v: float):
				_depth = v
				_auto = 0.0
		)
		add_slider(
			"Pin softness",
			0.0,
			100.0,
			_softness,
			func(v: float):
				_softness = v
				_softbody.softness = v,
			1.0
		)
		add_slider(
			"Joint reach in hops (rebuilds)",
			1.0,
			3.0,
			_reach,
			func(v: float):
				_reach = int(v)
				reset_demo(),
			1.0
		)
		add_shape_toggle()
		add_separator("Automatic")
		add_button("Gentle squash and release", func(): _auto = 1.0)
		add_button("Hard crush and release", func(): _auto = 2.0)
		add_separator()
		add_button("Reset (R)", reset_demo)
		add_readout(func(): return "height: %.0f%% of rest" % (100.0 * _measure_height() / _rest_height))
		add_readout(func(): return "shape error: %.1f px" % _shape_error())
		add_readout(
			func(): return "inverted joints: %.0f%%  (peak %.0f%%)" % [_fold_fraction() * 100.0, _peak_fold * 100.0]
		)
		add_readout(func(): return _verdict())


func _verdict() -> String:
	var fold := _fold_fraction()
	if _depth > 0.05 or _auto > 0.0:
		return "crushing..."
	if fold > 0.03:
		return "did NOT fully recover: lattice is inverted"
	if _shape_error() < vertex_hint():
		return "recovered"
	return "still settling"


func vertex_hint() -> float:
	return _softbody.vertex_interval * 0.25


## Travel available to the press. At full depth its underside rests on the floor, so the
## softbody is crushed with no gap left at all.
func _press_travel() -> float:
	const PRESS_HALF_HEIGHT := 30.0
	# Full travel would rest the slab on the floor with no gap at all, which squeezes bodies
	# out past the slab; 0.95 of it is a flat crush that still leaves the lattice a floor.
	return ((arena.end.y - PRESS_HALF_HEIGHT) - _press_top) * MAX_DEPTH


func _physics_process(delta: float) -> void:
	super(delta)
	if _softbody == null or not is_instance_valid(_softbody) or _press == null:
		return
	if _auto > 0.0:
		# Automatic cycle: down for a while, hold, then back up.
		var limit := 0.7 if _auto == 1.0 else 1.0
		_depth = move_toward(_depth, limit, delta * 0.6)
		if is_equal_approx(_depth, limit):
			_auto = -_auto
	elif _auto < 0.0:
		_depth = move_toward(_depth, 0.0, delta * 0.6)
		if _depth <= 0.0:
			_auto = 0.0
	_press.position.y = _press_top + _press_travel() * _depth
	_peak_fold = maxf(_peak_fold, _fold_fraction())


#region Measurements


func _measure_height() -> float:
	var lo := INF
	var hi := -INF
	for b in _softbody.get_rigid_bodies():
		lo = minf(lo, b.rigidbody.global_position.y)
		hi = maxf(hi, b.rigidbody.global_position.y)
	return hi - lo


func _measure_top() -> float:
	var lo := INF
	for b in _softbody.get_rigid_bodies():
		lo = minf(lo, b.rigidbody.global_position.y)
	return lo


func _capture_joint_directions() -> Dictionary:
	var out := {}
	for b in _softbody.get_rigid_bodies():
		for joint in b.joints:
			var target := joint.get_node_or_null(joint.node_b) as Node2D
			if target:
				out[joint.get_instance_id()] = (target.global_position - b.rigidbody.global_position).normalized()
	return out


func _fit_angle() -> float:
	var bodies := _softbody.get_rigid_bodies()
	if bodies.size() < 2:
		return 0.0
	var rest_centre := Vector2()
	var current_centre := Vector2()
	for b in bodies:
		rest_centre += b.rigidbody.get_meta("rest_position", b.rigidbody.position)
		current_centre += b.rigidbody.global_position
	rest_centre /= bodies.size()
	current_centre /= bodies.size()
	var sin_sum := 0.0
	var cos_sum := 0.0
	for b in bodies:
		var rest: Vector2 = b.rigidbody.get_meta("rest_position", b.rigidbody.position)
		sin_sum += (rest - rest_centre).cross(b.rigidbody.global_position - current_centre)
		cos_sum += (rest - rest_centre).dot(b.rigidbody.global_position - current_centre)
	return atan2(sin_sum, cos_sum)


## Share of joints now pointing more than 90 degrees away from their rest direction, once
## the softbody's own rotation is taken out. This is the lattice turning inside out.
func _fold_fraction() -> float:
	var angle := _fit_angle()
	var total := 0
	var inverted := 0
	for b in _softbody.get_rigid_bodies():
		for joint in b.joints:
			var target := joint.get_node_or_null(joint.node_b) as Node2D
			if target == null or not _rest_dirs.has(joint.get_instance_id()):
				continue
			total += 1
			var now := (target.global_position - b.rigidbody.global_position).normalized()
			if now.dot((_rest_dirs[joint.get_instance_id()] as Vector2).rotated(angle)) < 0.0:
				inverted += 1
	return float(inverted) / maxf(total, 1)


func _shape_error() -> float:
	var bodies := _softbody.get_rigid_bodies()
	if bodies.size() < 2:
		return 0.0
	var angle := _fit_angle()
	var rest_centre := Vector2()
	var current_centre := Vector2()
	for b in bodies:
		rest_centre += b.rigidbody.get_meta("rest_position", b.rigidbody.position)
		current_centre += b.rigidbody.global_position
	rest_centre /= bodies.size()
	current_centre /= bodies.size()
	var error := 0.0
	for b in bodies:
		var rest: Vector2 = b.rigidbody.get_meta("rest_position", b.rigidbody.position)
		error += (current_centre + (rest - rest_centre).rotated(angle)).distance_to(b.rigidbody.global_position)
	return error / bodies.size()

#endregion

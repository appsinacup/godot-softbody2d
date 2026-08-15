extends "res://demos/shared/demo_base.gd"

## Edge fit: how well the collision shapes stay inside the drawn softbody, and how much the
## outline swings at corners. Every slider rebuilds the softbody so the effect is visible.

# Teleporting bodies snaps back within a frame at joint reach 2, so the deformations are
# kicks: velocities that carry each body to its deformed spot over KICK_TIME seconds.
const KICK_TIME := 0.12

var _softbody: SoftBody2D
var _radius := 38.0
var _shape_type := "Circle"
var _clearance := -1.0
var _min_area := 0.08
var _reach := 2
var _smoothing := 0.5


func demo_title() -> String:
	return "7. Edge fit"


func build() -> void:
	_show_collision_shapes = true
	_softbody = spawn_softbody(
		arena.get_center() + Vector2(0, -60),
		func(sb: SoftBody2D):
			sb.shape_type = _shape_type
			sb.radius = _radius
			sb.edge_clearance = _clearance
			sb.min_area = _min_area
			sb.joint_reach = _reach
			sb.skin_smoothing = _smoothing
			sb.gravity_scale = 1.0
			sb.can_sleep = false
	)
	if controls.get_child_count() == 0:
		add_slider(
			"Particle size (radius)",
			14.0,
			46.0,
			_radius,
			func(v: float):
				_radius = v
				reset_demo(),
			1.0
		)
		add_toggle(
			"Circle shapes (off = squares)",
			_shape_type == "Circle",
			func(v: bool):
				_shape_type = "Circle" if v else "Rectangle"
				reset_demo()
		)
		add_slider(
			"Edge clearance (-1 = auto, 0 = off)",
			-1.0,
			30.0,
			_clearance,
			func(v: float):
				_clearance = v
				reset_demo(),
			1.0
		)
		add_slider(
			"Min region area (small = corners keep a body)",
			0.02,
			0.5,
			_min_area,
			func(v: float):
				_min_area = v
				reset_demo(),
			0.01
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
		add_slider(
			"Skin smoothing (rebuilds)",
			0.0,
			1.0,
			_smoothing,
			func(v: float):
				_smoothing = v
				reset_demo(),
			0.05
		)
		add_separator()
		add_button("Squash flat", func(): _deform(Vector2(1.0, 0.4)))
		add_button("Lean it over", func(): _shear(0.8))
		add_button("Reset (R)", reset_demo)
		add_readout(func(): return "bodies: %d" % _softbody.get_rigid_bodies().size())
		add_readout(func(): return "worst protrusion: %.1f px" % _worst_protrusion())
		add_readout(func(): return "worst hook: %.1f px" % _worst_hook())


func _deform(factor: Vector2) -> void:
	var centre := _softbody.get_bones_center_position()
	for child in _softbody.get_rigid_bodies():
		var body := child.rigidbody as RigidBody2D
		if body:
			var target := centre + (body.global_position - centre) * factor
			body.linear_velocity = (target - body.global_position) / KICK_TIME


func _shear(amount: float) -> void:
	var centre := _softbody.get_bones_center_position()
	for child in _softbody.get_rigid_bodies():
		var body := child.rigidbody as RigidBody2D
		if body:
			var offset := body.global_position - centre
			var target := centre + Vector2(offset.x + offset.y * amount, offset.y)
			body.linear_velocity = (target - body.global_position) / KICK_TIME


#region Measurements


## Outline vertices as the skeleton deforms them, in softbody local space, computed the way
## the renderer does: the four heaviest bones per vertex, normalised.
func _skinned_outline() -> PackedVector2Array:
	var skeleton: Skeleton2D = _softbody.get_node(_softbody.skeleton)
	var bone_xforms: Array[Transform2D] = []
	var weights: Array[PackedFloat32Array] = []
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone(i)
		bone_xforms.append(bone.transform * bone.rest.affine_inverse())
		weights.append(_softbody.get_bone_weights(i))
	var outline := PackedVector2Array()
	var outer_count := _softbody.polygon.size() - _softbody.internal_vertex_count
	for v in outer_count:
		var rest := _softbody.polygon[v]
		var ranked := []
		for b in bone_xforms.size():
			if v < weights[b].size() and weights[b][v] > 0.0:
				ranked.append([weights[b][v], b])
		ranked.sort_custom(func(a, c): return a[0] > c[0])
		var total := 0.0
		var pos := Vector2.ZERO
		for k in mini(4, ranked.size()):
			total += ranked[k][0]
		for k in mini(4, ranked.size()):
			pos += (ranked[k][0] / total) * (bone_xforms[ranked[k][1]] * rest)
		outline.append(pos if total > 0.0 else rest)
	return outline


func _worst_protrusion() -> float:
	if _softbody == null or not is_instance_valid(_softbody):
		return 0.0
	var outline := _skinned_outline()
	var worst := 0.0
	for child in _softbody.get_rigid_bodies():
		if child.shape == null or child.shape.shape == null:
			continue
		for p in _shape_outline(child.shape.shape, child.shape.global_transform):
			var local := _softbody.to_local(p)
			if not Geometry2D.is_point_in_polygon(local, outline):
				worst = maxf(worst, _distance_to_outline(local, outline))
	return worst


## How far an outline vertex has moved away from its nearest body compared to rest.
func _worst_hook() -> float:
	if _softbody == null or not is_instance_valid(_softbody):
		return 0.0
	var outline := _skinned_outline()
	var bodies := _softbody.get_rigid_bodies()
	var worst := 0.0
	for v in outline.size():
		var rest_nearest := INF
		var now_nearest := INF
		for b in bodies:
			var rest: Vector2 = b.rigidbody.get_meta("rest_position", b.rigidbody.position)
			rest_nearest = minf(rest_nearest, _softbody.polygon[v].distance_to(rest))
			now_nearest = minf(now_nearest, outline[v].distance_to(b.rigidbody.position))
		worst = maxf(worst, now_nearest - rest_nearest)
	return worst


func _shape_outline(shape: Shape2D, xform: Transform2D) -> Array[Vector2]:
	var points: Array[Vector2] = []
	if shape is RectangleShape2D:
		var half: Vector2 = (shape as RectangleShape2D).size * 0.5
		var corners := [
			Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)
		]
		for i in 4:
			var a: Vector2 = corners[i]
			var b: Vector2 = corners[(i + 1) % 4]
			for t in 4:
				points.append(xform * a.lerp(b, float(t) / 4.0))
	elif shape is CircleShape2D:
		var r: float = (shape as CircleShape2D).radius
		for t in 16:
			var a := TAU * t / 16.0
			points.append(xform * (Vector2(cos(a), sin(a)) * r))
	return points


func _distance_to_outline(p: Vector2, outline: PackedVector2Array) -> float:
	var best := INF
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best

#endregion

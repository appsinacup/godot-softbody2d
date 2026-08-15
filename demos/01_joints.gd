extends "res://demos/shared/demo_base.gd"

## Joints: what holds a softbody together. Pin softness is the squish, shape joints keep
## the overall shape inside the solver, angular limits bound how far neighbours may twist.

# Teleporting bodies snaps back within a frame at joint reach 2, so the deformations are
# kicks: velocities that carry each body to its deformed spot over KICK_TIME seconds.
const KICK_TIME := 0.12

var _softbody: SoftBody2D
var _softness := 60.0
var _reach := 2
var _limit := 0.0
var _yield := 0.0


func demo_title() -> String:
	return "1. Joints"


func build() -> void:
	_softbody = spawn_softbody(
		arena.get_center(),
		func(sb: SoftBody2D):
			sb.softness = _softness
			sb.joint_reach = _reach
			sb.angular_limit_enabled = _limit > 0.0
			sb.angular_limit_lower = -_limit
			sb.angular_limit_upper = _limit
			sb.yield_strain = _yield
			sb.gravity_scale = 1.0
			sb.can_sleep = false
	)
	_softbody.debug_draw |= SoftBody2D.DEBUG_DRAW_JOINTS
	if controls.get_child_count() == 0:
		add_slider(
			"Pin softness (squish)",
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
		add_slider(
			"Angular limit (degrees, 0 = off, rebuilds)",
			0.0,
			180.0,
			_limit,
			func(v: float):
				_limit = v
				reset_demo(),
			1.0
		)
		add_slider(
			"Yield strain (0 = elastic, else clay)",
			0.0,
			0.5,
			_yield,
			func(v: float):
				_yield = v
				_softbody.yield_strain = v,
			0.01
		)
		add_shape_toggle()
		add_separator("Deform it")
		add_button("Squash to 50%", func(): _deform(Vector2(0.5, 0.5)))
		add_button("Squash to 20%", func(): _deform(Vector2(0.2, 0.2)))
		add_button("Squash to 5%", func(): _deform(Vector2(0.05, 0.05)))
		add_button("Stretch to 200%", func(): _deform(Vector2(2.0, 2.0)))
		add_button("Stretch to 400%", func(): _deform(Vector2(4.0, 4.0)))
		add_button("Flatten to 35% height", func(): _deform(Vector2(1.0, 0.35)))
		add_button("Flatten to 10% height", func(): _deform(Vector2(1.0, 0.1)))
		add_button("Shear sideways", func(): _shear(0.6))
		add_button("Shear hard", func(): _shear(2.0))
		add_separator()
		add_button("Reset (R)", reset_demo)
		add_readout(func(): return "joints: %d" % total_joints())
		add_readout(func(): return "shape error: %.1f px" % _shape_error())


func _deform(factor: Vector2) -> void:
	var centre := _softbody.get_bones_center_position()
	for child in _softbody.get_rigid_bodies():
		var body := child.rigidbody as RigidBody2D
		if body == null:
			continue
		var target := centre + (body.global_position - centre) * factor
		body.linear_velocity = (target - body.global_position) / KICK_TIME
	set_status("Deformed.")


func _shear(amount: float) -> void:
	var centre := _softbody.get_bones_center_position()
	for child in _softbody.get_rigid_bodies():
		var body := child.rigidbody as RigidBody2D
		if body == null:
			continue
		var offset := body.global_position - centre
		var target := centre + Vector2(offset.x + offset.y * amount, offset.y)
		body.linear_velocity = (target - body.global_position) / KICK_TIME
	set_status("Sheared.")


## Mean distance between each body and where a rigid fit of the rest layout says it should be.
func _shape_error() -> float:
	var bodies := _softbody.get_rigid_bodies()
	if bodies.size() < 2:
		return 0.0
	var rest: Array[Vector2] = []
	var current: Array[Vector2] = []
	var rest_centre := Vector2()
	var current_centre := Vector2()
	for b in bodies:
		var r: Vector2 = b.rigidbody.get_meta("rest_position", b.rigidbody.position)
		rest.append(r)
		current.append(b.rigidbody.global_position)
		rest_centre += r
		current_centre += b.rigidbody.global_position
	rest_centre /= bodies.size()
	current_centre /= bodies.size()
	var sin_sum := 0.0
	var cos_sum := 0.0
	for i in bodies.size():
		sin_sum += (rest[i] - rest_centre).cross(current[i] - current_centre)
		cos_sum += (rest[i] - rest_centre).dot(current[i] - current_centre)
	var angle := atan2(sin_sum, cos_sum)
	var error := 0.0
	for i in bodies.size():
		error += (current_centre + (rest[i] - rest_centre).rotated(angle)).distance_to(current[i])
	return error / bodies.size()

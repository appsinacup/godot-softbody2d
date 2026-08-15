extends "res://demos/shared/demo_base.gd"

## Breaking: force based tearing with Rapier, compared against the distance fallback.

var _softbody: SoftBody2D
var _use_force := SoftBody2DPhysics.has_rapier()
# Measured peak joint load for this setup: dropping a weight peaks near 220, flinging it
# into a wall near 370, yanking it apart near 800, and an undisturbed blob sits at 0. A
# default of 150 tears on any of the three without breaking under its own weight.
var _break_force := 150.0
var _break_smoothing := 0.3
var _break_distance := 1.5
var _interior_strength := 4.0
var _start_joints := 0


func demo_title() -> String:
	return "2. Breaking"


func build() -> void:
	_softbody = spawn_softbody(
		arena.get_center() + Vector2(0, -120),
		func(sb: SoftBody2D):
			sb.mass = 0.15
			sb.can_sleep = false
			sb.max_breaks_per_step = 8
			_apply_break_settings(sb)
	)
	_start_joints = total_joints()
	set_status("")

	if controls.get_child_count() == 0:
		if SoftBody2DPhysics.has_rapier():
			add_toggle(
				"Force based (Rapier)",
				_use_force,
				func(v: bool):
					_use_force = v
					_apply_break_settings(_softbody)
					set_status("Mode: %s" % ("reaction force" if v else "stretch distance"))
			)
		add_slider(
			"Break force",
			20.0,
			1200.0,
			_break_force,
			func(v: float):
				_break_force = v
				_apply_break_settings(_softbody),
			10.0
		)
		add_slider(
			"Break smoothing (0 = snaps on one spike, 1 = needs sustained pull)",
			0.0,
			0.95,
			_break_smoothing,
			func(v: float):
				_break_smoothing = v
				_apply_break_settings(_softbody)
		)
		add_slider(
			"Break distance ratio",
			1.0,
			4.0,
			_break_distance,
			func(v: float):
				_break_distance = v
				_apply_break_settings(_softbody),
			0.1
		)
		add_slider(
			"Interior strength (tears start at the surface)",
			1.0,
			6.0,
			_interior_strength,
			func(v: float):
				_interior_strength = v
				_apply_break_settings(_softbody),
			0.5
		)
		add_shape_toggle()
		add_separator("Try to break it")
		add_button("Drop a weight", _drop_weight)
		add_button("Fling at the wall", _fling)
		add_button(
			"Yank it apart",
			func():
				var centre := _softbody.get_bones_center_position()
				for child in _softbody.get_rigid_bodies():
					var body := child.rigidbody as RigidBody2D
					if body:
						body.linear_velocity = (body.global_position - centre).normalized() * 2500.0
		)
		add_separator()
		add_button("Reset (R)", reset_demo)
		add_readout(func(): return "joints: %d of %d" % [total_joints(), _start_joints])
		add_readout(func(): return "pieces: %d" % _softbody.get_clusters().size())
		add_readout(func(): return "peak joint load: %.0f" % _peak_load())
		add_readout(
			func():
				return (
					"mode: %s"
					% ("reaction force" if _use_force and SoftBody2DPhysics.has_rapier() else "stretch distance")
				)
		)


func _apply_break_settings(sb: SoftBody2D) -> void:
	if sb == null:
		return
	sb.break_smoothing = _break_smoothing
	sb.break_force = _break_force
	sb.break_distance_ratio = _break_distance
	sb.interior_strength = _interior_strength
	# One mode is in charge at a time; the thresholds for the other are simply ignored.
	sb.break_mode = (
		SoftBody2D.BreakMode.FORCE if (_use_force and SoftBody2DPhysics.has_rapier()) else SoftBody2D.BreakMode.DISTANCE
	)


func _peak_load() -> float:
	if not SoftBody2DPhysics.has_rapier():
		return 0.0
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	var peak := 0.0
	for child in _softbody.get_rigid_bodies():
		for joint in child.joints:
			peak = maxf(peak, SoftBody2DPhysics.joint_reaction_impulse(joint).length() / delta)
	return peak


## Yanks the middle body away. With interior strength above 1 the joints around it hold
## until the tear has reached it from the surface; at 1 it rips straight out.
func _pull_centre() -> void:
	var centre := _softbody.get_center_body()
	var body := centre.rigidbody as RigidBody2D
	if body:
		body.linear_velocity = Vector2(0, -3000)
	set_status("Pulled the centre body.")


func _drop_weight() -> void:
	var weight := RigidBody2D.new()
	weight.mass = 12.0
	var shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(220, 60)
	shape.shape = rectangle
	weight.add_child(shape)
	var visual := Polygon2D.new()
	visual.polygon = PackedVector2Array([Vector2(-110, -30), Vector2(110, -30), Vector2(110, 30), Vector2(-110, 30)])
	visual.color = Color(0.85, 0.4, 0.35)
	weight.add_child(visual)
	weight.position = _softbody.get_bones_center_position() + Vector2(0, -320)
	world.add_child(weight)
	set_status("Dropped a weight.")


func _fling() -> void:
	for child in _softbody.get_rigid_bodies():
		var body := child.rigidbody as RigidBody2D
		if body:
			body.linear_velocity = Vector2(1800, -200)
	set_status("Flung it at the wall.")

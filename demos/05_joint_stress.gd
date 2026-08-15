extends "res://demos/shared/demo_base.gd"

## Stress view: SoftBody2D.debug_draw colours every joint by the force the solver applies
## to hold it. This is the signal force based breaking uses, made visible.

var _softbody: SoftBody2D


func demo_title() -> String:
	return "5. Joint stress"


func build() -> void:
	_softbody = spawn_softbody(
		arena.get_center(),
		func(sb: SoftBody2D):
			sb.gravity_scale = 1.0
			sb.can_sleep = false
			sb.mass = 0.2
	)
	_softbody.debug_draw |= SoftBody2D.DEBUG_DRAW_JOINTS
	if controls.get_child_count() == 0:
		add_shape_toggle()
		add_separator()
		add_button("Hang it from the ceiling", _pin_top)
		add_button("Reset (R)", reset_demo)
		add_readout(func(): return "peak load: %.0f" % _peak_load())
		add_readout(func(): return "mean load: %.0f" % _mean_load())
	if not SoftBody2DPhysics.has_rapier():
		set_status("Without Rapier the reaction force is unavailable, so joints are coloured by stretch.")


## Freeze the topmost bodies so the rest of the blob hangs off them under gravity, which
## puts a clear, steady load gradient through the lattice.
func _pin_top() -> void:
	var bodies := _softbody.get_rigid_bodies()
	if bodies.is_empty():
		return
	var top := INF
	for b in bodies:
		top = minf(top, b.rigidbody.global_position.y)
	for b in bodies:
		if b.rigidbody.global_position.y < top + 30.0 and b.rigidbody is RigidBody2D:
			(b.rigidbody as RigidBody2D).freeze = true
	set_status("Top row pinned. Load is highest where the weight hangs from.")


func _joint_force(joint: Joint2D) -> float:
	if not SoftBody2DPhysics.has_rapier():
		return -1.0
	return SoftBody2DPhysics.joint_reaction_impulse(joint).length() * float(Engine.physics_ticks_per_second)


func _peak_load() -> float:
	var peak := 0.0
	for b in _softbody.get_rigid_bodies():
		for joint in b.joints:
			peak = maxf(peak, _joint_force(joint))
	return peak


func _mean_load() -> float:
	var total := 0.0
	var count := 0
	for b in _softbody.get_rigid_bodies():
		for joint in b.joints:
			total += maxf(_joint_force(joint), 0.0)
			count += 1
	return total / maxf(count, 1)

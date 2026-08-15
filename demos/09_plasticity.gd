extends "res://demos/shared/demo_base.gd"

## Plasticity: the same blob twice, elastic on the left and clay on the right. Squash both
## and watch one spring back and the other keep the dent; stretching springs back on both.

const KICK_TIME := 0.12

var _elastic: SoftBody2D
var _clay: SoftBody2D
var _yield := 0.05
var _yield_limit := 0.3
var _softness := 60.0


func demo_title() -> String:
	return "9. Plasticity"


func build() -> void:
	_elastic = spawn_softbody(
		arena.get_center() + Vector2(-300, 0),
		func(sb: SoftBody2D):
			sb.softness = _softness
			sb.gravity_scale = 1.0
			sb.can_sleep = false
	)
	_clay = spawn_softbody(
		arena.get_center() + Vector2(300, 0),
		func(sb: SoftBody2D):
			sb.softness = _softness
			sb.yield_strain = _yield
			sb.gravity_scale = 1.0
			sb.can_sleep = false
	)
	_label(_elastic, "elastic")
	_label(_clay, "clay, yield strain %.2f" % _yield)
	if controls.get_child_count() == 0:
		add_slider(
			"Yield strain (right blob)",
			0.01,
			0.5,
			_yield,
			func(v: float):
				_yield = v
				_clay.yield_strain = v,
			0.01
		)
		add_slider(
			"Yield limit (most permanent stretch)",
			0.05,
			1.0,
			_yield_limit,
			func(v: float):
				_yield_limit = v
				_clay.yield_limit = v,
			0.05
		)
		add_slider(
			"Pin softness (both)",
			0.0,
			100.0,
			_softness,
			func(v: float):
				_softness = v
				_elastic.softness = v
				_clay.softness = v,
			1.0
		)
		add_shape_toggle()
		add_separator("Deform both")
		add_button("Squash to 40%", func(): _deform_both(Vector2(1.0, 0.4)))
		add_button("Squash to 15%", func(): _deform_both(Vector2(1.0, 0.15)))
		add_button("Stretch to 250% (springs back on both)", func(): _deform_both(Vector2(1.0, 2.5)))
		add_button("Squeeze sideways to 40%", func(): _deform_both(Vector2(0.4, 1.0)))
		add_button("Drop a weight on both", _drop_weights)
		add_separator()
		add_button("Reset (R)", reset_demo)
		add_readout(
			func():
				return (
					"height: elastic %.0f%%, clay %.0f%% of rest"
					% [_height_ratio(_elastic) * 100.0, _height_ratio(_clay) * 100.0]
				)
		)


func _label(sb: SoftBody2D, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = sb.get_bones_center_position() + Vector2(-70, -200)
	world.add_child(label)


func _deform_both(factor: Vector2) -> void:
	var both: Array[SoftBody2D] = [_elastic, _clay]
	for sb in both:
		var centre := sb.get_bones_center_position()
		for child in sb.get_rigid_bodies():
			var body := child.rigidbody as RigidBody2D
			if body:
				var target := centre + (body.global_position - centre) * factor
				body.linear_velocity = (target - body.global_position) / KICK_TIME


func _drop_weights() -> void:
	var both: Array[SoftBody2D] = [_elastic, _clay]
	for sb in both:
		var weight := RigidBody2D.new()
		weight.mass = 12.0
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = Vector2(220, 60)
		shape.shape = rectangle
		weight.add_child(shape)
		var visual := Polygon2D.new()
		visual.polygon = PackedVector2Array(
			[Vector2(-110, -30), Vector2(110, -30), Vector2(110, 30), Vector2(-110, 30)]
		)
		visual.color = Color(0.85, 0.4, 0.35)
		weight.add_child(visual)
		weight.position = sb.get_bones_center_position() + Vector2(0, -320)
		world.add_child(weight)


func _height_ratio(sb: SoftBody2D) -> float:
	if sb == null or not is_instance_valid(sb):
		return 0.0
	var lo := INF
	var hi := -INF
	var rest_lo := INF
	var rest_hi := -INF
	for child in sb.get_rigid_bodies():
		lo = minf(lo, child.rigidbody.global_position.y)
		hi = maxf(hi, child.rigidbody.global_position.y)
		var rest: Vector2 = child.rigidbody.get_meta("rest_position", child.rigidbody.position)
		rest_lo = minf(rest_lo, rest.y)
		rest_hi = maxf(rest_hi, rest.y)
	return (hi - lo) / maxf(rest_hi - rest_lo, 1.0)

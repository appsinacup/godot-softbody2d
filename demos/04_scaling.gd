extends "res://demos/shared/demo_base.gd"

## Scaling: bake_scale resizes the generated geometry, so physics matches what is drawn.

const SCALES := [0.6, 1.0, 1.6]
## How far above the floor every blob is released, measured from its lowest point.
const DROP_HEIGHT := 300.0

var _drop_frame := 0
var _landed := {}


func demo_title() -> String:
	return "4. Scaling"


func _init() -> void:
	# Wider than the default arena so the largest blob has room beside the others.
	arena = Rect2(-900, -500, 1800, 1000)


func build() -> void:
	_landed.clear()
	_drop_frame = 0
	var spacing := arena.size.x / (SCALES.size() + 1)
	for i in SCALES.size():
		var factor: float = SCALES[i]
		var x := arena.position.x + spacing * (i + 1)
		var sb := spawn_softbody(
			Vector2(x, arena.get_center().y), func(body: SoftBody2D): body.bake_scale = Vector2(factor, factor)
		)
		# Line the blobs up by their lowest point, measured rather than guessed. Aligning
		# their centres instead would start the biggest one closest to the floor, so it
		# would land first and look like it had fallen faster.
		_align_bottom(sb, arena.end.y - DROP_HEIGHT)
		var caption := Label.new()
		caption.text = "bake_scale %.1f\n%d bodies" % [factor, sb.get_rigid_bodies().size()]
		caption.position = Vector2(x - 60, arena.position.y + 24)
		world.add_child(caption)

	if controls.get_child_count() == 0:
		add_shape_toggle()
		add_readout(func(): return _drop_report())
		add_separator()
		add_button(
			"Poke them all",
			func():
				for sb in _softbodies():
					sb.apply_impulse_at_point(Vector2(0, -260), sb.get_bones_center_position())
		)
		add_button("Drop them again (R)", reset_demo)


## Shift a softbody so its lowest body sits at [param bottom_y].
func _align_bottom(sb: SoftBody2D, bottom_y: float) -> void:
	var lowest := -INF
	for child in sb.get_rigid_bodies():
		lowest = maxf(lowest, child.rigidbody.global_position.y)
	if lowest == -INF:
		return
	sb.position.y += bottom_y - lowest


## Record which frame each blob first touches down, so the claim that they fall at the same
## rate is visible rather than something you have to take on trust.
func _physics_process(delta: float) -> void:
	super(delta)
	_drop_frame += 1
	for sb in _softbodies():
		if _landed.has(sb):
			continue
		for child in sb.get_rigid_bodies():
			if child.rigidbody.global_position.y > arena.end.y - 60.0:
				_landed[sb] = _drop_frame
				break


func _drop_report() -> String:
	var parts := PackedStringArray()
	var index := 0
	for sb in _softbodies():
		var factor: float = SCALES[index] if index < SCALES.size() else 1.0
		if _landed.has(sb):
			parts.append(
				"%.1f: landed at %.2fs" % [factor, float(_landed[sb]) / float(Engine.physics_ticks_per_second)]
			)
		else:
			parts.append("%.1f: falling" % factor)
		index += 1
	return "\n".join(parts)

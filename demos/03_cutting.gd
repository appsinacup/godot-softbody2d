extends "res://demos/shared/demo_base.gd"

## Cutting: drag a line across the softbody to slice it with SoftBody2D.cut().

var _softbody: SoftBody2D
var _slice_start := Vector2.ZERO
var _slicing := false
var _last_cut := 0


func demo_title() -> String:
	return "3. Cutting"


func build() -> void:
	_softbody = spawn_softbody(
		arena.get_center(),
		func(sb: SoftBody2D):
			sb.gravity_scale = 0.4
			sb.can_sleep = false
	)
	_last_cut = 0
	set_status("")

	if controls.get_child_count() == 0:
		add_button("Cut horizontally", func(): _cut_through(Vector2.RIGHT))
		add_button("Cut vertically", func(): _cut_through(Vector2.DOWN))
		add_button("Cut diagonally", func(): _cut_through(Vector2(1, 1).normalized()))
		add_separator()
		add_shape_toggle()
		add_button("Reset (R)", reset_demo)
		add_readout(func(): return "pieces: %d" % _softbody.get_clusters().size())
		add_readout(func(): return "joints: %d" % total_joints())
		overlay.draw.connect(_draw_overlay)


func _cut_through(direction: Vector2) -> void:
	var centre := _softbody.get_bones_center_position()
	_last_cut = _softbody.cut(centre - direction * 2000.0, centre + direction * 2000.0)
	set_status("Cut %d joints into %d pieces." % [_last_cut, _softbody.get_clusters().size()])


func _unhandled_input(event: InputEvent) -> void:
	super(event)
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		if (event as InputEventMouseButton).pressed:
			_slice_start = get_global_mouse_position()
			_slicing = true
		elif _slicing:
			_slicing = false
			_last_cut = _softbody.cut(_slice_start, get_global_mouse_position())
			set_status("Cut %d joints into %d pieces." % [_last_cut, _softbody.get_clusters().size()])


func _draw_overlay() -> void:
	if _slicing:
		overlay.draw_line(_slice_start, get_global_mouse_position(), Color(1.0, 0.4, 0.3), 3.0)
		overlay.draw_circle(_slice_start, 5.0, Color(1.0, 0.4, 0.3))

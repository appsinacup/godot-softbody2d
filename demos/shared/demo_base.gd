extends Node2D

## Shared scaffolding for the SoftBody2D demos.
##
## Builds the arena, camera, side panel and mouse grabbing, so each demo only has to
## describe its own contents. Extend this and override [method demo_title] and
## [method build].

const HUB_SCENE := "res://demos/demo_hub.tscn"
const DEFAULT_TEXTURE := "res://samples/softbody2d/softbody2d_full.png"

## Inner area the softbodies live in. Walls are built around it.
var arena := Rect2(-620, -380, 1240, 760)
## Everything a demo spawns goes here, so resetting is just clearing this node.
var world: Node2D
## Put demo specific sliders and buttons in here.
var controls: VBoxContainer
## Node2D whose `draw` signal demos can connect to for overlays. Drawn above everything.
var overlay: Node2D

var _grabbed: RigidBody2D
var _grab_strength := 220.0
var _readouts: Array[Dictionary] = []
var _status: Label
var _show_collision_shapes := false

#region Overridable by each demo


func demo_title() -> String:
	return "SoftBody2D"


## Build the contents of the demo. Everything spawned should be parented to [member world].
func build() -> void:
	pass


#endregion


func _ready() -> void:
	_build_arena()
	_build_camera()
	_build_ui()
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	overlay = Node2D.new()
	overlay.name = "Overlay"
	overlay.z_index = 100
	add_child(overlay)
	build()


## Toggle for the softbody's own collision shape overlay. Every demo gets it.
func add_shape_toggle() -> void:
	add_toggle(
		"Show collision shapes",
		_show_collision_shapes,
		func(v: bool):
			_show_collision_shapes = v
			for sb in _softbodies():
				_apply_debug_draw(sb)
	)


func _apply_debug_draw(sb: SoftBody2D) -> void:
	if _show_collision_shapes:
		sb.debug_draw |= SoftBody2D.DEBUG_DRAW_SHAPES
	else:
		sb.debug_draw &= ~SoftBody2D.DEBUG_DRAW_SHAPES


## Clear everything the demo spawned and build it again.
func reset_demo() -> void:
	_grabbed = null
	for child in world.get_children():
		world.remove_child(child)
		child.queue_free()
	build()
	overlay.queue_redraw()


#region Spawning


## Create a softbody at [param position]. [param configure] receives the SoftBody2D before
## it is generated, so properties that need a rebuild can be set there.
func spawn_softbody(position: Vector2, configure := Callable(), texture_path := DEFAULT_TEXTURE) -> SoftBody2D:
	var sb := SoftBody2D.new()
	sb.texture = load(texture_path)
	sb.vertex_interval = 40
	sb.radius = 38
	sb.mass = 0.1
	sb.linear_damp = 0.5
	if configure.is_valid():
		configure.call(sb)
	world.add_child(sb)
	sb.create_softbody2d(true)
	_apply_debug_draw(sb)
	# Generation lays the body out from the texture's top left corner, so centre it on the
	# requested position rather than offsetting by a guess.
	sb.position = position - _softbody_extent_centre(sb)
	return sb


func _softbody_extent_centre(sb: SoftBody2D) -> Vector2:
	var bodies := sb.get_rigid_bodies()
	if bodies.is_empty():
		return Vector2.ZERO
	var lim_min := Vector2.INF
	var lim_max := -Vector2.INF
	for b in bodies:
		lim_min = lim_min.min(b.rigidbody.position)
		lim_max = lim_max.max(b.rigidbody.position)
	return lim_min + (lim_max - lim_min) * 0.5


## Total joints across every softbody in the demo.
func total_joints() -> int:
	var n := 0
	for sb in _softbodies():
		for b in sb.get_rigid_bodies():
			n += b.joints.size()
	return n


func _softbodies() -> Array[SoftBody2D]:
	var result: Array[SoftBody2D] = []
	for child in world.get_children():
		if child is SoftBody2D:
			result.append(child)
	return result


#endregion

#region UI helpers


## Add a labelled slider. [param on_change] receives the new value.
func add_slider(
	label: String, min_value: float, max_value: float, value: float, on_change: Callable, step := 0.01
) -> HSlider:
	var caption := Label.new()
	caption.text = "%s: %s" % [label, _format(value)]
	controls.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(220, 0)
	slider.value_changed.connect(
		func(v: float):
			caption.text = "%s: %s" % [label, _format(v)]
			on_change.call(v)
	)
	controls.add_child(slider)
	return slider


func add_button(text: String, on_press: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_press)
	controls.add_child(button)
	return button


func add_toggle(text: String, pressed: bool, on_toggle: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = pressed
	box.toggled.connect(func(v: bool): on_toggle.call(v))
	controls.add_child(box)
	return box


## Add a line of live text. [param provider] is called every frame and returns the text.
func add_readout(provider: Callable) -> Label:
	var label := Label.new()
	label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	controls.add_child(label)
	_readouts.append({"label": label, "provider": provider})
	return label


func add_separator(text := "") -> void:
	controls.add_child(HSeparator.new())
	if text != "":
		var label := Label.new()
		label.text = text
		label.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8))
		controls.add_child(label)


func set_status(text: String) -> void:
	if _status:
		_status.text = text


func _format(value: float) -> String:
	return "%.2f" % value if absf(value) < 10.0 else "%.0f" % value


#endregion

#region Scaffolding


func _build_camera() -> void:
	var camera := Camera2D.new()
	camera.position = arena.get_center()
	add_child(camera)
	camera.make_current()


func _build_arena() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Arena"
	add_child(walls)
	var thickness := 40.0
	var sides := {
		"Floor": Rect2(arena.position.x, arena.end.y, arena.size.x, thickness),
		"Ceiling": Rect2(arena.position.x, arena.position.y - thickness, arena.size.x, thickness),
		"Left": Rect2(arena.position.x - thickness, arena.position.y, thickness, arena.size.y),
		"Right": Rect2(arena.end.x, arena.position.y, thickness, arena.size.y),
	}
	for side_name in sides:
		var rect: Rect2 = sides[side_name]
		var shape := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = rect.size
		shape.shape = rectangle
		shape.position = rect.get_center()
		shape.name = side_name
		walls.add_child(shape)
		var visual := Polygon2D.new()
		visual.polygon = PackedVector2Array(
			[rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
		)
		visual.color = Color(0.22, 0.24, 0.30)
		add_child(visual)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(280, 0)
	layer.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var title := Label.new()
	title.text = demo_title()
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)

	if not SoftBody2DPhysics.has_rapier():
		var warning := Label.new()
		warning.text = "Rapier not installed. Force based features are unavailable."
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.custom_minimum_size = Vector2(250, 0)
		warning.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		column.add_child(warning)

	column.add_child(HSeparator.new())

	controls = VBoxContainer.new()
	controls.add_theme_constant_override("separation", 4)
	column.add_child(controls)

	column.add_child(HSeparator.new())

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(250, 0)
	_status.add_theme_color_override("font_color", Color(0.65, 0.9, 0.65))
	column.add_child(_status)

	var back := Button.new()
	back.text = "Back to menu"
	back.pressed.connect(_go_back)
	column.add_child(back)


func _go_back() -> void:
	get_tree().change_scene_to_file(HUB_SCENE)


#endregion

#region Interaction


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_ESCAPE:
				_go_back()
			KEY_R:
				reset_demo()
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		if (event as InputEventMouseButton).pressed:
			_grabbed = _nearest_body(get_global_mouse_position())
		else:
			_grabbed = null


## Nearest softbody particle to a point, ignoring anything too far away to be a deliberate grab.
func _nearest_body(point: Vector2) -> RigidBody2D:
	var best: RigidBody2D = null
	var best_distance := 90.0
	for sb in _softbodies():
		for child in sb.get_rigid_bodies():
			var body := child.rigidbody as RigidBody2D
			if body == null or body.freeze:
				continue
			var distance := body.global_position.distance_to(point)
			if distance < best_distance:
				best_distance = distance
				best = body
	return best


func _physics_process(_delta: float) -> void:
	if _grabbed != null and is_instance_valid(_grabbed):
		var to_mouse := get_global_mouse_position() - _grabbed.global_position
		_grabbed.apply_central_force((to_mouse * _grab_strength - _grabbed.linear_velocity * 12.0) * _grabbed.mass)


func _process(_delta: float) -> void:
	for readout in _readouts:
		(readout["label"] as Label).text = str((readout["provider"] as Callable).call())
	if overlay:
		overlay.queue_redraw()

#endregion

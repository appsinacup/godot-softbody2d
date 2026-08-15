extends Control

## Menu for the SoftBody2D demos. Run this scene to browse them.

const DEMOS := [
	{"scene": "res://demos/01_joints.tscn", "title": "1. Joints"},
	{"scene": "res://demos/02_breaking.tscn", "title": "2. Breaking"},
	{"scene": "res://demos/03_cutting.tscn", "title": "3. Cutting"},
	{"scene": "res://demos/04_scaling.tscn", "title": "4. Scaling"},
	{"scene": "res://demos/05_joint_stress.tscn", "title": "5. Joint stress"},
	{"scene": "res://demos/06_crush.tscn", "title": "6. Crush test"},
	{"scene": "res://demos/07_edge_fit.tscn", "title": "7. Edge fit"},
	{"scene": "res://demos/08_benchmark.tscn", "title": "8. Benchmark"},
	{"scene": "res://demos/09_plasticity.tscn", "title": "9. Plasticity"},
]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = Color(0.11, 0.12, 0.15)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(620, 0)
	centre.add_child(column)

	var title := Label.new()
	title.text = "SoftBody2D demos"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = (
		"Physics engine: %s        Rapier: %s"
		% [
			ProjectSettings.get_setting("physics/2d/physics_engine", "DEFAULT"),
			"yes" if SoftBody2DPhysics.has_rapier() else "no"
		]
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	column.add_child(subtitle)

	if not SoftBody2DPhysics.has_rapier():
		var warning := Label.new()
		warning.text = "Rapier is not installed, so the force based demos fall back to stretch distance."
		warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		warning.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
		column.add_child(warning)

	column.add_child(HSeparator.new())

	for demo in DEMOS:
		var button := Button.new()
		button.text = demo["title"]
		button.custom_minimum_size = Vector2(0, 38)
		var target: String = demo["scene"]
		button.pressed.connect(func(): get_tree().change_scene_to_file(target))
		column.add_child(button)

	column.add_child(HSeparator.new())

	var footer := Label.new()
	footer.text = "Inside a demo: drag with the left mouse button to pull the blob, R to reset, Esc to come back here."
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	footer.add_theme_color_override("font_color", Color(0.55, 0.57, 0.62))
	column.add_child(footer)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	column.add_child(quit)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_tree().quit()

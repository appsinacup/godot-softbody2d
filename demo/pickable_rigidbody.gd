@tool
extends SoftBody2DRigidBody

var SPEED : float = 200

static var selected_node: SoftBody2DRigidBody = null
static var hovering: Array[SoftBody2DRigidBody] = []

func _draw():
	if hovering && hovering.has(self):
		draw_circle(Vector2(), 10, Color.WHITE)
	if selected_node == self:
		var dir = (get_global_mouse_position() - global_position).normalized()
		draw_line(Vector2(0,0), dir * 50, Color.WHITE, 10)

func _on_mouse_entered():
	hovering.append(self)

func _on_mouse_exited():
	hovering.erase(self)

func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _process(delta):
	if selected_node == null && Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) && hovering && hovering.has(self):
		selected_node = hovering[0]
	if !Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		selected_node = null
	queue_redraw()
	if selected_node == self:
		var dir = (get_global_mouse_position() - global_position - linear_velocity * delta)
		var length = dir.length()
		dir /= length
		length /= mass
		if length > SPEED:
			length = SPEED;
		if length < 1:
			length = 1;
		apply_central_impulse(dir * length)

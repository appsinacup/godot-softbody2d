extends RigidBody2D

@onready var pin1 : PinJoint2D = $PinJoint2D
@onready var pin2 : PinJoint2D = $PinJoint2D2

const SPEED = 6000

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	var direction := Input.get_axis("ui_left", "ui_right")
	if direction:
		pin1.motor_enabled = true
		pin2.motor_enabled = true
		pin1.motor_target_velocity = -direction * SPEED
		pin2.motor_target_velocity = -direction * SPEED
	else:
		pin1.motor_enabled = false
		pin2.motor_enabled = false

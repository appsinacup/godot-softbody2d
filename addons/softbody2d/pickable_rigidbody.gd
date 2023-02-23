extends RigidBody2D

var is_mouse_inside := false
@onready var hinges := get_children().filter(func(node): return node is DampedSpringJoint2D)
@onready var rigidbodies := get_parent().get_children().filter(func(node): return node is RigidBody2D)
var hinges_bodies: Dictionary

func _ready():
	mouse_entered.connect(_mouse_entered)
	mouse_exited.connect(_mouse_exited)
	for hinge in hinges:
		var joint := hinge as DampedSpringJoint2D
		hinges_bodies[joint.node_a] = get_node(joint.node_a.get_concatenated_names().substr(1)) as RigidBody2D
		hinges_bodies[joint.node_b] = get_node(joint.node_b.get_concatenated_names().substr(1)) as RigidBody2D

func _mouse_entered():
	is_mouse_inside = true
	
func _mouse_exited():
	is_mouse_inside = false
	SoftBody2D

func is_hinge_broken(joint: DampedSpringJoint2D):
	return joint.length * 1.7 < hinges_bodies[joint.node_a].position.distance_to(hinges_bodies[joint.node_b].position)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	var to_remove = []
	for hinge in hinges:
		if is_hinge_broken(hinge as DampedSpringJoint2D):
			to_remove.append(hinge)
			print(get_parent().get_parent().name)
	for hinge in to_remove:
		hinges.erase(hinge)
		hinge.queue_free()
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and is_mouse_inside:
		var diff = get_global_mouse_position() - global_position
		for rb in rigidbodies:
			(rb as RigidBody2D).global_position += diff
			(rb as RigidBody2D).linear_velocity = Vector2()

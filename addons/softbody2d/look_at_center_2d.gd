class_name LookAtCenter2D
extends Bone2D

@export var follow: NodePath

# follow has to be a valid node
func _physics_process(delta):
	assert(!follow.is_empty())
	look_at(get_node(follow).global_position)

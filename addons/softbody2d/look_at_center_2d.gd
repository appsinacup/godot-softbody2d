class_name LookAtCenter2D
extends Bone2D

@export var follow: NodePath

func _physics_process(delta):
	look_at(get_node(follow).global_position)

class_name LookAtCenter2D
extends Bone2D

@export var follow: NodePath
var active := true

# follow has to be a valid node
func _physics_process(delta):
	if !active:
		return
	if get_node(follow) == null:
		active = false
		return
	look_at(get_node(follow).global_position)

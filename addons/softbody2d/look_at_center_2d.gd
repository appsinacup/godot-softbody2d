class_name LookAtCenter2D
extends Bone2D

@export var follow: NodePath
var follow_node: Node
var active := true

# follow has to be a valid node
func _physics_process(delta):
	if not active:
		return
	if follow_node == null:
		follow_node = get_node_or_null(follow)
		if follow_node == null:
			active = false
	if follow_node != null:
		look_at(follow_node.global_position)

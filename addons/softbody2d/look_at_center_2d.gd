class_name LookAtCenter2D
extends Bone2D

@export var follow: Array[NodePath]
var _follow_nodes: Array[Node]
@export var active := true

func look_at_nodes():
	_follow_nodes = []
	for to_follow in follow:
		_follow_nodes.append(get_node_or_null(to_follow))
	if _follow_nodes.size() == 0:
		active = false

# follow has to be a valid node
func _physics_process(delta):
	if not active:
		return
	if _follow_nodes.size() == 0:
		look_at_nodes()
	var follow_dir = Vector2()
	for to_follow in _follow_nodes:
		follow_dir += to_follow.global_position
	look_at(follow_dir/_follow_nodes.size())

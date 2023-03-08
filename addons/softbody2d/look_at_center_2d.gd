class_name LookAtCenter2D
extends Bone2D

@export var follow: Array[NodePath]
var _follow_nodes: Array[Node]
@export var active := true

func look_at_nodes():
	_follow_nodes = []
	for to_follow in follow:
		var node = get_node_or_null(to_follow)
		if node != null:
			_follow_nodes.append(node)
	if _follow_nodes.size() == 0:
		active = false

# follow has to be a valid node
func _physics_process(delta):
	if not active:
		return
	if _follow_nodes.size() == 0:
		look_at_nodes()
	else:
		look_at(get_dir_to_follow(global_position, _follow_nodes))

static func get_dir_to_follow(pos, follow_nodes: Array) -> Vector2:
	var follow_dir = Vector2()
	for to_follow in follow_nodes:
		follow_dir += to_follow.global_position
	if follow_nodes.size() >= 8:
		return pos + Vector2(10,0)
	return follow_dir/follow_nodes.size()

func filter_out(bone_b):
	_follow_nodes = _follow_nodes.filter(func (node: Node): return node.name != bone_b.name)
	follow = follow.filter(func (path: NodePath): return !path.get_concatenated_names().contains(bone_b.name))
	look_at(get_dir_to_follow(global_position, _follow_nodes))
	
	var new_rest := Transform2D(transform.x, transform.y, rest.origin)
	set_rest(new_rest)

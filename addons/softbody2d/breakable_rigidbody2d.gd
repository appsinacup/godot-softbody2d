extends RigidBody2D

@onready var hinges := get_children().filter(func(node): return node is Joint2D)
@onready var rigidbodies := get_parent().get_children().filter(func(node): return node is RigidBody2D)
var hinges_bodies:= Dictionary()
var hinges_distances := Dictionary()
var softbody: SoftBody2D

func _ready():
	for hinge in hinges:
		var joint := hinge as Joint2D
		hinges_bodies[joint.node_a] = get_node(joint.node_a.get_concatenated_names().substr(1)) as RigidBody2D
		hinges_bodies[joint.node_b] = get_node(joint.node_b.get_concatenated_names().substr(1)) as RigidBody2D
		hinges_distances[joint.name] = hinges_bodies[joint.node_a].global_position.distance_to(hinges_bodies[joint.node_b].global_position)
	softbody = (get_parent() as SoftBody2D)

func is_hinge_broken(joint: Joint2D):
	return hinges_distances[joint.name] * 1.8 < hinges_bodies[joint.node_a].position.distance_to(hinges_bodies[joint.node_b].position)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta):
	if is_queued_for_deletion():
		return
	var to_remove_hinge = []
	for node in hinges:
		var hinge := node as Joint2D
		if hinges_bodies[hinge.node_a] == null or \
			hinges_bodies[hinge.node_b] == null or \
			hinges_bodies[hinge.node_a].is_queued_for_deletion() or \
			hinges_bodies[hinge.node_b].is_queued_for_deletion():
			to_remove_hinge.append(hinge)
			continue
		if is_hinge_broken(hinge):
			softbody.remove_joint(hinges_bodies[hinge.node_a].get_meta("bone_name"), \
				hinges_bodies[hinge.node_b].get_meta("bone_name"))
			to_remove_hinge.append(hinge)
	if len(to_remove_hinge) != 0:
		for hinge in to_remove_hinge:
			remove_child(hinge)
			hinge.queue_free()
			hinges.erase(hinge)
			var bone_a_name = hinges_bodies[hinge.node_a].get_meta("bone_name")
			var bone_b_name = hinges_bodies[hinge.node_b].get_meta("bone_name")
			var bone_a = get_node(NodePath("../"+softbody.skeleton.get_concatenated_names()+"/"+bone_a_name))
			var bone_b = get_node(NodePath("../"+softbody.skeleton.get_concatenated_names()+"/"+bone_b_name))
			remove_bone(bone_a, bone_b)
			remove_bone(bone_b, bone_a)

func remove_bone(bone_a: LookAtCenter2D, bone_b: LookAtCenter2D):
	bone_a.filter_out(bone_b)

extends RigidBody2D

@onready var hinges := get_children().filter(func(node): return node is DampedSpringJoint2D)
@onready var rigidbodies := get_parent().get_children().filter(func(node): return node is RigidBody2D)
var hinges_bodies: Dictionary

func _ready():
	for hinge in hinges:
		var joint := hinge as DampedSpringJoint2D
		hinges_bodies[joint.node_a] = get_node(joint.node_a.get_concatenated_names().substr(1)) as RigidBody2D
		hinges_bodies[joint.node_b] = get_node(joint.node_b.get_concatenated_names().substr(1)) as RigidBody2D

func is_hinge_broken(joint: DampedSpringJoint2D):
	return joint.length * 1.7 < hinges_bodies[joint.node_a].position.distance_to(hinges_bodies[joint.node_b].position)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if is_queued_for_deletion():
		return
	var to_remove_hinge = []
	var softbody = (get_parent() as SoftBody2D)
	for node in hinges:
		var hinge := node as DampedSpringJoint2D
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

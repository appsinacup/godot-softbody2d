@tool
class_name SoftBody2DBuilder
extends RefCounted

## Builds the scene tree of a [SoftBody2D] from generated regions: the [Skeleton2D] with one
## [Bone2D] per region and the polygon weights, one [RigidBody2D] per bone with its
## [CollisionShape2D] and [RemoteTransform2D], and the [Joint2D]s between neighbours.
## Reads the softbody's generation properties; created for one generation.

var _softbody: SoftBody2D


func _init(softbody: SoftBody2D) -> void:
	_softbody = softbody


## Builds everything from a [method SoftBody2DRegions.generate] result and returns the
## skeleton. The softbody must already carry the generated polygon.
func build(generated: Dictionary) -> Skeleton2D:
	var regions: Array[Voronoi2D.VoronoiRegion2D] = generated["regions"]
	var bone_vertices: Array = generated["bone_vertices"]
	var skeleton := _prepare_skeleton()
	var bones := _create_bones(regions)
	var weights_and_connections := _generate_weights(bones, regions, bone_vertices)
	var weights: Array = weights_and_connections[0]
	for bone_index in bones.size():
		var bone: Bone2D = bones[bone_index]
		bone.set_meta("vert_owned", bone_vertices[bone_index])
		skeleton.add_child(bone)
		_softbody.add_bone(NodePath(bone.name), PackedFloat32Array(weights[bone_index]))
		_set_editor_owner(bone)
	_remove_old_bodies()
	var rigidbodies := _add_rigid_body_for_bones(skeleton, generated)
	_generate_joints(skeleton, rigidbodies, weights_and_connections[1])
	return skeleton


static func new_shape(shape_type: String, radius: float, fit := 1.0) -> Shape2D:
	var shape: Shape2D
	if shape_type == "Circle":
		shape = CircleShape2D.new()
	elif shape_type == "Rectangle":
		shape = RectangleShape2D.new()
	else:
		push_error("Wrong shape used for shape_type. " + shape_type)
		shape = RectangleShape2D.new()
	shape.resource_local_to_scene = true
	size_shape(shape, radius, fit)
	return shape


static func size_shape(shape: Shape2D, radius: float, fit := 1.0) -> void:
	if shape is CircleShape2D:
		shape.radius = radius / 2.0 * fit
	elif shape is RectangleShape2D:
		shape.size = Vector2(radius, radius) * fit


## The node of [param nodes] nearest to their centroid.
static func node_nearest_centre(nodes: Array) -> Node:
	var centre := Vector2()
	for node in nodes:
		if node != null:
			centre += (node as Node2D).global_position
	centre /= nodes.size()
	var best_distance := (nodes[0] as Node2D).global_position.distance_squared_to(centre)
	var selected: Node = nodes[0]
	for node in nodes:
		if node == null:
			continue
		var distance := (node as Node2D).global_position.distance_squared_to(centre)
		if distance < best_distance:
			best_distance = distance
			selected = node
	return selected


## A bone with no neighbours has no region worth showing; its polygon fades away.
static func hide_lone_bone(bone: Bone2D) -> void:
	bone.create_tween().tween_property(bone, "scale", Vector2(), 1)


func _set_editor_owner(node: Node) -> void:
	if Engine.is_editor_hint():
		node.set_owner(_softbody.get_tree().get_edited_scene_root())


func _prepare_skeleton() -> Skeleton2D:
	var skeleton: Skeleton2D
	for child in _softbody.get_children():
		if child is Skeleton2D:
			skeleton = child
			break
	if skeleton == null:
		skeleton = Skeleton2D.new()
		skeleton.name = "Skeleton2D"
		_softbody.add_child(skeleton)
		_set_editor_owner(skeleton)
	_softbody.skeleton = NodePath(skeleton.name)
	skeleton.position = Vector2()
	for child in skeleton.get_children():
		child.queue_free()
		skeleton.remove_child(child)
	_softbody.clear_bones()
	return skeleton


func _create_bones(regions: Array[Voronoi2D.VoronoiRegion2D]) -> Array[Bone2D]:
	var bones: Array[Bone2D] = []
	for index in regions.size():
		var bone := Bone2D.new()
		bone.name = "Bone-" + str(index)
		bone.global_position = regions[index].fixed_center
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(_softbody.vertex_interval)
		bones.append(bone)
	return bones


# A polygon vertex is pulled by every bone whose region touches it; bones sharing a vertex
# are neighbours, which is what the joints are generated from. With skin smoothing, nearby
# bones pull too, fading with distance, so the texture bends smoothly across region borders.
func _generate_weights(bones: Array[Bone2D], regions: Array, bone_vertices: Array) -> Array:
	var polygon := _softbody.polygon
	var weights := []
	var bone_count := bones.size()
	weights.resize(bone_count)
	for bone_index in bone_count:
		weights[bone_index] = []
		weights[bone_index].resize(polygon.size())
		weights[bone_index].fill(0.0)
	for bone_index in bone_count:
		for point_idx in bone_vertices[bone_index]:
			weights[bone_index][point_idx] = 1.0
	var bone_connections := []
	for bone_index in bone_count:
		bone_connections.append({})
	for point_index in polygon.size():
		var point := polygon[point_index]
		var bones_at_point := []
		for bone_index in bone_count:
			for poly in regions[bone_index].polygon_points:
				for poly_point in poly:
					if point.distance_squared_to(poly_point) < 2:
						bones_at_point.append(bone_index)
						weights[bone_index][point_index] = 1.0
		for bone_a in bones_at_point:
			for bone_b in bones_at_point:
				if bone_a != bone_b:
					bone_connections[bone_a][bone_b] = true
	if _softbody.skin_smoothing > 0.0:
		_smooth_weights(weights, bones, polygon)
	return [weights, bone_connections]


# Blends the rigid region weights with distance falloff weights over every bone within
# reach; the reach grows with the smoothing so 1 is visibly softer than 0.5.
func _smooth_weights(weights: Array, bones: Array[Bone2D], polygon: PackedVector2Array) -> void:
	var smoothing := _softbody.skin_smoothing
	var reach := _softbody.vertex_interval * (0.75 + smoothing)
	for point_index in polygon.size():
		var point := polygon[point_index]
		for bone_index in bones.size():
			var distance := point.distance_to(bones[bone_index].position)
			var falloff := 0.0
			if distance < reach:
				falloff = pow(1.0 - distance / reach, 2.0)
			var rigid: float = weights[bone_index][point_index]
			weights[bone_index][point_index] = lerpf(rigid, falloff, smoothing)


## Re-anchors a joint at [param anchor] so the bodies' current pose becomes its rest pose,
## keeping its parameters. Plastic yielding is built on this.
static func reanchor(joint: Joint2D, anchor: Vector2, body_a: PhysicsBody2D, body_b: PhysicsBody2D) -> void:
	var rid := joint.get_rid()
	if joint is PinJoint2D:
		var pin := joint as PinJoint2D
		PhysicsServer2D.joint_make_pin(rid, anchor, body_a.get_rid(), body_b.get_rid())
		PhysicsServer2D.pin_joint_set_param(rid, PhysicsServer2D.PIN_JOINT_SOFTNESS, pin.softness)
		PhysicsServer2D.pin_joint_set_flag(
			rid, PhysicsServer2D.PIN_JOINT_FLAG_ANGULAR_LIMIT_ENABLED, pin.angular_limit_enabled
		)
		PhysicsServer2D.pin_joint_set_param(rid, PhysicsServer2D.PIN_JOINT_LIMIT_LOWER, pin.angular_limit_lower)
		PhysicsServer2D.pin_joint_set_param(rid, PhysicsServer2D.PIN_JOINT_LIMIT_UPPER, pin.angular_limit_upper)
		PhysicsServer2D.joint_set_param(rid, PhysicsServer2D.JOINT_PARAM_BIAS, pin.bias)
		PhysicsServer2D.joint_disable_collisions_between_bodies(rid, pin.disable_collision)
	joint.global_position = anchor


func _remove_old_bodies() -> void:
	for child in _softbody.get_children():
		if not child is Skeleton2D:
			_softbody.remove_child(child)
			child.queue_free()


func _add_rigid_body_for_bones(skeleton: Skeleton2D, generated: Dictionary) -> Array[RigidBody2D]:
	var bones := skeleton.get_children()
	var rigidbodies: Array[RigidBody2D] = []
	var follow := node_nearest_centre(bones)
	# Geometry is already in world units via bake_scale, so shapes are sized from radius directly.
	var shared_shape := new_shape(_softbody.shape_type, _softbody.radius)
	var outlines: Array[PackedVector2Array] = generated["clearance_outlines"]
	var clearance: float = generated["clearance"]
	var edge_regions: PackedByteArray = generated["edge_regions"]
	for idx in bones.size():
		var bone: Bone2D = bones[idx]
		var fit := SoftBody2DRegions.shape_fit_at(bone.position, outlines, clearance)
		var shape := shared_shape if fit >= 1.0 else new_shape(_softbody.shape_type, _softbody.radius, fit)
		var rigid_body := _create_rigid_body(skeleton, bone, bone == follow, shape)
		rigid_body.set_meta("idx", idx)
		if fit < 1.0:
			rigid_body.set_meta("shape_fit", fit)
		if edge_regions[idx] == 1:
			rigid_body.set_meta("edge", true)
		rigid_body.set_meta("bone_name", bone.name)
		rigidbodies.append(rigid_body)
	return rigidbodies


func _create_rigid_body(skeleton: Skeleton2D, bone: Bone2D, is_center: bool, shape: Shape2D) -> RigidBody2D:
	var rigid_body: RigidBody2D
	if _softbody.rigidbody_scene:
		rigid_body = _softbody.rigidbody_scene.instantiate()
	else:
		rigid_body = RigidBody2D.new()
	rigid_body.name = bone.name
	var collision_shape := CollisionShape2D.new()
	collision_shape.shape = shape
	collision_shape.name = _softbody.shape_type + "Shape2D"
	collision_shape.visible = false
	rigid_body.mass = _softbody.mass
	rigid_body.can_sleep = _softbody.can_sleep
	rigid_body.gravity_scale = _softbody.gravity_scale
	rigid_body.constant_torque = _softbody.constant_torque
	rigid_body.constant_force = _softbody.constant_force
	# The node has no parent yet, so this is a local position despite the name.
	rigid_body.position = skeleton.transform * bone.position
	# Shape memory reads this, so it stays right even if the scene is saved while deformed.
	rigid_body.set_meta("rest_position", rigid_body.position)
	rigid_body.physics_material_override = _softbody.physics_material_override
	rigid_body.linear_damp = _softbody.linear_damp
	rigid_body.angular_damp = _softbody.angular_damp
	rigid_body.add_child(collision_shape)
	rigid_body.collision_layer = _softbody.collision_layer
	rigid_body.collision_mask = _softbody.collision_mask
	for exclude in _softbody.exclude_array:
		if exclude != null:
			rigid_body.add_collision_exception_with(exclude)
	var remote_transform := RemoteTransform2D.new()
	remote_transform.visible = false
	remote_transform.name = "RemoteTransform2D"
	rigid_body.add_child(remote_transform)
	remote_transform.remote_path = "../../" + skeleton.name + "/" + bone.name
	remote_transform.update_rotation = false
	remote_transform.update_scale = false
	remote_transform.use_global_coordinates = true
	_softbody.add_child(rigid_body)
	_set_editor_owner(collision_shape)
	_set_editor_owner(remote_transform)
	_set_editor_owner(rigid_body)
	if rigid_body is SoftBody2DRigidBody:
		(rigid_body as SoftBody2DRigidBody).rigidbody_created.emit(collision_shape, is_center)
	return rigid_body


func _generate_joints(skeleton: Skeleton2D, rigid_bodies: Array[RigidBody2D], connected_bones: Array) -> void:
	var bones := skeleton.get_children()
	var connected_paths := []
	var connected_indices := []
	for _i in bones.size():
		connected_paths.append([])
		connected_indices.append([])
	for idx_a in rigid_bodies.size():
		var node_a := rigid_bodies[idx_a]
		for idx_b in connected_bones[idx_a].keys():
			var node_b := rigid_bodies[idx_b]
			if node_a == node_b:
				continue
			connected_paths[idx_a].append(NodePath(bones[idx_b].name))
			connected_indices[idx_a].append(idx_b)
			# One joint per pair, parented to the lower index and anchored midway.
			if idx_a < idx_b:
				_add_joint(node_a, node_b)
	if _softbody.joint_reach > 1:
		_add_reach_joints(rigid_bodies, connected_bones)
	skeleton.visible = false
	for i in bones.size():
		# The skin rotation of every bone is written each physics step from its neighbourhood,
		# relative to this rest pose.
		bones[i].set_rest(bones[i].transform)
		bones[i].set_meta("idx", i)
		bones[i].set_meta("connected_nodes_paths", connected_paths[i])
		bones[i].set_meta("connected_nodes_idx", connected_indices[i])
		if connected_paths[i].is_empty():
			hide_lone_bone(bones[i])


# One joint per pair of bodies between two and joint_reach hops apart, however many paths
# connect them. Breadth first over the one-hop connections.
func _add_reach_joints(rigid_bodies: Array[RigidBody2D], connected_bones: Array) -> void:
	for idx_a in rigid_bodies.size():
		var hops := {idx_a: 0}
		var frontier := [idx_a]
		for hop in range(1, _softbody.joint_reach + 1):
			var next := []
			for idx in frontier:
				for idx_b in connected_bones[idx].keys():
					if !hops.has(idx_b):
						hops[idx_b] = hop
						next.append(idx_b)
			frontier = next
		for idx_b in hops.keys():
			if idx_b > idx_a && hops[idx_b] > 1:
				_add_joint(rigid_bodies[idx_a], rigid_bodies[idx_b], hops[idx_b])


func _add_joint(node_a: RigidBody2D, node_b: RigidBody2D, hops := 1) -> void:
	var joint_distance := (node_a.global_position - node_b.global_position).length()
	var joint: Joint2D
	if _softbody.joint_type == "pin":
		var pin_joint := PinJoint2D.new()
		pin_joint.softness = _softbody.softness
		pin_joint.angular_limit_enabled = _softbody.angular_limit_enabled
		pin_joint.angular_limit_lower = deg_to_rad(_softbody.angular_limit_lower)
		pin_joint.angular_limit_upper = deg_to_rad(_softbody.angular_limit_upper)
		joint = pin_joint
	else:
		var spring_joint := DampedSpringJoint2D.new()
		spring_joint.stiffness = _softbody.stiffness
		spring_joint.rest_length = joint_distance * _softbody.rest_length_ratio
		spring_joint.length = joint_distance * _softbody.length_ratio
		spring_joint.damping = _softbody.damping
		joint = spring_joint
	# Distance breaking measures against this; recorded now so a scene saved while deformed
	# still breaks at the right ratio.
	joint.set_meta("joint_distance", joint_distance)
	joint.set_meta("original_distance", joint_distance)
	if hops > 1:
		joint.set_meta("hops", hops)
	joint.name = "Joint2D-" + node_a.name + "-" + node_b.name
	joint.node_a = ".."
	joint.node_b = "../../" + node_b.name
	joint.disable_collision = _softbody.disable_collision
	joint.rotation = node_a.position.angle_to_point(node_b.position) - PI / 2
	joint.bias = _softbody.bias
	joint.visible = false
	node_a.add_child(joint)
	_set_editor_owner(joint)
	joint.global_position = (node_a.global_position + node_b.global_position) * 0.5

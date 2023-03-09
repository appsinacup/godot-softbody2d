@tool
@icon("res://addons/softbody2d/plugin_icon.png")
class_name SoftBody2D
extends Polygon2D

@export var bake_softbody := false :
	set (value):
		create_softbody2d()
	get:
		return false

@export var clear_softbody := false :
	set (value):
		clear_softbody2d()
	get:
		return false

@export_group("Polygon")
@export_range(2, 50, 1, "or_greater") var polygon_vertex_interval := 30
@export_range(0.01, 0.6, 0.05) var polygon_voronoi_interval :float= 0.15

@export_group("Joint")
@export_enum("pin", "spring") var joint_type:= "pin"
@export_range(0, 2, 0.1, "or_greater") var joint_bias : float = 0.1
@export var joint_disable_collision := false
@export_subgroup("DampedSpringJoint")
@export_range(0.1, 128, 0.1, "or_greater") var joint_stiffness: float = 20
@export_range(0.1, 16, 0.1, "or_greater") var joint_damping: float = 0.7
@export_subgroup("PinJoint")
@export_range(0, 100, 0.1, "or_greater") var joint_softness: float = 80

@export_group("RigidBody")
@export_range(2, 50, 1, "or_greater") var shape_circle_radius := 20
@export_flags_2d_physics var rigidbody_collision_layer := 1
@export_flags_2d_physics var rigidbody_collision_mask := 1
@export_range(0.1, 100, 0.1, "or_more") var rigidbody_mass := 0.1
@export var rigidbody_script : Script
@export var rigidbody_pickable := false
@export var rigidbody_lock_rotation := false
@export var physics_material_override: PhysicsMaterial

func create_softbody2d():
	var voronoi = create_polygon2d()
	var skeleton2d = construct_skeleton2d(voronoi[0], voronoi[1])
	create_rigidbodies2d(skeleton2d)

func clear_softbody2d():
	clear_polygon()
	for child in get_children():
		child.queue_free()
		remove_child(child)
	clear_bones()

func clear_polygon():
	polygon.clear()
	polygons.clear()
	uv.clear()
	internal_vertex_count = 0

func create_polygon2d():
	if texture == null:
		print("Texture is required to generate SoftBody2D")
		return
	_create_external_vertices_from_texture()
	_simplify_polygon()
	return _create_internal_vertices()

func _get_polygon_verts():
	var polygon_verts = polygon.duplicate()
	if polygon_verts.size() != 0:
		var new_size = polygon_verts.size() - internal_vertex_count
		if new_size > 0:
			polygon_verts.resize(new_size)
	return polygon_verts

func _create_external_vertices_from_texture():
	skeleton = ""
	var bitmap = BitMap.new()
	bitmap.create_from_image_alpha(texture.get_image())
	var rect = Rect2(0, 0, texture.get_width(), texture.get_height())
	var poly = bitmap.opaque_to_polygons(rect)
	set_polygon(PackedVector2Array(poly[0]))
	set_uv(PackedVector2Array([]))

func _simplify_polygon():
	var poly = []
	var init_size = polygon.size()
	for n in range(init_size):
		var next_n = n + 1 if init_size > n + 1 else 0
		var p1 = polygon[n]
		var p2 = polygon[next_n]
		var dir = p1.direction_to(p2)
		var dist = p1.distance_to(p2)
		var num = dist / polygon_vertex_interval
		for _n in range(num + 1):
			var point = p1 + (dir * _n * polygon_vertex_interval)
			if point.distance_to(p2) > polygon_vertex_interval / 3:
				poly.append(point)
					
	set_polygon(PackedVector2Array(poly))

func _generate_points_voronoi(lim_min: Vector2, lim_max: Vector2, polygon_verts):
	var polygon_size = lim_max - lim_min
	var polygon_num = Vector2(int(polygon_size.x / polygon_vertex_interval), int(polygon_size.y / polygon_vertex_interval))
	var voronoi = Voronoi2D.generateVoronoi(polygon_size, polygon_vertex_interval, \
		Vector2(polygon_voronoi_interval, polygon_voronoi_interval) + lim_min + polygon_size/2, polygon_voronoi_interval)
	
	var polygons = []
	var new_voronoi = []
	var voronoi_regions_to_move = []
	# find out what regions to remove
	for region_idx in len(voronoi):
		var each = voronoi[region_idx]
		var did_cut = false
		var is_middle_inside = _is_point_in_area(each[0], polygon_verts)
		var is_inside = true
		for polygon_vert in each[1]:
			if not _is_point_in_area(polygon_vert, polygon_verts):
				is_inside = false
				var intersect = Geometry2D.intersect_polygons(polygon_verts, each[1])
				each[1] = PackedVector2Array()
				for intersect_poly in intersect:
					each[1].append_array(intersect_poly)
					did_cut = true
				if did_cut:
					new_voronoi.append(each)
					if not is_middle_inside:
						voronoi_regions_to_move.append(new_voronoi.size() - 1)
					break
		if (not did_cut) and is_inside:
			new_voronoi.append(each)
			if not is_middle_inside:
				voronoi_regions_to_move.append(new_voronoi.size() - 1)
	# move regions first
	for region_to_move in voronoi_regions_to_move:
		var dist := -1.0
		var closest_idx := -1
		var to_remove = new_voronoi[region_to_move]
		for voronoi_idx in len(new_voronoi):
			if voronoi_idx in voronoi_regions_to_move:
				continue
			var each = new_voronoi[voronoi_idx]
			var current_dist = each[0].distance_to(to_remove[0])
			if dist < 0 or dist > current_dist:
				dist = current_dist
				closest_idx = voronoi_idx
		if typeof(new_voronoi[closest_idx][1]) != TYPE_ARRAY:
			new_voronoi[closest_idx][1] = [new_voronoi[closest_idx][1]]
		new_voronoi[closest_idx][1].append(to_remove[1])
	voronoi_regions_to_move.sort_custom(func (x,y): return x>y)
	# remove them
	for region_to_move in voronoi_regions_to_move:
		new_voronoi.remove_at(region_to_move)
	# add remaining
	var new_vert = get_polygon()
	var bone_vert_arr = []
	var in_vert_count = 0
	for each in new_voronoi:
		if typeof(each[1]) != TYPE_ARRAY:
			each[1] = [each[1]]
		# multiple polygons
		var bone_vert_combined_array := []
		for poly in each[1]:
			polygons.append_array(_triangulate_polygon(poly, polygon_verts, len(new_vert)))
			var bone_vert_arr_el = []
			for vert in poly:
				bone_vert_arr_el.append(len(new_vert))
				new_vert.append(vert)
				in_vert_count += 1
			bone_vert_combined_array.append_array(bone_vert_arr_el)
		bone_vert_arr.append(bone_vert_combined_array)
	set_polygon(new_vert)
	set_internal_vertex_count(in_vert_count)
	set_polygons(polygons)
	return [new_voronoi, bone_vert_arr]

func _create_internal_vertices():
	var polygon_verts = _get_polygon_verts()
	var polygon_limits = _calculate_polygon_limits()
	var lim_min = polygon_limits[0]
	var lim_max = polygon_limits[1]
	var polygon_size = lim_max - lim_min
	var polygon_num = Vector2(int(polygon_size.x / polygon_vertex_interval), int(polygon_size.y / polygon_vertex_interval))
	return _generate_points_voronoi(lim_min, lim_max, polygon_verts)

func _calculate_polygon_limits() -> Array[Vector2]:
	var lim_min = polygon[0]
	var lim_max = polygon[0]
	for point in polygon:
		if point.x < lim_min.x:
			lim_min.x = point.x
		if point.x > lim_max.x:
			lim_max.x = point.x
		if point.y < lim_min.y:
			lim_min.y = point.y
		if point.y > lim_max.y:
			lim_max.y = point.y
	return [lim_min, lim_max]

func _is_point_in_area(point: Vector2, polygon_verts: PackedVector2Array, scale_amount := 1.0) -> bool:
	var scaled_poly = polygon_verts.duplicate()
	var center = Vector2()
	for vert in polygon_verts:
		center = center + vert
	center = center / len(polygon_verts)
	for i in len(scaled_poly):
		scaled_poly[i] = (scaled_poly[i] - center) * scale_amount + center
	return Geometry2D.is_point_in_polygon(point, scaled_poly)

func _triangulate_polygon(polygon: PackedVector2Array, polygon_verts, offset:= 0, validate_inside:= false):
	var points = Array(Geometry2D.triangulate_polygon(polygon))
	var polygons = []
	for i in range(ceil(len(points) / 3)):
		var triangle = []
		for n in range(3):
			triangle.append(points.pop_front() + offset)
		var a = polygon[triangle[0] - offset]
		var b = polygon[triangle[1] - offset]
		var c = polygon[triangle[2] - offset]
		if validate_inside:
			if _is_line_in_area(a,b, polygon_verts) and _is_line_in_area(b,c, polygon_verts) and _is_line_in_area(c,a, polygon_verts):
				polygons.append(PackedInt32Array(triangle))
		else:
			polygons.append(PackedInt32Array(triangle))
	return polygons


func _is_line_in_area(a: Vector2, b: Vector2, polygon_verts: PackedVector2Array) -> bool:
	return _is_point_in_area(a + a.direction_to(b) * 0.01, polygon_verts) \
		and _is_point_in_area(b + b.direction_to(a) * 0.01, polygon_verts) \
		and _is_point_in_area((a + b) / 2, polygon_verts)


func _create_skeleton() -> Skeleton2D:
	var skeleton2d = Skeleton2D.new()
	skeleton2d.name = "Skeleton2D"
	add_child(skeleton2d)
	if Engine.is_editor_hint():
		skeleton2d.set_owner(get_tree().get_edited_scene_root())
	skeleton = NodePath(skeleton2d.name)
	clear_bones()
	return skeleton2d

func construct_skeleton2d(voronoi, bone_vert_arr) -> Skeleton2D:
	var skeleton_nodes = get_children().filter(func (node): return node is Skeleton2D)
	var skeleton2d : Skeleton2D
	if len(skeleton_nodes) == 0:
		print("Skeleton2D is null. Creating one for you.")
		skeleton2d = _create_skeleton()
	else:
		skeleton2d = skeleton_nodes[0] as Skeleton2D
	skeleton = NodePath(skeleton2d.name)
	skeleton2d.position = Vector2()
	for child in skeleton2d.get_children():
		child.queue_free()
		skeleton2d.remove_child(child)
	clear_bones()
	var bones = _create_bones(voronoi)
	var weights = _generate_weights(bones, voronoi)
	var bone_count = skeleton2d.get_bone_count()
	for bone_index in len(bones):
		var bone : Bone2D = bones[bone_index]
		bone.set_meta("vert_owned", bone_vert_arr[bone_index])
		skeleton2d.add_child(bone)
		add_bone(NodePath(bone.name), PackedFloat32Array(weights[bone_index]))
		if Engine.is_editor_hint():
			bone.set_owner(get_tree().get_edited_scene_root())
	return skeleton2d

func _create_bones(voronoi) -> Array[Bone2D]:
	var bones: Array[Bone2D] = []
	var polygon_limits = _calculate_polygon_limits()
	var polygon_verts = _get_polygon_verts()
	for each in voronoi:
		var bone := Bone2D.new()
		var point = each[0]
		bone.global_position = point
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(polygon_vertex_interval)
		bones.append(bone)
	for bone in bones:
		bone.set_script(LookAtCenter2D)
	return bones

func _get_node_to_follow(bones_arr) -> Node:
	var center = Vector2()
	for bone in bones_arr:
		if bone != null:
			center = center + (bone as Node2D).global_position
	center = center / len(bones_arr)
	var dist_to_center = (bones_arr[0] as Node2D).global_position.distance_squared_to(center)
	var selected_bone = bones_arr[0]
	for bone in bones_arr:
		if bones_arr != null:
			var dist = (bone as Node2D).global_position.distance_squared_to(center)
			if dist < dist_to_center:
				dist_to_center = dist
				selected_bone = bone
	
	return selected_bone

func _generate_weights(bones: Array[Bone2D], voronoi):
	var weights = []
	var bone_count = len(bones)
	var points_size = polygon.size()
	weights.resize(bone_count)
	for bone_index in bone_count:
		weights[bone_index] = []
		weights[bone_index].resize(points_size)
	for point_index in points_size:
		var point = polygon[point_index]
		var bones_data = []
		var dist_sum : float = 0
		
		for bone_index in bone_count:
			weights[bone_index][point_index] = 0
			for poly in voronoi[bone_index][1]:
				if _is_point_in_area(point, poly, 1.1):
					weights[bone_index][point_index] = 1
					break
	return weights

func _sort_nearest_point(a, b) -> bool:
	return a[1] < b[1]

func create_rigidbodies2d(skeleton: Skeleton2D):
	for child in get_children():
		if not child is Skeleton2D:
			remove_child(child)
			child.queue_free()
	var rigidbodies := _add_rigid_body_for_bones(skeleton)
	_generate_joints(rigidbodies)

func _add_rigid_body_for_bones(skeleton: Skeleton2D) -> Array[RigidBody2D]:
	var bones = skeleton.get_children()
	var link_pair = {}
	var rigidbodies : Array[RigidBody2D] = []
	for bone in bones:
		var rigid_body = _create_rigid_body(skeleton, bone)
		rigid_body.set_meta("bone_name", bone.name)
		rigidbodies.append(rigid_body)
	return rigidbodies

func _create_rigid_body(skeleton: Skeleton2D, bone: Bone2D):
	var rigid_body = RigidBody2D.new()
	rigid_body.name = bone.name
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = shape_circle_radius / 2.0
	collision_shape.shape = shape
	rigid_body.mass = rigidbody_mass
	rigid_body.global_position = skeleton.transform * bone.position
	rigid_body.physics_material_override = physics_material_override
	rigid_body.add_child(collision_shape)
	rigid_body.collision_layer = rigidbody_collision_layer
	rigid_body.collision_mask = rigidbody_collision_mask
	rigid_body.input_pickable = rigidbody_pickable
	rigid_body.lock_rotation = rigidbody_lock_rotation
	rigid_body.set_script(rigidbody_script)
	var remote_transform = RemoteTransform2D.new()
	rigid_body.add_child(remote_transform)
	remote_transform.remote_path = "../../" + skeleton.name + "/" + bone.name
	remote_transform.update_rotation = false
	remote_transform.update_scale = false
	remote_transform.use_global_coordinates = true
	add_child(rigid_body)
	if Engine.is_editor_hint():
		collision_shape.set_owner(get_tree().get_edited_scene_root())
		remote_transform.set_owner(get_tree().get_edited_scene_root())
		rigid_body.set_owner(get_tree().get_edited_scene_root())
	return rigid_body

func _generate_joints(rigid_bodies: Array[RigidBody2D]):
	var bones = get_node(skeleton).get_children()
	var connected_nodes_paths = []
	var connected_nodes = []
	for _i in bones.size():
		connected_nodes_paths.append([])
		connected_nodes.append([])
	for idx_a in len(rigid_bodies):
		var node_a := rigid_bodies[idx_a]
		for idx_b in len(rigid_bodies):
			var node_b := rigid_bodies[idx_b]
			if node_a == node_b or \
				node_a.global_position.distance_to(node_b.global_position) > polygon_vertex_interval * 1.5:
				continue
			connected_nodes_paths[idx_a].append(NodePath("../"+bones[idx_b].name))
			connected_nodes[idx_a].append(node_b)
			if joint_type == "pin":
				var joint = PinJoint2D.new()
				joint.node_a = ".."
				joint.node_b = "../../" + node_b.name
				joint.softness = joint_softness
				joint.disable_collision = joint_disable_collision
				joint.look_at(node_b.global_position)
				joint.rotation = node_a.position.angle_to_point(node_b.position) - PI/2
				joint.bias = joint_bias
				node_a.add_child(joint)
				joint.global_position = node_a.global_position
				if Engine.is_editor_hint():
					joint.set_owner(get_tree().get_edited_scene_root())
			else:
				var joint = DampedSpringJoint2D.new()
				joint.node_a = ".."
				joint.node_b = "../../" + node_b.name
				joint.stiffness = joint_stiffness
				joint.disable_collision = joint_disable_collision
				#joint.rest_length = ((node_a.global_position - node_b.global_position).length()) * 1
				#joint.rest_length = 0
				joint.length = ((node_a.global_position - node_b.global_position).length()) * 1
				joint.look_at(node_b.global_position)
				joint.rotation = node_a.position.angle_to_point(node_b.position) - PI/2
				joint.damping = joint_damping
				joint.bias = joint_bias
				node_a.add_child(joint)
				joint.global_position = node_a.global_position
				if Engine.is_editor_hint():
					joint.set_owner(get_tree().get_edited_scene_root())
	var follow_node := _get_node_to_follow(bones)
	for i in bones.size():
		var bone = bones[i]
		#bone.follow = [NodePath("../"+follow_node.name)]
		#bone._follow_nodes = [follow_node]
		bone.follow = connected_nodes_paths[i]
		bone._follow_nodes = connected_nodes[i]
		bone.look_at(LookAtCenter2D.get_dir_to_follow(bone.global_position, connected_nodes[i]))
		bone.set_rest(bone.transform)

# used internally, computed at _ready once
var _bones_array

# Called when the node enters the scene tree for the first time.
func _ready():
	if get_child_count() == 0:
		print("SoftBody2D not initialized")
		return
	_bones_array = get_node(skeleton).get_children().filter(func(node): return node is Bone2D)

func remove_joint(bone_a_name, bone_b_name):
	var polygon_weights: Array[float] = []
	polygon_weights.resize(len(polygon))
	var weights: Array[PackedFloat32Array] = []
	var bone_a_idx = -1
	var bone_b_idx = -1
	var bone_a: Bone2D
	var bone_b: Bone2D
	for i in len(_bones_array):
		var bone = _bones_array[i]
		if bone.name == bone_a_name:
			bone_a_idx = i
			bone_a = bone
		if bone.name == bone_b_name:
			bone_b_idx = i
			bone_b = bone
	
	var bone_a_weights = get_bone_weights(bone_a_idx)
	var bone_b_weights = get_bone_weights(bone_b_idx)
	var bone_a_owned_verts = _bones_array[bone_a_idx].get_meta("vert_owned")
	var bone_b_owned_verts = _bones_array[bone_b_idx].get_meta("vert_owned")
	for i in bone_a_owned_verts:
		bone_b_weights[i] = 0.0
	for i in bone_b_owned_verts:
		bone_a_weights[i] = 0.0
	set_bone_weights(bone_a_idx, bone_a_weights)
	set_bone_weights(bone_b_idx, bone_b_weights)

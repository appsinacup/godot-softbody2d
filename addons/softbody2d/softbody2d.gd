@tool
@icon("res://addons/softbody2d/plugin_icon.png")
class_name SoftBody2D
extends Polygon2D

@export var bake_softbody := false :
	set (value):
		create_softbody2d()
	get:
		return false

@export_group("Polygon")
@export_range(2, 50, 1, "or_greater") var polygon_vertex_interval := 30

@export_group("Skeleton")
@export_range(2, 50, 1, "or_greater") var bone_interval := 35
@export_range(1, 5, 1, "or_greater") var weight_shared_by_n := 2

@export_group("Joint")
@export_range(0, 1, 0.1) var joint_ratio : float = 1
@export_range(0.1, 64, 0.1) var joint_stiffness: float = 20
@export_range(2, 50, 1, "or_greater") var joint_damping: float = 0.7
@export_range(0, 1, 0.1) var joint_bias : float = 0
@export var joint_disable_collision := false

@export_group("RigidBody")
@export_flags_2d_physics var rigidbody_collision_layer := 1
@export_flags_2d_physics var rigidbody_collision_mask := 1
@export_range(0.1, 100, 0.1, "or_more") var rigidbody_mass := 0.1
@export var rigidbody_script : Script
@export var rigidbody_pickable := false
@export_range(2, 50, 1, "or_greater") var shape_circle_radius := 30
@export var physics_material_override: PhysicsMaterial

@export_group("Debug")

@export var bake_polygon := false :
	set (value):
		create_polygon2d()
	get:
		return false

@export var bake_skeleton := false :
	set (value):
		construct_skeleton2d()
	get:
		return false
		
@export var bake_rigidbodies := false :
	set (value):
		var skeleton2d = get_children().filter(func (node): return node is Skeleton2D)[0] as Skeleton2D
		create_rigidbodies2d(skeleton2d)
	get:
		return false

func create_softbody2d():
	create_polygon2d()
	var skeleton2d = construct_skeleton2d()
	create_rigidbodies2d(skeleton2d)



func create_polygon2d():
	if texture == null:
		print("Texture is required to generate SoftBody2D")
		return
	_create_external_vertices_from_texture()
	_simplify_polygon()
	_create_internal_vertices()
	_triangulate_polygon()

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

func _create_internal_vertices():
	var polygon_verts = _get_polygon_verts()
	var in_vert_count = 0
	var new_vert = get_polygon()
	var polygon_limits = _calculate_polygon_limits()
	var lim_min = polygon_limits[0]
	var lim_max = polygon_limits[1]
	var polygon_size = lim_max - lim_min
	var polygon_num = Vector2(int(polygon_size.x / polygon_vertex_interval), int(polygon_size.y / polygon_vertex_interval))
	for y in range(polygon_num.y + 1):
		for x in range(polygon_num.x + 1):
			var point = Vector2(lim_min.x + (x * polygon_vertex_interval), lim_min.y + (y * polygon_vertex_interval))
			if _is_point_in_area(point, polygon_verts):
				var is_fit = true
				for vert in polygon_verts:
					if point.distance_to(vert) < polygon_vertex_interval / 3:
						is_fit = false
						break
				if is_fit:
					new_vert.append(point)
					in_vert_count += 1
	
	set_polygon(new_vert)
	set_internal_vertex_count(in_vert_count)

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

func _is_point_in_area(point: Vector2, polygon_verts: PackedVector2Array) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon_verts)

func _triangulate_polygon() -> void:
	var polygon_verts = _get_polygon_verts()
	var points = Array(Geometry2D.triangulate_delaunay(polygon))
	var polygons = []
	for i in range(ceil(len(points) / 3)):
		var triangle = []
		for n in range(3):
			triangle.append(points.pop_front())
		var a = polygon[triangle[0]]
		var b = polygon[triangle[1]]
		var c = polygon[triangle[2]]
		
		if _is_line_in_area(a,b, polygon_verts) and _is_line_in_area(b,c, polygon_verts) and _is_line_in_area(c,a, polygon_verts):
			polygons.append(PackedInt32Array(triangle))
	set_polygons(polygons)

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

func construct_skeleton2d() -> Skeleton2D:
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
	var bones = _create_bones()
	for bone in bones:
		skeleton2d.add_child(bone)
		if Engine.is_editor_hint():
			bone.set_owner(get_tree().get_edited_scene_root())
	var weights = _generate_weights(skeleton2d)
	var bone_count = skeleton2d.get_bone_count()
	for bone_index in bone_count:
		add_bone(NodePath(skeleton2d.get_bone(bone_index).name), PackedFloat32Array(weights[bone_index]))
	return skeleton2d

func _create_bones() -> Array[Bone2D]:
	var bones: Array[Bone2D] = []
	var bone_matrix = []
	var polygon_limits = _calculate_polygon_limits()
	var lim_min = polygon_limits[0]
	var lim_max = polygon_limits[1]
	var polygon_size = lim_max - lim_min
	var polygon_bone_num = Vector2(int(polygon_size.x / bone_interval), int(polygon_size.y / bone_interval))
	var polygon_verts = _get_polygon_verts()
	bone_matrix.resize(polygon_bone_num.y + 2)
	for y in range(-polygon_bone_num.y / 2-1, polygon_bone_num.y +2):
		var row_array = []
		row_array.resize(polygon_bone_num.x + 2)
		bone_matrix[y] = row_array
		for x in range(-polygon_bone_num.x / 2 -1, polygon_bone_num.x + 2):
			var point = Vector2(lim_min.x + polygon_size.x/2 + x * bone_interval,\
				lim_min.y + polygon_size.y/2 + y * bone_interval)
			
			if _is_point_in_area(point, polygon_verts):
				var is_fit = true
				if is_fit:
					var bone := Bone2D.new()
					bone.name = "Bone:["+str(x)+"]["+str(y)+"]"
					bone.global_position = point
					bone.set_autocalculate_length_and_angle(false)
					bones.append(bone)
					bone_matrix[y][x] = bone
	var center_bone = bone_matrix[0][0]
	for bone in bones:
		bone.look_at(center_bone.global_position)
		bone.set_script(LookAtCenter2D)
		(bone as LookAtCenter2D).follow = NodePath("../" + center_bone.name)
	
		bone.set_rest(bone.transform)
	return bones

func _generate_weights(skeleton: Skeleton2D):
	var weights = []
	var bone_count = skeleton.get_bone_count()
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
			var bone = skeleton.get_bone(bone_index)
			var dist = point.distance_to(bone.position)
			bones_data.append([bone_index, dist, null])
			dist_sum += dist
		
		bones_data.sort_custom(_sort_nearest_point)
		var total_bone_sum = 0
		var weights_to_calc = bone_count
		if weights_to_calc > weight_shared_by_n:
			weights_to_calc = weight_shared_by_n
			dist_sum = 0
			for i in weights_to_calc:
				dist_sum += bones_data[i][1]
		for bone_data_index in range(weights_to_calc):
			var bone_data = bones_data[bone_data_index]
			var bone_index = bones_data[bone_data_index][0]
			bone_data[2] = (dist_sum - bone_data[1]) / dist_sum
			if bone_data[2] > 0.25:
				weights[bone_index][point_index] = bone_data[2]
			else:
				weights[bone_index][point_index] = 0
	return weights

func _sort_nearest_point(a, b) -> bool:
	return a[1] < b[1]

func remove_bone(polygon2d: Polygon2D, skeleton2d: Skeleton2D, idx: int):
	var bone := skeleton2d.get_bone(idx)
	polygon2d.erase_bone(idx)
	skeleton2d.remove_child(bone)
	bone.queue_free()

func remove_unused_points(polygon2d: Polygon2D):
	var polygon_weights : Array[float] = []
	polygon_weights.resize(len(polygon2d.polygon))
	var weights: Array[PackedFloat32Array] = []
	var bone_count := polygon2d.get_bone_count()
	for bone_idx in bone_count:
		var arr := polygon2d.get_bone_weights(bone_idx)
		weights.append(arr)
		for i in len(polygon_weights):
			polygon_weights[i] += arr[i]
	var polygon = PackedVector2Array()
	var to_remove = {}
	var internal_vertex_count = polygon2d.internal_vertex_count
	var outside_vertex_count = len(polygon_weights) - internal_vertex_count
	for i in len(polygon_weights):
		if polygon_weights[i] < 0.5:
			to_remove[i] = true
			if i > outside_vertex_count:
				internal_vertex_count = internal_vertex_count - 1
		else:
			polygon.append(polygon2d.polygon[i])
	for bone_idx in bone_count:
		var removed := 0
		for idx_removed in to_remove:
			weights[bone_idx].remove_at(idx_removed - removed)
			removed = removed + 1
		polygon2d.set_bone_weights(bone_idx, weights[bone_idx])
	var new_polygons = []
	for poly in polygon2d.polygons:
		var valid_polygon = true
		for idx in poly:
			if idx in to_remove:
				valid_polygon = false
		if valid_polygon:
			var ith = 0
			for idx_removed in to_remove:
				for i in len(poly):
					if poly[i] >= idx_removed - ith:
						poly[i] = poly[i] - 1
				ith = ith + 1
			new_polygons.append(poly)
	polygon2d.polygons = new_polygons
	polygon2d.polygon = polygon
	polygon2d.internal_vertex_count = internal_vertex_count


func create_rigidbodies2d(skeleton: Skeleton2D):
	for child in get_children():
		if not child is Skeleton2D:
			remove_child(child)
			child.queue_free()
	var rigidbodies := _add_rigid_body_for_bones(skeleton)
	_reset_skeleton(skeleton)
	_generate_joints(rigidbodies)

func _add_rigid_body_for_bones(skeleton: Skeleton2D) -> Array[RigidBody2D]:
	var bones = skeleton.get_children()
	var link_pair = {}
	var rigidbodies : Array[RigidBody2D] = []
	for bone in bones:
		var rigid_body = _create_rigid_body(skeleton, bone)
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
	rigid_body.set_script(rigidbody_script)
	var remote_transform = RemoteTransform2D.new()
	rigid_body.add_child(remote_transform)
	remote_transform.remote_path = "../../" + skeleton.name + "/" + bone.name
	remote_transform.update_rotation = false
	remote_transform.update_scale = false
	add_child(rigid_body)
	if Engine.is_editor_hint():
		collision_shape.set_owner(get_tree().get_edited_scene_root())
		remote_transform.set_owner(get_tree().get_edited_scene_root())
		rigid_body.set_owner(get_tree().get_edited_scene_root())
	return rigid_body

func _reset_skeleton(skeleton: Skeleton2D):
	for bone_index in skeleton.get_bone_count():
		var bone := skeleton.get_bone(bone_index)
		bone.apply_rest()

func _generate_joints(rigid_bodies: Array[RigidBody2D]):
	_add_joints(rigid_bodies)

func _add_joints(rigid_bodies: Array[RigidBody2D]):
	for node_a in rigid_bodies:
		for node_b in rigid_bodies:
			if node_a == node_b or \
				node_a.global_position.distance_to(node_b.global_position) > bone_interval * 1.5:
				continue
			var joint = DampedSpringJoint2D.new()
			joint.node_a = ".."
			joint.node_b = "../../" + node_b.name
			joint.stiffness = joint_stiffness
			joint.disable_collision = joint_disable_collision
			joint.rest_length = ((node_a.global_position - node_b.global_position).length())
			joint.length = ((node_a.global_position - node_b.global_position).length())*joint_ratio
			joint.look_at(node_b.global_position)
			joint.rotation = node_a.position.angle_to_point(node_b.position) - PI/2
			joint.damping = joint_damping
			joint.bias = joint_bias
			node_a.add_child(joint)
			joint.global_position = node_a.global_position
			if Engine.is_editor_hint():
				joint.set_owner(get_tree().get_edited_scene_root())



# Called when the node enters the scene tree for the first time.
func _ready():
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	if Engine.is_editor_hint():
		pass

@tool
extends Control

@export var editor : EditorInterface

var stiffness: float = 20
var damping: float = 0
var disable_collision := false

var collision_layer := 1
var collision_mask := 1
var mass := 0.1
var step := 10
var stepbone := 30
var steprigidbody := 20
var polygon2d: Polygon2D
var polygon_verts: PackedVector2Array
var polygon_size: Vector2
var polygon_num: Vector2
var polygon_bone_num: Vector2
var lim_max: Vector2
var lim_min: Vector2
var rigid_bodies_root: Node2D

func _is_polygon_selected():
	polygon2d = null
	if editor.get_selection().get_selected_nodes():
		if editor.get_selection().get_selected_nodes()[0] is Polygon2D:
			polygon2d = editor.get_selection().get_selected_nodes()[0]
			return true
	return false

func _on_generate_polygon() -> void:
	if !_is_polygon_selected():
		return
	_create_basic_poly()
	_clear_polygon()
	_create_per_vert()
	_create_internal_vert()
	_triangulate_polygon()

func _create_basic_poly() -> void:
	if polygon2d == null:
		return
	polygon2d.skeleton = ""
	var bm = BitMap.new()
	bm.create_from_image_alpha(polygon2d.texture.get_image())
	var rect = Rect2(0, 0, polygon2d.texture.get_width(), polygon2d.texture.get_height())
	var poly = bm.opaque_to_polygons(rect)
	polygon2d.set_polygon(PackedVector2Array(poly[0]))
	polygon2d.set_polygons(PackedVector2Array(poly[0]))

func _update_vars():
	polygon_verts = polygon2d.polygon.duplicate()
	if polygon_verts.size() != 0:
		var new_size = polygon_verts.size() - polygon2d.internal_vertex_count
		if new_size > 0:
			polygon_verts.resize(new_size)
	lim_min = polygon2d.polygon[0]
	lim_max = polygon2d.polygon[0]
	for point in polygon2d.polygon:
		if point.x < lim_min.x:
			lim_min.x = point.x
		if point.x > lim_max.x:
			lim_max.x = point.x
		if point.y < lim_min.y:
			lim_min.y = point.y
		if point.y > lim_max.y:
			lim_max.y = point.y
	polygon_size = Vector2(lim_max.x - lim_min.x, lim_max.y - lim_min.y)
	polygon_num = Vector2(int(polygon_size.x / step), int(polygon_size.y / step))
	polygon_bone_num = Vector2(int(polygon_size.x / stepbone), int(polygon_size.y / stepbone))

func _clear_polygon() -> void:
	if polygon2d == null:
		return
	_update_vars()
	polygon2d.set_polygons([])
	polygon2d.set_internal_vertex_count(0)
	polygon2d.set_uv(PackedVector2Array([]))

func _create_per_vert() -> PackedVector2Array:
	var poly = []
	var init_size = polygon2d.polygon.size()
	for n in range(init_size):
		var next_n = n + 1 if init_size > n + 1 else 0
		var p1 = polygon2d.polygon[n]
		var p2 = polygon2d.polygon[next_n]
		var dir = p1.direction_to(p2)
		var dist = p1.distance_to(p2)
		var num = dist / step
		for _n in range(num + 1):
			var point = p1 + (dir * _n * step)
			if point.distance_to(p2) > step / 3:
				poly.append(point)
					
	polygon2d.set_polygon(PackedVector2Array(poly))
	polygon_verts = PackedVector2Array(poly)
	return polygon2d.get_polygon()

func _create_internal_vert() -> void:
	var in_vert_count = 0
	var new_vert = polygon2d.get_polygon()
	
	for y in range(polygon_num.y + 1):
		for x in range(polygon_num.x + 1):
			var point = Vector2(lim_min.x + (x * step), lim_min.y + (y * step))
			if _is_point_in_area(point):
				var is_fit = true
				for vert in polygon_verts:
					if point.distance_to(vert) < step / 3:
						is_fit = false
						break
				if is_fit:
					new_vert.append(point)
					in_vert_count += 1
	
	polygon2d.set_polygon(new_vert)
	polygon2d.set_internal_vertex_count(in_vert_count)

func _is_point_in_area(point: Vector2) -> bool:
	return Geometry2D.is_point_in_polygon(point, polygon_verts)

func _triangulate_polygon() -> void:
	var polygon = polygon2d.get_polygon()
	var points = Array(Geometry2D.triangulate_delaunay(polygon))
	var polygons = []
	for i in range(ceil(len(points) / 3)):
		var triangle = []
		for n in range(3):
			triangle.append(points.pop_front())
		var a = polygon[triangle[0]]
		var b = polygon[triangle[1]]
		var c = polygon[triangle[2]]
		
		if _is_line_in_area(a,b) and _is_line_in_area(b,c) and _is_line_in_area(c,a):
			polygons.append(PackedInt32Array(triangle))
	polygon2d.set_polygons(polygons)

func _is_line_in_area(a: Vector2, b: Vector2) -> bool:
	return _is_point_in_area(a + a.direction_to(b) * 0.01) \
		and _is_point_in_area(b + b.direction_to(a) * 0.01) \
		and _is_point_in_area((a + b) / 2)

func _on_weights_pressed() -> void:
	if !_is_polygon_selected():
		return
	_update_vars()
	var skeleton := polygon2d.get_node(polygon2d.skeleton) as Skeleton2D
	var weights = []
	var bone_count = polygon2d.get_bone_count()
	var points_size = polygon2d.polygon.size()
	
	weights.resize(bone_count)
	for bone_index in range(bone_count):
		weights[bone_index] = []
		weights[bone_index].resize(points_size)

	for point_index in range(polygon2d.polygon.size()):
		var point = polygon2d.polygon[point_index] + polygon2d.global_position
		var bones_data = []
		var dist_sum = 0
		
		for bone_index in range(bone_count):
			var bone = skeleton.get_bone(bone_index)
			var dist = point.distance_to(bone.global_position)
			bones_data.append([bone_index, dist, null])
			dist_sum += dist
		
		bones_data.sort_custom(_sort_nearest_point)
		var total_bone_sum = 0
		var weights_to_calc = bone_count
		if weights_to_calc > 2:
			weights_to_calc = 2
			dist_sum = (bones_data[0][1] + bones_data[1][1])
		for bone_data_index in range(weights_to_calc):
			var bone_data = bones_data[bone_data_index]
			var bone_index = bones_data[bone_data_index][0]
			if bone_data[1] < 0.1:
				bone_data[2] = 1
			else:
				bone_data[2] = (dist_sum - bone_data[1]) / dist_sum
			
			if bone_data[2] > 0.4:
				weights[bone_index][point_index] = bone_data[2]
			else:
				weights[bone_index][point_index] = 0

	for bone_index in range(bone_count):
		polygon2d.set_bone_weights(bone_index, PackedFloat32Array(weights[bone_index]))

func _sort_nearest_point(a, b) -> bool:
	return a[1] < b[1]

func _on_create_skeleton_pressed():
	if !_is_polygon_selected():
		return
	_update_vars()
	for child in polygon2d.get_children():
		if child is Skeleton2D:
			child.queue_free()
	var skeleton2D = Skeleton2D.new()
	skeleton2D.name = "Skeleton2D"
	polygon2d.add_child(skeleton2D)
	skeleton2D.owner = editor.get_edited_scene_root()
	skeleton2D.get_relative
	polygon2d.skeleton = NodePath(skeleton2D.name)
	_create_bones(skeleton2D)

func _create_bones(skeleton2D: Skeleton2D) -> void:
	var bones: Array[Bone2D] = []
	var bone_matrix = []
	bone_matrix.resize(polygon_bone_num.y + 1)
	for y in range(polygon_bone_num.y + 1):
		var row_array = []
		row_array.resize(polygon_bone_num.x + 1)
		bone_matrix[y] = row_array
		for x in range(polygon_bone_num.x + 1):
			var point = Vector2(lim_min.x + (x * stepbone), lim_min.y + (y * stepbone))
			
			if _is_point_in_area(point):
				var is_fit = true
				if is_fit:
					var bone := Bone2D.new()
					bone.name = "Bone2D"+str(x)+str(y)
					bone.global_position = point
					bone.set_autocalculate_length_and_angle(false)
					skeleton2D.add_child(bone)
					bone.owner = editor.get_edited_scene_root()
					bones.append(bone)
					bone_matrix[y][x] = bone
	var center_bone = bone_matrix[(polygon_bone_num.y + 1) / 2][(polygon_bone_num.x + 1) / 2]
	for bone in bones:
		bone.look_at(center_bone.global_position)
		bone.set_script(LookAtCenter2D)
		(bone as LookAtCenter2D).follow = "../" + center_bone.name

func _create_rigid_body(skeleton: Skeleton2D, bone: Bone2D):
	var rigid_body = RigidBody2D.new()
	rigid_bodies_root.add_child(rigid_body)
	rigid_body.owner = editor.get_edited_scene_root()
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = steprigidbody / 2
	collision_shape.shape = shape
	rigid_body.mass = mass
	rigid_body.global_position = bone.global_position
	rigid_body.add_child(collision_shape)
	collision_shape.owner = editor.get_edited_scene_root()
	rigid_body.collision_layer = collision_layer
	rigid_body.collision_mask = collision_mask
	var remote_transform = RemoteTransform2D.new()
	rigid_body.add_child(remote_transform)
	remote_transform.owner = editor.get_edited_scene_root()
	remote_transform.remote_path = "../../../" + skeleton.name + "/" + bone.name
	remote_transform.update_rotation = false
	remote_transform.update_scale = false
	return rigid_body

func _add_rigid_body_bones():
	var skeleton := polygon2d.get_node(polygon2d.skeleton) as Skeleton2D
	var bones = skeleton.get_children()
	var link_pair = {}
	for bone in bones:
		var rigid_body = _create_rigid_body(skeleton, bone)

func _on_generate_rigidbodies_pressed():
	if !_is_polygon_selected():
		return
	_update_vars()
	for child in polygon2d.get_children():
		if not child is Skeleton2D:
			child.queue_free()
	rigid_bodies_root = Node2D.new()
	rigid_bodies_root.name = "RigidBodiesRoot"
	polygon2d.add_child(rigid_bodies_root)
	rigid_bodies_root.owner = editor.get_edited_scene_root()
	_add_rigid_body_bones()

func _on_generate_joints_pressed():
	if !_is_polygon_selected():
		return
	_update_vars()
	var rigid_bodies: Array[RigidBody2D]
	for child in polygon2d.get_children():
		if not child is Skeleton2D:
			var children = child.get_children()
			for rigid_body in children:
				rigid_bodies.append(rigid_body as RigidBody2D)
				for link in rigid_body.get_children():
					if link is DampedSpringJoint2D:
						link.queue_free()
	_add_joints(rigid_bodies)

func _add_joints(rigid_bodies: Array[RigidBody2D]):
	for node_a in rigid_bodies:
		for node_b in rigid_bodies:
			if node_a == node_b or \
				node_a.global_position.distance_to(node_b.global_position) > stepbone * 2:
				continue
			var joint = DampedSpringJoint2D.new()
			joint.node_a = ".."
			joint.node_b = "../../" + node_b.name
			joint.stiffness = stiffness
			joint.disable_collision = disable_collision
			joint.length = ((node_a.global_position - node_b.global_position).length())
			joint.rest_length = ((node_a.global_position - node_b.global_position).length())
			var angle = (node_a.global_position - node_b.global_position).angle()
			joint.global_rotation = angle + PI/2
			joint.damping = damping
			node_a.add_child(joint)
			joint.global_position = node_a.global_position
			joint.owner = editor.get_edited_scene_root()

func _on_steplabel_value_changed(value):
	step = value

func _on_stepbonelabel_value_changed(value):
	stepbone = value

func _on_stiffnesslabel_value_changed(value):
	stiffness = value

func _on_dampinglabel_value_changed(value):
	damping = value

func _on_disablecollision_toggled(button_pressed):
	disable_collision = button_pressed

func _on_collisionlayer_value_changed(value):
	collision_layer = value

func _on_collisionmask_value_changed(value):
	collision_mask = value

func _on_mass_value_changed(value):
	mass = value

func _on_radiuslabel_value_changed(value):
	steprigidbody = value

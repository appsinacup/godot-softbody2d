@tool
@icon("res://addons/softbody2d/softbody2d.svg")
extends Polygon2D

## A 2D Softbody.
##
## Models an object as a softbody by creating:[br]
## - a set of [RigidBody2D] nodes, each with one [CollisionShape2D] with a [Shape2D] and a set of [Joint2D] nodes connected to adjacent bodies.[br]
## - one [Skeleton2D] node with a set of [Bone2D] nodes, each getting their position set from a [RemoteTransform2D] node, located on the rigidbodies.[br]
##
## @tutorial: https://appsinacup.com/softbody2d-tutorial/

class_name SoftBody2D

## Called after a joint is removed.
signal joint_removed(rigid_body_a: SoftBodyChild, rigid_body_b: SoftBodyChild)

#region Properties

func _set(property, value):
	if property == "texture":
		texture = value as Texture2D
		vertex_interval = texture.get_size().length() / 10
		create_softbody2d()
		return true
	return false

func _get_configuration_warnings():
	if texture == null:
		return ["No texture set."]
	if get_child_count() == 0:
		return ["No rigidbodies created. Check the vertex_interval to be lower than texture size."]
	if !get_node_or_null(skeleton):
		return ["Skeleton2D empty."]
	return []


## Draw regions of edge polygon.[br]
## 1a. Creates edge vertices from texture.[br]
## 1b. Creates multiple voronoi regions with roughly same total size as the edge vertices AABB.[br]
## 1c. Delete the voronoi regions not inside the polygon.[br]
@export var draw_regions := false :
	set (value):
		if draw_regions == value:
			return
		draw_regions = value
		create_softbody2d()
	get:
		return draw_regions

## Distance between internal vertices
@export_range(0.1, 50, 1, "or_greater") var vertex_interval := 30:
	set (value):
		if vertex_interval == value:
			return
		vertex_interval = value
		radius = value - value * 0.2
		create_softbody2d()
	get:
		return vertex_interval

@export_group("Collision")
## Sets the [member PhysicsBody2D.collision_layer].
@export_flags_2d_physics var collision_layer := 1 :
	set (value):
		if collision_layer == value:
			return
		collision_layer = value
		for body in get_rigid_bodies():
			body.rigidbody.collision_layer = collision_layer
	get:
		return collision_layer
## Sets the [member PhysicsBody2D.collision_mask].
@export_flags_2d_physics var collision_mask := 1 :
	set (value):
		if collision_mask == value:
			return
		collision_mask = value
		for body in get_rigid_bodies():
			body.rigidbody.collision_mask = collision_mask
	get:
		return collision_mask

#endregion

#region Image
## Properties that relate to the image used to generate the polygon
@export_group("Image")
## Create softbody with holes
@export var exclude_texture: Texture2D:
	set (value):
		if exclude_texture == value:
			return
		exclude_texture = value
		create_softbody2d()
	get:
		return exclude_texture
## Epsilon for making polygon from texture. Smaller value results in more accurate result, but more vertices
@export_range(0.1, 50, 0.01, "or_greater") var texture_epsilon := 1:
	set (value):
		if texture_epsilon == value:
			return
		texture_epsilon = value
		create_softbody2d()
	get:
		return texture_epsilon
## Min alpha to consider the point part of polygon
@export_range(0.01, 1, 0.01, "or_greater") var min_alpha := 0.05:
	set (value):
		if min_alpha == value:
			return
		min_alpha = value
		create_softbody2d()
	get:
		return min_alpha
## Amount to grow or shrink the image with in pixels. Adds dilatation if positive, if negative adds erosion.
@export_range(-50, 50, 1, "or_greater") var margin_pixels := 0:
	set (value):
		if margin_pixels == value:
			return
		margin_pixels = value
		create_softbody2d()
	get:
		return margin_pixels
#endregion

#region Polygon
## Properties that relate to the generated polygon.
@export_group("Polygon")

## Offset from Texture Center for the polygon. Use this if some rigidbodies are positioned weirdly.
@export var polygon_offset := Vector2():
	set (value):
		if polygon_offset == value:
			return
		polygon_offset = value
		create_softbody2d()
	get:
		return polygon_offset
## Minimum area of a region that was cut. If it's less than this, it will be added to another region close to it.
@export_range(0.01, 1, 0.01) var min_area:= 0.35:
	set (value):
		if min_area == value:
			return
		min_area = value
		create_softbody2d()
	get:
		return min_area

const MAX_REGIONS := 200

#endregion

#region Joint

## Set properties related to the generated joints between rigidbodies.
@export_group("Joint")

## Should create a joint between node a->b and b->a (2 joints per 2 nodes) or just 1 joint per 2 nodes.
@export var joint_both_ways : bool = true:
	set (value):
		if joint_both_ways == value:
			return
		joint_both_ways = value
		create_softbody2d()
	get:
		return joint_both_ways
## The joint type. Pin yields a more sturdy softbody, and uses [PinJoint2D], while sprint a more soft one, and uses [DampedSpringJoint2D].
@export_enum("pin", "spring") var joint_type:= "pin":
	set (value):
		if joint_type == value:
			return
		joint_type = value
		create_softbody2d()
	get:
		return joint_type
## Sets the [member Joint2D.bias] property of the joint.
@export_range(0, 2, 0.1, "or_greater") var bias : float = 0 :
	set (value):
		if bias == value:
			return
		bias = value
		for body in get_rigid_bodies():
			for joint in body.joints:
				joint.bias = bias
	get:
		return bias

## Sets the [member Joint2D.disable_collision] property of the joint.
@export var disable_collision := true :
	set (value):
		if disable_collision == value:
			return
		disable_collision = value
		for body in get_rigid_bodies():
			for joint in body.joints:
				joint.disable_collision = disable_collision
	get:
		return disable_collision
@export_subgroup("DampedSpringJoint")
## Relevant only if you picked [member SoftBody2D.joint_type] = "spring". Sets the [member DampedSpringJoint2D.stiffness] property of the joint.
@export_range(0.1, 128, 0.1, "or_greater") var stiffness: float = 20  :
	set (value):
		if stiffness == value:
			return
		stiffness = value
		for body in get_rigid_bodies():
			for joint in body.joints:
				if joint is DampedSpringJoint2D:
					joint.stiffness = stiffness
	get:
		return stiffness
## Relevant only if you picked [member SoftBody2D.joint_type] = "spring". Sets the [member DampedSpringJoint2D.damping] property of the joint.
@export_range(0.1, 16, 0.1, "or_greater") var damping: float = 0.7  :
	set (value):
		if damping == value:
			return
		damping = value
		for body in get_rigid_bodies():
			for joint in body.joints:
				if joint is DampedSpringJoint2D:
					joint.damping = damping
	get:
		return damping
## Sets the [member DampedSpringJoint2D.rest_length] property of the joint based on the distance between bones.
@export_range(0, 2, 0.1, "or_greater") var rest_length_ratio : float = 1 :
	set (value):
		if rest_length_ratio == value:
			return
		rest_length_ratio = value
		for body in get_rigid_bodies():
			for joint in body.joints:
				if joint is DampedSpringJoint2D:
					joint.rest_length = joint.get_meta("joint_distance") * rest_length_ratio
	get:
		return rest_length_ratio
## Sets the [member DampedSpringJoint2D.length] property of the joint based on the distance between bones.
@export_range(0, 2, 0.1, "or_greater") var length_ratio : float = 1:
	set (value):
		if length_ratio == value:
			return
		length_ratio = value
		for body in get_rigid_bodies():
			for joint in body.joints:
				if joint is DampedSpringJoint2D:
					joint.length = joint.get_meta("joint_distance") * length_ratio
	get:
		return length_ratio

@export_subgroup("PinJoint")
## Relevant only if you picked [member SoftBody2D.joint_type] = "pin". Sets the [member PinJoint2D.softness] property of the joint.
@export_range(0, 100, 0.1, "or_greater") var softness: float = 60 :
	set (value):
		if softness == value:
			return
		softness = value
		for body in get_rigid_bodies():
			for joint in body.joints:
				if joint is PinJoint2D:
					joint.softness = softness
	get:
		return softness

#endregion

#region RigidBody

## Properties that change every rigidbody created for this softbody.
@export_group("RigidBody")
## Sets the [member Shape2D size].
@export_range(2, 50, 1, "or_greater") var radius := 20 :
	set (value):
		if radius == value:
			return
		radius = value
		for body in get_rigid_bodies():
			var shape = body.shape
			if shape_type == "Circle":
				shape.shape.radius = radius / 2.0
			elif shape_type == "Rectangle":
				shape.shape.size = Vector2(radius, radius)
			else:
				push_error("Wrong shape used for shape_type. " + shape_type)
	get:
		return radius

## Sets the total mass. Each rigidbody will have some [member RigidBody2D.mass] totaling this amount.
@export_range(0.01, 100, 0.1, "or_greater") var total_mass := 1.0 :
	set (value):
		if total_mass == value:
			return
		total_mass = value
		if !get_node_or_null(skeleton):
			push_warning("Skeleton2D not created")
			return
		for body in get_rigid_bodies():
			if "mass" in body.rigidbody:
				body.rigidbody.mass = total_mass / get_rigid_bodies().size()
	get:
		return total_mass
## Sets the gravity scale. Each rigidbody will have [member RigidBody2D.gravity_scale] set to this amount.
@export_range(-1, 1, 0.01) var gravity_scale := 1.0 :
	set (value):
		if gravity_scale == value:
			return
		gravity_scale = value
		for body in get_rigid_bodies():
			if "gravity_scale" in body.rigidbody:
				body.rigidbody.gravity_scale = gravity_scale
	get:
		return gravity_scale

## Sets the constant force. Each rigidbody will have [member RigidBody2D.constant_force] set to this amount.
@export var constant_force := Vector2() :
	set (value):
		if constant_force == value:
			return
		constant_force = value
		for body in get_rigid_bodies():
			if "constant_force" in body.rigidbody:
				body.rigidbody.constant_force = constant_force
	get:
		return constant_force

## Sets the constant torque. Each rigidbody will have [member RigidBody2D.constant_torque] set to this amount.
@export var constant_torque := 0.0 :
	set (value):
		if constant_torque == value:
			return
		constant_torque = value
		for body in get_rigid_bodies():
			if "constant_torque" in body.rigidbody:
				body.rigidbody.constant_torque = constant_torque
	get:
		return constant_torque

## What kind of shape to create for each rigidbody.
@export_enum("Circle", "Rectangle") var shape_type:= "Circle" :
	set (value):
		if shape_type == value:
			return
		shape_type = value
		for body in get_rigid_bodies():
			var shape = body.shape
			if shape_type == "Circle":
				shape.shape = CircleShape2D.new()
				shape.shape.resource_local_to_scene = true
				shape.shape.radius = radius / 2.0
			elif shape_type == "Rectangle":
				shape.shape = RectangleShape2D.new()
				shape.shape.resource_local_to_scene = true
				shape.shape.size = Vector2(radius, radius)
			else:
				push_error("Wrong shape used for shape_type")
	get:
		return shape_type
## If this is greater than 0, the softbody will be breakable. This number is multiplied by [member SoftBody2D.vertex_interval]
@export_range(0, 2, 0.1, "or_greater") var break_distance_ratio:= 0.0

## A custom rigidbody scene from which to create the rigidbody. Useful if you want to have custom rigidbodies with custom scripts.
@export var rigidbody_scene: PackedScene :
	set (value):
		if rigidbody_scene == value:
			return
		rigidbody_scene = value
		create_softbody2d()
	get:
		return rigidbody_scene

## Sets the [member RigidBody2D.physics_material_override].
@export var physics_material_override: PhysicsMaterial :
	set (value):
		if physics_material_override == value:
			return
		physics_material_override = value
		for body in get_rigid_bodies():
			body.rigidbody.physics_material_override = physics_material_override
	get:
		return physics_material_override

#endregion

#region CreateSoftbody

## Create debug regions. Good to visualize how softbody regions will look in the end
func create_regions():
	var voronoi_regions = _create_polygon2d()
	if (!voronoi_regions):
		return
	var voronoi_node:= Voronoi2D.new()
	add_child(voronoi_node)
	var polygon_limits = _calculate_polygon_limits()
	var lim_min = polygon_limits[0]
	var lim_max = polygon_limits[1]
	var polygon_size = lim_max - lim_min
	voronoi_node.size = polygon_size;
	voronoi_node.distance_between_points = vertex_interval
	if Engine.is_editor_hint():
		voronoi_node.set_owner(get_tree().get_edited_scene_root())
	voronoi_node.draw_voronoi(voronoi_regions[0])

## Call this to create a new softbody at runtime.
func create_softbody2d():
	# At runtime if we already have skeleton, don't create it.
	if !Engine.is_editor_hint() || !get_tree():
		return
	clear_softbody2d()
	if draw_regions:
		create_regions()
		return
	var voronoi = _create_polygon2d()
	if (!voronoi || voronoi[0].is_empty()):
		return
	var skeleton2d_and_connected_bones = _construct_skeleton2d(voronoi[0], voronoi[1])
	_create_rigidbodies2d(skeleton2d_and_connected_bones[0], skeleton2d_and_connected_bones[1])
	_update_soft_body_rigidbodies(skeleton2d_and_connected_bones[0])
	

## Call this to clear all children, polygons and bones.
func clear_softbody2d():
	_clear_polygon()
	for child in get_children():
		child.queue_free()
		remove_child(child)
	clear_bones()
	_soft_body_rigidbodies_array = []

func _clear_polygon():
	polygon.clear()
	polygons.clear()
	uv.clear()
	internal_vertex_count = 0

#endregion

#region Create Polygon

func _create_polygon2d():
	if texture == null:
		push_error("Texture is required to generate SoftBody2D")
		return
	var outside_polygon = _create_external_vertices_from_texture(texture)
	set_polygon(outside_polygon)
	set_uv(PackedVector2Array([]))
	return _create_internal_vertices()

func _create_external_vertices_from_texture(texture, inside = true) -> PackedVector2Array:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(texture.get_image(), min_alpha)
	var rect = Rect2(0, 0, texture.get_width(), texture.get_height())
	if margin_pixels != 0:
		if inside:
			bitmap.grow_mask(margin_pixels, rect)
		else:
			bitmap.grow_mask(-margin_pixels, rect)
	var poly = bitmap.opaque_to_polygons(rect, texture_epsilon)
	if poly.is_empty():
		push_error("Could not generate polygon outline")
	if poly.size() != 1:
		var resulting_poly = PackedVector2Array()
		for poly_b in poly:
			var merged_polygon := Geometry2D.merge_polygons(resulting_poly, poly_b)
			if merged_polygon.size() != 1:
				push_error("More than 1 polygon resulted from image. Tried to merge them but failed. Try to change the min_alpha to something higher.")
				break
			resulting_poly = merged_polygon[0]
		poly[0] = resulting_poly
	if poly[0].is_empty():
		push_error("Resulting polygon is empty")
	return poly[0]

func _create_internal_vertices():
	var polygon_verts = _get_polygon_verts()
	var polygon_limits = _calculate_polygon_limits()
	var lim_min = polygon_limits[0]
	var lim_max = polygon_limits[1]
	var polygon_size = lim_max - lim_min
	var polygon_num = Vector2(int(polygon_size.x / vertex_interval), int(polygon_size.y / vertex_interval))
	return _generate_points_voronoi(lim_min, lim_max, polygon_verts)
	
func _get_polygon_verts():
	var polygon_verts = polygon.duplicate()
	if polygon_verts.size() != 0:
		var new_size = polygon_verts.size() - internal_vertex_count
		if new_size > 0:
			polygon_verts.resize(new_size)
	return polygon_verts

func _generate_points_voronoi(lim_min: Vector2, lim_max: Vector2, polygon_verts):
	var polygon_size = lim_max - lim_min
	var polygon_num = Vector2(int(polygon_size.x / vertex_interval), int(polygon_size.y / vertex_interval))
	var voronoi = Voronoi2D.generate_voronoi(polygon_size * 1.2, vertex_interval, \
		lim_min + polygon_offset)
	var polygons = []
	var new_voronoi: Array[Voronoi2D.VoronoiRegion2D]
	var voronoi_regions_to_move = []
	var exclude_polygon = PackedVector2Array([])
	# read exclude polygon
	if exclude_texture:
		exclude_polygon = _create_external_vertices_from_texture(exclude_texture, false)
	# find out what regions to remove
	for region_idx in len(voronoi):
		var each: Voronoi2D.VoronoiRegion2D = voronoi[region_idx]
		var total_area := 0.01
		for polygon_point in each.polygon_points:
			total_area += _polygon_area(polygon_point)
		# initially the intersect is the starting polygon
		var intersect: Array[PackedVector2Array]
		# if there is a point not inside the polygon vertices, cut it.
		# it may result in multiple polygons
		for voronoi_polygon in each.polygon_points:
			var added := false
			for polygon_vert in voronoi_polygon:
				if not _is_point_in_area(polygon_vert, polygon_verts, 1.01):
					intersect.append_array(Geometry2D.intersect_polygons(polygon_verts, voronoi_polygon))
					added = true
					break
			if !added:
				intersect.append(voronoi_polygon)
		# exclude eclude_polygon part
		var new_intersect_poly: Array[PackedVector2Array]
		for intersect_poly in intersect:
			new_intersect_poly.append_array(Geometry2D.clip_polygons(intersect_poly, exclude_polygon))
		intersect = new_intersect_poly
		if !intersect.is_empty():
			each.polygon_points = intersect
			# update center if we change the polygon
			each.fixed_center = _polygon_center(each.polygon_points)
			each.center = _polygon_center(each.polygon_points)
			new_voronoi.append(each)
			var cut_area := 0.0
			for intersected in intersect:
				cut_area += _polygon_area(intersected)
			var is_middle_inside = _is_point_in_area(each.fixed_center, polygon_verts, 1.1)
			# if area of polygon is too smal, move it to another region
			if cut_area / total_area < min_area || !is_middle_inside:
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
			var current_dist = each.fixed_center.distance_to(to_remove.fixed_center)
			if dist < 0 or dist > current_dist:
				dist = current_dist
				closest_idx = voronoi_idx
		new_voronoi[closest_idx].polygon_points.append_array(to_remove.polygon_points)
		# update center if we change the polygon
		new_voronoi[closest_idx].fixed_center = _polygon_center(new_voronoi[closest_idx].polygon_points)
		new_voronoi[closest_idx].center = _polygon_center(new_voronoi[closest_idx].polygon_points)
	voronoi_regions_to_move.sort_custom(func (x,y): return x>y)
	# remove them
	for region_to_move in voronoi_regions_to_move:
		new_voronoi.remove_at(region_to_move)
	# add remaining
	var new_vert = get_polygon()
	var bone_vert_arr = []
	var in_vert_count = 0
	if new_voronoi.size() > MAX_REGIONS:
		push_error("Too many regions. Current max_regions is " + str(MAX_REGIONS) + ", total current regions " + str(new_voronoi.size()) + ". Increase the vertex_interval.")
		new_voronoi = []
	for each in new_voronoi:
		# multiple polygons
		var bone_vert_combined_array := []
		for poly in each.polygon_points:
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

#endregion

#region Helpers

func _polygon_center(polygon_verts: Array[PackedVector2Array]) -> Vector2:
	var min_vec = polygon_verts[0][0]
	var max_vec = polygon_verts[0][0]
	for poly in polygon_verts:
		for i in poly.size():
			min_vec = _minv(min_vec, poly[i])
			max_vec = _maxv(max_vec, poly[i])
	return min_vec + (max_vec - min_vec)/2

func _minv(curvec,newvec):
	return Vector2(min(curvec.x,newvec.x),min(curvec.y,newvec.y))

func _maxv(curvec,newvec):
	return Vector2(max(curvec.x,newvec.x),max(curvec.y,newvec.y))
		
func _polygon_area(polygon_verts: PackedVector2Array) -> float:
	var area := 0.0;

	for i in polygon_verts.size():
		var j = (i + 1)%polygon_verts.size();
		area += 0.5 * (polygon_verts[i].x*polygon_verts[j].y -  polygon_verts[j].x*polygon_verts[i].y);

	return area
	
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

func _is_point_in_area(point: Vector2, polygon_verts: PackedVector2Array, scale_amount := 1.01) -> bool:
	var scaled_poly = polygon_verts.duplicate()
	var center = Vector2()
	for vert in polygon_verts:
		center = center + vert
	center = center / len(polygon_verts)
	for i in len(scaled_poly):
		scaled_poly[i] = (scaled_poly[i] - center) * scale_amount + center
	return Geometry2D.is_point_in_polygon(point, scaled_poly)

func _distance_from_point_to_polygon(point: Vector2, polygon_verts: PackedVector2Array):
	var min_dist:= -1.0
	for i in len(polygon_verts):
		var p1 = polygon_verts[i]
		var p2 = polygon_verts[(i+1)%len(polygon_verts)]
		var r = (p2 - p1).dot(point - p1)
		r /= (p2 - p1).length() ** 2
		var dist = -1
		if r < 0:
			dist = (point - p1).length()
		elif r > 1:
			dist = (p2 - point).length()
		else:
			dist = sqrt((point - p1).length_squared() - (r * (p2-p1)).length_squared())
		if min_dist < 0:
			min_dist = dist
		if dist > 0 && min_dist > dist:
			min_dist = dist
	return min_dist

func _triangulate_polygon(polygon: PackedVector2Array, polygon_verts: PackedVector2Array, offset:= 0, validate_inside:= false):
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

#endregion

#region Create Skeleton

func _create_skeleton() -> Skeleton2D:
	var skeleton2d = Skeleton2D.new()
	skeleton2d.resource_local_to_scene = true
	skeleton2d.name = "Skeleton2D"
	add_child(skeleton2d)
	if Engine.is_editor_hint():
		skeleton2d.set_owner(get_tree().get_edited_scene_root())
	skeleton = NodePath(skeleton2d.name)
	clear_bones()
	return skeleton2d

func _construct_skeleton2d(voronoi: Array[Voronoi2D.VoronoiRegion2D], bone_vert_arr) -> Array:
	var skeleton_nodes = get_children().filter(func (node): return node is Skeleton2D)
	var skeleton2d : Skeleton2D
	if len(skeleton_nodes) == 0:
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
	var weights_and_connected_nodes = _generate_weights(bones, voronoi, bone_vert_arr)
	var weights = weights_and_connected_nodes[0]
	var bone_count = skeleton2d.get_bone_count()
	for bone_index in len(bones):
		var bone : Bone2D = bones[bone_index]
		bone.set_meta("vert_owned", bone_vert_arr[bone_index])
		skeleton2d.add_child(bone)
		add_bone(NodePath(bone.name), PackedFloat32Array(weights[bone_index]))
		if Engine.is_editor_hint():
			bone.set_owner(get_tree().get_edited_scene_root())
	return [skeleton2d, weights_and_connected_nodes[1]]

func _create_bones(voronoi: Array[Voronoi2D.VoronoiRegion2D]) -> Array[Bone2D]:
	var bones: Array[Bone2D] = []
	var polygon_limits = _calculate_polygon_limits()
	var polygon_verts = _get_polygon_verts()
	var bone_idx = 0
	for each in voronoi:
		var bone := Bone2D.new()
		var point = each.fixed_center
		bone.name = "Bone-"+str(bone_idx)
		bone_idx += 1
		bone.global_position = point
		bone.set_autocalculate_length_and_angle(false)
		bone.set_length(vertex_interval)
		bones.append(bone)
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

func _generate_weights(bones: Array[Bone2D], voronoi, bone_vert_arr):
	var weights = []
	var bone_count = len(bones)
	var points_size = polygon.size()
	weights.resize(bone_count)
	for bone_index in bone_count:
		weights[bone_index] = []
		weights[bone_index].resize(points_size)
	# Set weights to bones and regions that they are part of
	for bone_index in bone_count:
		for point_idx in bone_vert_arr[bone_index]:
			weights[bone_index][point_idx] = 1
	var bone_connections := []
	for bone_index in bone_count:
		bone_connections.append({})
	# Set weights to regions close to the bone also
	# One point should be pulled on at most 2 bones
	for point_index in points_size:
		var point := polygon[point_index]
		
		var bones_connected_to_point := []
		for bone_index in bone_count:
			for poly in voronoi[bone_index].polygon_points:
				for poly_point in poly:
					if point.distance_squared_to(poly_point) < 2:
						bones_connected_to_point.append(bone_index)
						weights[bone_index][point_index] = 1
		# connect all bones connected to this point to each other
		for bone_connected_to_point in bones_connected_to_point:
			for other_bone_connected_to_point in bones_connected_to_point:
				if bone_connected_to_point != other_bone_connected_to_point:
					bone_connections[bone_connected_to_point][other_bone_connected_to_point] = true
	return [weights, bone_connections]

#endregion

#region Create Rigidbody

func _create_rigidbodies2d(skeleton: Skeleton2D, connected_bones: Array):
	for child in get_children():
		if not child is Skeleton2D:
			remove_child(child)
			child.queue_free()
	var rigidbodies := _add_rigid_body_for_bones(skeleton)
	_generate_joints(rigidbodies, connected_bones)

func _add_rigid_body_for_bones(skeleton: Skeleton2D) -> Array[RigidBody2D]:
	var bones = skeleton.get_children()
	var link_pair = {}
	var rigidbodies : Array[RigidBody2D] = []
	var polygon_limits = _calculate_polygon_limits()
	var follow = _get_node_to_follow(bones)
	var shape: Shape2D
	if shape_type == "Circle":
		shape = CircleShape2D.new()
		shape.radius = radius / 2.0
	elif shape_type == "Rectangle":
		shape = RectangleShape2D.new()
		shape.size = Vector2(radius, radius)
	else:
		push_error("Wrong shape used for shape_type")
	shape.resource_local_to_scene = true
	var idx := 0
	for bone in bones:
		var rigid_body = _create_rigid_body(skeleton, bone, total_mass / bones.size(), bone == follow, shape)
		rigid_body.set_meta("idx", idx)
		idx += 1
		rigid_body.set_meta("bone_name", bone.name)
		rigidbodies.append(rigid_body)
	return rigidbodies

func _create_rigid_body(skeleton: Skeleton2D, bone: Bone2D, mass, is_center: bool, shape: Shape2D):
	var rigid_body: RigidBody2D
	if rigidbody_scene:
		rigid_body = rigidbody_scene.instantiate()
	else:
		rigid_body = RigidBody2D.new()
	rigid_body.name = bone.name
	var collision_shape = CollisionShape2D.new()
	collision_shape.shape = shape
	collision_shape.name = shape_type + "Shape2D"
	rigid_body.mass = mass
	rigid_body.gravity_scale = gravity_scale
	rigid_body.constant_torque = constant_torque
	rigid_body.constant_force = constant_force
	rigid_body.global_position = skeleton.transform * bone.position
	rigid_body.physics_material_override = physics_material_override
	rigid_body.add_child(collision_shape)
	rigid_body.collision_layer = collision_layer
	rigid_body.collision_mask = collision_mask
	var remote_transform = RemoteTransform2D.new()
	remote_transform.visible = false;
	remote_transform.name = "RemoteTransform2D"
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
	if rigid_body is SoftBody2DRigidBody:
		(rigid_body as SoftBody2DRigidBody).rigidbody_created.emit(collision_shape, is_center)
	return rigid_body

#endregion

#region Create Joint

func _generate_joints(rigid_bodies: Array[RigidBody2D], connected_bones: Array):
	var bones = get_node_or_null(skeleton).get_children()
	var connected_nodes_paths = []
	var connected_nodes_idx = []
	var connected_nodes = []
	for _i in bones.size():
		connected_nodes_paths.append([])
		connected_nodes_idx.append([])
		connected_nodes.append([])
	for idx_a in len(rigid_bodies):
		var node_a := rigid_bodies[idx_a]
		for idx_b in connected_bones[idx_a].keys():
			# only create joint once
			if idx_b > idx_a && !joint_both_ways:
				continue
			var node_b := rigid_bodies[idx_b]
			if node_a == node_b:
				continue
			connected_nodes_paths[idx_a].append(NodePath(bones[idx_b].name))
			connected_nodes_idx[idx_a].append(idx_b)
			connected_nodes[idx_a].append(node_b)
			if joint_type == "pin":
				var joint = PinJoint2D.new()
				joint.visible = false
				joint.name = "Joint2D-"+node_a.name+"-"+node_b.name
				joint.node_a = ".."
				joint.node_b = "../../" + node_b.name
				joint.softness = softness
				joint.disable_collision = disable_collision
				joint.look_at(node_b.global_position)
				joint.rotation = node_a.position.angle_to_point(node_b.position) - PI/2
				joint.bias = bias
				node_a.add_child(joint)
				joint.global_position = node_a.global_position
				if Engine.is_editor_hint():
					joint.set_owner(get_tree().get_edited_scene_root())
			else:
				var joint = DampedSpringJoint2D.new()
				joint.visible = false
				joint.name = "Joint2D-"+node_a.name+"-"+node_b.name
				joint.node_a = ".."
				joint.node_b = "../../" + node_b.name
				joint.stiffness = stiffness
				joint.disable_collision = disable_collision
				var joint_distance := (node_a.global_position - node_b.global_position).length()
				joint.set_meta("joint_distance", joint_distance)
				joint.rest_length = joint_distance * rest_length_ratio
				joint.length = joint_distance * length_ratio
				joint.look_at(node_b.global_position)
				joint.rotation = node_a.position.angle_to_point(node_b.position) - PI/2
				joint.damping = damping
				joint.bias = bias
				node_a.add_child(joint)
				joint.global_position = node_a.global_position
				if Engine.is_editor_hint():
					joint.set_owner(get_tree().get_edited_scene_root())
	var skeleton_node: Skeleton2D = get_node_or_null(skeleton)
	skeleton_node.visible = false;
	var skeleton_modification_stack:=SkeletonModificationStack2D.new()
	for i in bones.size():
		var skeleton_modification :=SkeletonModification2DLookAt.new()
		skeleton_modification.bone2d_node = NodePath(bones[i].name)
		skeleton_modification.resource_local_to_scene = true
		skeleton_modification.set_editor_draw_gizmo(false)
		_update_bone_lookat(skeleton_node, skeleton_modification, bones[i], connected_nodes_paths[i], i, true)
		
		bones[i].set_rest(bones[i].transform)
		skeleton_modification_stack.add_modification(skeleton_modification)
	skeleton_modification_stack.enable_all_modifications(true)
	skeleton_modification_stack.enabled = true
	skeleton_modification_stack.resource_local_to_scene = true
	skeleton_node.set_modification_stack(skeleton_modification_stack)

	for i in bones.size():
		bones[i].set_meta("idx", i)
		bones[i].set_meta("connected_nodes_paths", connected_nodes_paths[i])
		bones[i].set_meta("connected_nodes_idx", connected_nodes_idx[i])

func _update_bone_lookat(skeleton_node: Skeleton2D, skeleton_modification :SkeletonModification2DLookAt, bone: Bone2D, connected_nodes_paths, bone_idx: int, initiate_step: bool = false):
	if connected_nodes_paths.is_empty():
		skeleton_modification.enabled = false
		push_warning("Softbody" + name + " bone has no node to look at")
		# Hide this particle probably
		# TODO also deactivate it.
		create_tween().tween_property(bone, "scale", Vector2(), 1)#.finished.connect(func(): bone.process_mode = Node.PROCESS_MODE_DISABLED)
		return false
	var node_lookat = skeleton_node.get_node(connected_nodes_paths[floor(connected_nodes_paths.size()/2)])
	var prev_rotation = bone.rotation
	bone.look_at(node_lookat.global_position)
	if !initiate_step:
		skeleton_modification.set_additional_rotation(prev_rotation - bone.rotation)
	
	skeleton_node.set_bone_local_pose_override(bone_idx, bone.get_transform(), 1, true)
	skeleton_modification.target_nodepath = connected_nodes_paths[floor(connected_nodes_paths.size()/2)]
	return true
	
#endregion

# used internally, computed at _ready once
var _bones_array: Array[Bone2D]
var _skeleton_node: Skeleton2D
var _soft_body_rigidbodies_array: Array[SoftBodyChild]
var _soft_body_rigidbodies_dict: Dictionary
var _hinges_bodies:= Dictionary()
var _hinges_distances_squared := Dictionary()

# The center of the softbody. Updates dynamically if [member SoftBody2D.look_at_center] is true. If not, call [method SoftBody2D.get_bones_center_position] to compute it.
@onready var bone_center_position = get_bones_center_position()

# Called when the node enters the scene tree for the first time.
func _ready():
	if Engine.is_editor_hint():
		return
	_update_vars()

func _update_vars():
	_skeleton_node = get_node_or_null(skeleton)
	if get_child_count() == 0 || !_skeleton_node:
		push_warning("Softbody2d not created")
		return
	var bone_nodes := _skeleton_node.get_children().filter(func(node): return node is Bone2D)
	_bones_array.clear()
	for bone in bone_nodes:
		_bones_array.append(bone as Bone2D)
	_update_soft_body_rigidbodies(_skeleton_node)
	# This is needed for breaking the rigidbody
	for rigid_body in get_rigid_bodies():
		for hinge in rigid_body.joints:
			var joint := hinge as Joint2D
			_hinges_bodies[rigid_body.rigidbody.name] = get_node(NodePath(rigid_body.rigidbody.name)) as PhysicsBody2D
			_hinges_bodies[joint.node_b] = get_node(joint.node_b.get_concatenated_names().substr(4)) as PhysicsBody2D
			_hinges_distances_squared[joint.name] = _hinges_bodies[rigid_body.rigidbody.name].global_position.distance_squared_to(_hinges_bodies[joint.node_b].global_position)


#region Public API

class SoftBodyChild:
	var is_outside_facing: bool
	var rigidbody: PhysicsBody2D
	var bone: Bone2D
	var joints: Array[Joint2D]
	var shape: CollisionShape2D

## Remove joint between bone_a_name and bone_b_name. Useful if you want to make breakable softbodies.[br]
## This also handles recreating the polygon, updating the bones to look at the right target and the weights of polygons.
func remove_joint(rigid_body_child: SoftBodyChild, joint: Joint2D):
	# In case calling from @tool script
	if Engine.is_editor_hint():
		_update_vars()
	var bone_a_name : String = _hinges_bodies[rigid_body_child.rigidbody.name].get_meta("bone_name")
	var bone_b_name : String = _hinges_bodies[joint.node_b].get_meta("bone_name")
	var bone_a_idx = -1
	var bone_b_idx = -1
	var bone_a: Bone2D
	var bone_b: Bone2D
	var rigid_body_a: SoftBodyChild
	var rigid_body_b: SoftBodyChild
	# find bones and rigidbodies
	for i in len(_bones_array):
		var bone = _bones_array[i]
		if bone_a_idx != -1 && bone_b_idx != -1:
			break
		if bone.name == bone_a_name:
			bone_a_idx = i
			bone_a = bone
		if bone.name == bone_b_name:
			bone_b_idx = i
			bone_b = bone
	for rigid_body in get_rigid_bodies():
		if rigid_body_a != null && rigid_body_b != null:
			break
		if rigid_body.bone == bone_a:
			rigid_body_a = rigid_body
		if rigid_body.bone == bone_b:
			rigid_body_b = rigid_body
	
	rigid_body_a.joints.erase(joint)
	for joint_b in rigid_body_b.joints:
		if joint_b.node_a.get_name(joint_b.node_a.get_name_count() - 1) == rigid_body_a.rigidbody.name || joint_b.node_b.get_name(joint_b.node_b.get_name_count() - 1) == rigid_body_a.rigidbody.name:
			rigid_body_b.joints.erase(joint_b)
			joint_b.queue_free()
			break
	joint.queue_free()
	var owned_verts = []
	var MIN_WEIGHT = 0.01
	var bone_weight_matrix = []
	for i in get_bone_count():
		owned_verts.append(_bones_array[i].get_meta("vert_owned"))
		bone_weight_matrix.append(get_bone_weights(i))
	var bone_a_owned_verts : Array = owned_verts[bone_a_idx]
	var bone_b_owned_verts : Array = owned_verts[bone_b_idx]
	var bone_a_weights : PackedFloat32Array = bone_weight_matrix[bone_a_idx]
	var bone_b_weights : PackedFloat32Array = bone_weight_matrix[bone_b_idx]
	var connected_nodes_idx_a: Array = bone_a.get_meta("connected_nodes_idx")
	var connected_nodes_idx_b: Array = bone_b.get_meta("connected_nodes_idx")
	var bone_a_connections := {}
	var bone_b_connections := {}
	for idx in connected_nodes_idx_a:
		bone_a_connections[idx] = true
	for idx in connected_nodes_idx_b:
		bone_b_connections[idx] = true
	var bones_to_update = {}
	for i in bone_a_weights.size():
		var should_remove_a = true
		var should_remove_b = true
		# Both nodes have weight, check if it's not their own vert.
		# Remove from where it's not owned by them.
		# Also check if no other bone has this weight, if it does, leave it as it's
		# a common weight
		var is_common_weight := 0
		var shared_weight = bone_a_weights[i] > MIN_WEIGHT && bone_b_weights[i] > MIN_WEIGHT
		var common_bone := -1
		if shared_weight:
			for bone_idx in get_bone_count():
				if bone_idx != bone_a_idx && bone_idx != bone_b_idx && bone_weight_matrix[bone_idx][i] > MIN_WEIGHT:
					if bone_a_connections.has(bone_idx) && bone_b_connections.has(bone_idx):
						if is_common_weight == 0:
							is_common_weight = 1
					elif !bone_a_connections.has(bone_idx) || !bone_b_connections.has(bone_idx):
						# If there is a connection with this node but it's not it's own node, remove it
						var is_owned_vert := false
						for owned_vert in owned_verts[bone_idx]:
							if i == owned_vert:
								is_owned_vert = true
								break
						if !is_owned_vert:
							is_common_weight = -1
							bones_to_update[bone_idx] = true
							bone_weight_matrix[bone_idx][i] = 0.0
		if shared_weight && is_common_weight <= 0:
			for point_a in bone_a_owned_verts:
				if i == point_a:
					should_remove_a = false
					break
			for point_b in bone_b_owned_verts:
				if i == point_b:
					should_remove_b = false
					break
			if should_remove_a:
				bone_a_weights[i] = 0.0
			if should_remove_b:
				bone_b_weights[i] = 0.0
	set_bone_weights(bone_a_idx, bone_a_weights)
	set_bone_weights(bone_b_idx, bone_b_weights)
	# Also update bones that had common weights with a or b
	for bone_to_update in bones_to_update.keys():
		if bone_to_update != bone_a_idx && bone_to_update != bone_b_idx:
			set_bone_weights(bone_to_update, bone_weight_matrix[bone_to_update])
	var skeleton_modification_stack: SkeletonModificationStack2D = _skeleton_node.get_modification_stack()
	# Erase connected node from meta (in case we save the resource)
	var connected_nodes_paths_a: Array = bone_a.get_meta("connected_nodes_paths")
	connected_nodes_paths_a.erase(NodePath(bone_b_name))
	connected_nodes_idx_a.erase(bone_b_idx)
	bone_a.set_meta("connected_nodes_paths", connected_nodes_paths_a)
	bone_a.set_meta("connected_nodes_idx", connected_nodes_idx_a)
	var connected_nodes_paths_b: Array = bone_b.get_meta("connected_nodes_paths")
	connected_nodes_paths_b.erase(NodePath(bone_a_name))
	connected_nodes_idx_b.erase(bone_a_idx)
	bone_b.set_meta("connected_nodes_paths", connected_nodes_paths_b)
	bone_b.set_meta("connected_nodes_idx", connected_nodes_idx_b)
	# Change modification stack for nodes lookat
	var modification_a := skeleton_modification_stack.get_modification(bone_a_idx)
	var modification_b := skeleton_modification_stack.get_modification(bone_b_idx)
	if !_update_bone_lookat(_skeleton_node, skeleton_modification_stack.get_modification(bone_a_idx), bone_a, bone_a.get_meta("connected_nodes_paths"), bone_a_idx):
		var remote_transform_a : RemoteTransform2D= rigid_body_a.rigidbody.get_children().filter(func (node): return node is RemoteTransform2D)[0]
		rigid_body_a.rigidbody.rotation = bone_a.rotation
		# TODO deactivate it.
		create_tween().tween_property(rigid_body_a.shape, "scale", Vector2(), 0)#.finished.connect(func(): rigid_body_a.process_mode = Node.PROCESS_MODE_DISABLED)
		remote_transform_a.update_rotation = true
	if !_update_bone_lookat(_skeleton_node, skeleton_modification_stack.get_modification(bone_b_idx), bone_b, bone_b.get_meta("connected_nodes_paths"), bone_b_idx):
		var remote_transform_b : RemoteTransform2D= rigid_body_b.rigidbody.get_children().filter(func (node): return node is RemoteTransform2D)[0]
		rigid_body_b.rigidbody.rotation = bone_b.rotation
		# TODO deactivate it.
		create_tween().tween_property(rigid_body_b.shape, "scale", Vector2(), 0)#.finished.connect(func(): rigid_body_b.process_mode = Node.PROCESS_MODE_DISABLED)
		remote_transform_b.update_rotation = true
	skeleton_modification_stack.set_modification(bone_a_idx, modification_a)
	skeleton_modification_stack.set_modification(bone_b_idx, modification_b)
	_skeleton_node.set_modification_stack(skeleton_modification_stack)
	_update_soft_body_rigidbodies(_skeleton_node)
	
	joint_removed.emit(rigid_body_a, rigid_body_b)

## Get all the bodies, including joints and shape
func get_rigid_bodies() -> Array[SoftBodyChild]:
	if _soft_body_rigidbodies_array.is_empty() || Engine.is_editor_hint():
		if !_skeleton_node:
			_skeleton_node = get_node_or_null(skeleton)
		_update_soft_body_rigidbodies(_skeleton_node)
	return _soft_body_rigidbodies_array

## Computes the center of the softbody.
func get_bones_center_position() -> Vector2:
	var center = Vector2()
	var bodies := _soft_body_rigidbodies_array
	for body in bodies:
		center = center + body.rigidbody.global_position
	return center / bodies.size()
	
## Get the body located in the center
func get_center_body() -> SoftBodyChild:
	var bodies := get_rigid_bodies()
	var rb_array := bodies.map(func(body): return body.rigidbody)
	var center_rb := _get_node_to_follow(rb_array)
	return _soft_body_rigidbodies_dict[center_rb]

func apply_impulse(impulse: Vector2, position: Vector2 = Vector2(0, 0)):
	for softbody_el in get_rigid_bodies():
		var rigidbody := softbody_el.rigidbody
		if rigidbody is RigidBody2D:
			(rigidbody as RigidBody2D).apply_impulse(impulse, position)

func apply_force(force: Vector2, position: Vector2 = Vector2(0, 0)):
	for softbody_el in get_rigid_bodies():
		var rigidbody := softbody_el.rigidbody
		if rigidbody is RigidBody2D:
			(rigidbody as RigidBody2D).apply_force(force, position)

#endregion

func _update_soft_body_rigidbodies(skeleton_node:Skeleton2D = null):
	var result: Array[SoftBodyChild]
	var children = get_children().filter(func (node: Node): return !(node is Skeleton2D))
	if !skeleton_node:
		return
	var bones = skeleton_node.get_children()
	for child in children:
		var softbodyrb = SoftBodyChild.new()
		softbodyrb.rigidbody = child as PhysicsBody2D
		var nodes_found = bones.filter(func(bone): return bone.name == child.name);
		if bones.filter(func(bone): return bone.name == child.name).is_empty():
			push_error("Cannot find node " + child.name + " on " + skeleton_node.get_path().get_concatenated_names())
			return
		softbodyrb.bone = bones.filter(func(bone): return bone.name == child.name)[0]
		var rb_children = child.get_children()
		softbodyrb.shape = rb_children.filter(func (node): return node is CollisionShape2D)[0]
		var joints = rb_children.filter(func (node): return node is Joint2D)
		for joint in joints:
			# dont add joints we are about to delete
			if !joint.is_queued_for_deletion():
				softbodyrb.joints.append(joint)
		result.append(softbodyrb)
		_soft_body_rigidbodies_dict[softbodyrb.rigidbody] = softbodyrb
	_soft_body_rigidbodies_array = result

var _max_deletions = 6
var _last_delete_time := 0
const WAIT_DELETE_MSEC = 100

@onready var _last_texture = texture

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	# Needed in case texture changes
	if Engine.is_editor_hint():
		if texture != _last_texture:
			create_softbody2d()
		_last_texture = texture
		return
	# Wait a little before breaking bones
	if break_distance_ratio <= 0 || !_skeleton_node || Time.get_ticks_msec() - _last_delete_time < WAIT_DELETE_MSEC:
		return
	# Break at max max_deletions joints
	var deleted_count = 0
	for rigid_body in get_rigid_bodies():
		#if rigid_body.joints.size() > 2:# && rigid_body.is_outside_facing:
		for node in rigid_body.joints:
			var joint := node
			if joint == null:
				continue
			if joint.is_queued_for_deletion() || deleted_count >= _max_deletions:
				continue
			if _hinges_distances_squared[joint.name] * break_distance_ratio * break_distance_ratio * rigid_body.joints.size() < _hinges_bodies[rigid_body.rigidbody.name].global_position.distance_squared_to(_hinges_bodies[joint.node_b].global_position):
				deleted_count = deleted_count + 1
				remove_joint(rigid_body, joint)
				_last_delete_time = Time.get_ticks_msec()

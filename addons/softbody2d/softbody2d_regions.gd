@tool
class_name SoftBody2DRegions
extends RefCounted

## Region generation for [SoftBody2D]: the outline from the texture, the voronoi cells
## clipped to it, their merging and placement. Reads the softbody's generation properties
## and returns plain data; the softbody applies it. Created for one generation.

## Below this share of the clearance a body would be pointlessly small, so its region is
## merged into a neighbour instead.
const MIN_SHAPE_FIT := 0.4

var _softbody: SoftBody2D
var _outline := PackedVector2Array()


func _init(softbody: SoftBody2D) -> void:
	_softbody = softbody


## Everything the softbody needs to draw and skin itself, or an empty dictionary when the
## texture yields no usable outline. Keys: [code]outline[/code] (the outer polygon),
## [code]vertices[/code] (outline followed by every region vertex),
## [code]internal_vertex_count[/code], [code]polygons[/code] (triangles indexing vertices),
## [code]regions[/code], [code]bone_vertices[/code] (per region, the indices it owns),
## [code]clearance_outlines[/code] and [code]clearance[/code] for shape fitting.
func generate() -> Dictionary:
	if _softbody.texture == null:
		push_error("Texture is required to generate SoftBody2D")
		return {}
	_outline = outline_from_texture(_softbody.texture)
	if _outline.is_empty():
		return {}
	var limits := polygon_limits()
	return _generate_points_voronoi(limits[0], limits[1], _outline)


func outline_from_texture(source: Texture2D, inside = true) -> PackedVector2Array:
	var bitmap := BitMap.new()
	bitmap.create_from_image_alpha(source.get_image(), _softbody.min_alpha)
	var rect = Rect2(0, 0, source.get_width(), source.get_height())
	if _softbody.margin_pixels != 0:
		bitmap.grow_mask(_softbody.margin_pixels if inside else -_softbody.margin_pixels, rect)
	var poly = bitmap.opaque_to_polygons(rect, _softbody.texture_epsilon)
	if poly.is_empty():
		push_error("Could not generate polygon outline")
		return PackedVector2Array()
	if poly.size() != 1:
		var resulting_poly = PackedVector2Array()
		for poly_b in poly:
			var merged_polygon := Geometry2D.merge_polygons(resulting_poly, poly_b)
			if merged_polygon.size() != 1:
				push_error(
					(
						"More than 1 polygon resulted from image. Tried to merge them but failed. "
						+ "Try to change the min_alpha to something higher."
					)
				)
				break
			resulting_poly = merged_polygon[0]
		poly[0] = resulting_poly
	if poly[0].is_empty():
		push_error("Resulting polygon is empty")
		return PackedVector2Array()
	var result := PackedVector2Array(poly[0])
	if _softbody.bake_scale != Vector2.ONE:
		for i in result.size():
			result[i] *= _softbody.bake_scale
	return result


func _generate_points_voronoi(lim_min: Vector2, lim_max: Vector2, polygon_verts: PackedVector2Array) -> Dictionary:
	var polygon_size = lim_max - lim_min
	# Anchor the grid on the polygon itself, with one cell of margin on every side, so
	# coverage does not depend on where the opaque pixels sit inside the texture.
	var grid_margin := Vector2(_softbody.vertex_interval, _softbody.vertex_interval)
	var voronoi = Voronoi2D.generate_voronoi(
		_softbody.pattern_type,
		polygon_size + grid_margin * 2,
		_softbody.vertex_interval,
		lim_min - grid_margin + _softbody.polygon_offset
	)
	var polygons = []
	var new_voronoi: Array[Voronoi2D.VoronoiRegion2D]
	var voronoi_regions_to_move = []
	var exclude_polygon = PackedVector2Array([])
	if _softbody.exclude_texture:
		exclude_polygon = outline_from_texture(_softbody.exclude_texture, false)
	for region_idx in len(voronoi):
		var each: Voronoi2D.VoronoiRegion2D = voronoi[region_idx]
		var total_area := 0.01
		for polygon_point in each.polygon_points:
			total_area += _polygon_area(polygon_point)
		# Regions poking out of the polygon are clipped, which may leave several pieces.
		var intersect: Array[PackedVector2Array]
		for voronoi_polygon in each.polygon_points:
			var added := false
			for polygon_vert in voronoi_polygon:
				if not _is_point_in_area(polygon_vert, polygon_verts, 1.01):
					intersect.append_array(Geometry2D.intersect_polygons(polygon_verts, voronoi_polygon))
					added = true
					break
			if !added:
				intersect.append(voronoi_polygon)
		var new_intersect_poly: Array[PackedVector2Array]
		for intersect_poly in intersect:
			new_intersect_poly.append_array(Geometry2D.clip_polygons(intersect_poly, exclude_polygon))
		intersect = new_intersect_poly
		if intersect.is_empty():
			continue
		each.polygon_points = intersect
		each.fixed_center = _polygon_center(each.polygon_points)
		new_voronoi.append(each)
		var cut_area := 0.0
		for intersected in intersect:
			cut_area += _polygon_area(intersected)
		var is_middle_inside = _is_point_in_area(each.fixed_center, polygon_verts, 1.1)
		if cut_area / total_area < _softbody.min_area || !is_middle_inside:
			voronoi_regions_to_move.append(new_voronoi.size() - 1)

	# Small or outside regions are merged into their nearest surviving neighbour.
	_merge_regions(new_voronoi, voronoi_regions_to_move)
	var clearance := edge_clearance()
	var clearance_outlines: Array[PackedVector2Array] = []
	if clearance > 0.0:
		clearance_outlines.append(polygon_verts)
		if !exclude_polygon.is_empty():
			clearance_outlines.append(exclude_polygon)
		_push_clear_of_outlines(new_voronoi, polygon_verts, exclude_polygon, clearance)
		# A corner too thin to give a body even a fraction of its shape is not worth a body:
		# merge it into a neighbour and place that one again.
		var cramped := []
		for idx in new_voronoi.size():
			if _room_at(new_voronoi[idx].fixed_center, clearance_outlines) < clearance * MIN_SHAPE_FIT:
				cramped.append(idx)
		if !cramped.is_empty() && cramped.size() < new_voronoi.size():
			_merge_regions(new_voronoi, cramped)
			_push_clear_of_outlines(new_voronoi, polygon_verts, exclude_polygon, clearance)

	var new_vert := polygon_verts.duplicate()
	var bone_vert_arr = []
	var in_vert_count = 0
	if new_voronoi.size() > _softbody.MAX_REGIONS:
		push_error(
			(
				"Too many regions. Current max_regions is %d, total current regions %d. Increase the vertex_interval."
				% [_softbody.MAX_REGIONS, new_voronoi.size()]
			)
		)
		new_voronoi = []
	for each in new_voronoi:
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
	var surface_outlines: Array[PackedVector2Array] = [polygon_verts]
	if !exclude_polygon.is_empty():
		surface_outlines.append(exclude_polygon)
	var edge_regions := PackedByteArray()
	for each in new_voronoi:
		edge_regions.append(1 if _touches_outline(each, surface_outlines) else 0)
	return {
		"outline": polygon_verts,
		"edge_regions": edge_regions,
		"vertices": new_vert,
		"internal_vertex_count": in_vert_count,
		"polygons": polygons,
		"regions": new_voronoi,
		"bone_vertices": bone_vert_arr,
		"clearance_outlines": clearance_outlines,
		"clearance": clearance,
	}


# Merges each listed region into its nearest region that is not itself listed, then drops
# the listed ones. Indices refer to `regions` before removal.
func _merge_regions(regions: Array[Voronoi2D.VoronoiRegion2D], to_merge: Array) -> void:
	for region_to_move in to_merge:
		var dist := -1.0
		var closest_idx := -1
		var to_remove = regions[region_to_move]
		for voronoi_idx in regions.size():
			if voronoi_idx in to_merge:
				continue
			var current_dist = regions[voronoi_idx].fixed_center.distance_to(to_remove.fixed_center)
			if dist < 0 or dist > current_dist:
				dist = current_dist
				closest_idx = voronoi_idx
		if closest_idx == -1:
			# Every region was marked for merging, so there is nothing left to merge into.
			continue
		regions[closest_idx].polygon_points.append_array(to_remove.polygon_points)
		regions[closest_idx].fixed_center = _polygon_center(regions[closest_idx].polygon_points)
	var descending := to_merge.duplicate()
	descending.sort_custom(func(x, y): return x > y)
	for region_to_move in descending:
		regions.remove_at(region_to_move)


func _push_clear_of_outlines(
	regions: Array[Voronoi2D.VoronoiRegion2D], outline: PackedVector2Array, hole: PackedVector2Array, clearance: float
) -> void:
	for each in regions:
		each.fixed_center = keep_clear_of_outline(each.fixed_center, outline, clearance, true)
		if !hole.is_empty():
			each.fixed_center = keep_clear_of_outline(each.fixed_center, hole, clearance, false)


static func _room_at(position: Vector2, outlines: Array[PackedVector2Array]) -> float:
	var room := INF
	for outline in outlines:
		room = minf(room, position.distance_to(closest_point_on_outline(position, outline)))
	return room


# A region touches the outline when any of its vertices lies on it. Those bodies form the
# surface of the softbody, where a tear can start.
static func _touches_outline(region: Voronoi2D.VoronoiRegion2D, outlines: Array[PackedVector2Array]) -> bool:
	for poly in region.polygon_points:
		for point in poly:
			for outline in outlines:
				if point.distance_squared_to(closest_point_on_outline(point, outline)) < 1.0:
					return true
	return false


func _polygon_center(polygon_verts: Array[PackedVector2Array]) -> Vector2:
	var min_vec = polygon_verts[0][0]
	var max_vec = polygon_verts[0][0]
	for poly in polygon_verts:
		for i in poly.size():
			min_vec = min_vec.min(poly[i])
			max_vec = max_vec.max(poly[i])
	return min_vec + (max_vec - min_vec) / 2


func _polygon_area(polygon_verts: PackedVector2Array) -> float:
	var area := 0.0
	for i in polygon_verts.size():
		var j = (i + 1) % polygon_verts.size()
		area += 0.5 * (polygon_verts[i].x * polygon_verts[j].y - polygon_verts[j].x * polygon_verts[i].y)
	# Clipping can hand back clockwise polygons; callers compare magnitudes.
	return absf(area)


## Bounding box of the outline as [min, max]. Valid after [method generate].
func polygon_limits() -> Array[Vector2]:
	var lim_min = _outline[0]
	var lim_max = _outline[0]
	for point in _outline:
		lim_min = lim_min.min(point)
		lim_max = lim_max.max(point)
	return [lim_min, lim_max]


# A circle fits exactly at its radius; a square needs its half diagonal, since it rotates and
# its corners reach past a curved outline.
func edge_clearance() -> float:
	if _softbody.edge_clearance >= 0.0:
		return _softbody.edge_clearance
	if _softbody.shape_type == "Circle":
		return _softbody.radius / 2.0
	return _softbody.radius / 2.0 * sqrt(2.0)


# Pushes a body centre inward, away from the nearest point on the outline, until it is
# `clearance` from it. Moving away from the closest outline point is the local inward normal,
# which is what a wavy or concave outline needs; the texture centre is not. If the pushed
# point ends up outside the polygon (a feature thinner than two clearances) it is left as is.
static func keep_clear_of_outline(
	centre: Vector2, outline: PackedVector2Array, clearance: float, keep_inside: bool
) -> Vector2:
	var closest := closest_point_on_outline(centre, outline)
	var away := centre - closest
	var distance := away.length()
	var on_right_side := Geometry2D.is_point_in_polygon(centre, outline) == keep_inside
	if on_right_side && distance >= clearance:
		return centre
	if distance < 0.001:
		return centre
	if !on_right_side:
		away = -away
	# A feature thinner than two clearances cannot fit the whole push; take what it can.
	var attempt := clearance
	while attempt > 1.0:
		var pushed := closest + away / distance * attempt
		if Geometry2D.is_point_in_polygon(pushed, outline) == keep_inside:
			return pushed
		attempt *= 0.5
	return centre


static func closest_point_on_outline(point: Vector2, outline: PackedVector2Array) -> Vector2:
	var best := outline[0]
	var best_distance := INF
	for i in outline.size():
		var candidate := Geometry2D.get_closest_point_to_segment(point, outline[i], outline[(i + 1) % outline.size()])
		var distance := point.distance_squared_to(candidate)
		if distance < best_distance:
			best_distance = distance
			best = candidate
	return best


func _is_point_in_area(point: Vector2, polygon_verts: PackedVector2Array, scale_amount := 1.01) -> bool:
	var scaled_poly = polygon_verts.duplicate()
	var center = Vector2()
	for vert in polygon_verts:
		center = center + vert
	center = center / len(polygon_verts)
	for i in len(scaled_poly):
		scaled_poly[i] = (scaled_poly[i] - center) * scale_amount + center
	return Geometry2D.is_point_in_polygon(point, scaled_poly)


func _triangulate_polygon(
	polygon: PackedVector2Array, polygon_verts: PackedVector2Array, offset := 0, validate_inside := false
):
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
			if (
				_is_line_in_area(a, b, polygon_verts)
				and _is_line_in_area(b, c, polygon_verts)
				and _is_line_in_area(c, a, polygon_verts)
			):
				polygons.append(PackedInt32Array(triangle))
		else:
			polygons.append(PackedInt32Array(triangle))
	return polygons


func _is_line_in_area(a: Vector2, b: Vector2, polygon_verts: PackedVector2Array) -> bool:
	return (
		_is_point_in_area(a + a.direction_to(b) * 0.01, polygon_verts)
		and _is_point_in_area(b + b.direction_to(a) * 0.01, polygon_verts)
		and _is_point_in_area((a + b) / 2, polygon_verts)
	)


# A body that could not be pushed clear of the outline (a corner thinner than two
# clearances) gets a shape scaled down to the room it actually has, so it never pokes out.
# Returns 1 for the full-size shape.
static func shape_fit_at(position: Vector2, outlines: Array[PackedVector2Array], clearance: float) -> float:
	if outlines.is_empty() || clearance <= 0.0:
		return 1.0
	var room := _room_at(position, outlines)
	if room >= clearance:
		return 1.0
	return clampf(room / clearance, MIN_SHAPE_FIT, 1.0)

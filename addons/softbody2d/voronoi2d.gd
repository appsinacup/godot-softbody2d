@tool
@icon("res://addons/softbody2d/voronoi_icon.png")
class_name Voronoi2D
extends Node2D

## A Voronoi 2D regions generator. Generates chunks of 5 voronoi regions.
##
## Can be used as a helper class to generate the regions, or as a standalone node to
## display them.[br]
## As a standalone node, set [member Voronoi2D.size] for the size of the total space the
## regions will occupy, then either click [member Voronoi2D.bake] or call
## [method Voronoi2D.display_voronoi].[br]
## [br]
## Credits: Based on [b]arcanewright[/b]/[b]godot-chunked-voronoi-generator[/b]

## Bake the voronoi regions as [Polygon2D] nodes children. Removes old children.
@export var bake := false:
	set(value):
		clear = true
		display_voronoi()
	get:
		return false

## Clear the voronoi regions.
@export var clear := false:
	set(value):
		for child in get_children():
			remove_child(child)
			child.queue_free()
	get:
		return false

## Approximate size of the regions
@export var size := Vector2(100, 100)
## Type of the regions
@export var type := "hexagon"
## Distance between points in the region defined with [member Voronoi2D.size]
@export var distance_between_points: float = 10


## A Voronoi 2D Region
class VoronoiRegion2D:
	var w: int
	var h: int
	## Center of the region
	var center: Vector2
	## Fixed center of the region
	var fixed_center: Vector2
	## Points defining the region
	var polygon_points: Array[PackedVector2Array]


## Generate hexagonal points around the center
static func generate_hexagon(center: Vector2, dist: float) -> Array[PackedVector2Array]:
	dist = (2 / sqrt(3)) * dist
	var points := PackedVector2Array()
	for i in range(6):
		var angle = i * (PI / 3)
		points.append(center + Vector2(cos(angle), sin(angle)) * dist)
	return [points]


## Generate four rectangles around the center
static func generate_rectangle(center: Vector2, dist: float) -> Array[PackedVector2Array]:
	var half := dist * 0.5
	return [
		[center + Vector2(-half, -half), center + Vector2(0, -half), center, center + Vector2(-half, 0)],
		[center, center + Vector2(half, 0), center + Vector2(half, half), center + Vector2(0, half)],
		[center + Vector2(-half, 0), center, center + Vector2(0, half), center + Vector2(-half, half)],
		[center + Vector2(0, -half), center + Vector2(half, -half), center + Vector2(half, 0), center],
	]


static func generate_voronoi(
	type: String, size: Vector2, distance: float, start := Vector2()
) -> Array[VoronoiRegion2D]:
	if type == "hexagon":
		return generate_voronoi_hexagon(size, distance / 2.0, start)
	return generate_voronoi_rectangle(size, distance, start)


## Generate voronoi regions. [param start] is the top-left corner the grid is anchored at.
static func generate_voronoi_rectangle(size: Vector2, distance: float, start := Vector2()) -> Array[VoronoiRegion2D]:
	var polygons: Array[VoronoiRegion2D]
	for w in range(int(size.x / distance) + 2):
		for h in range(int(size.y / distance) + 2):
			var region := VoronoiRegion2D.new()
			region.w = w
			region.h = h
			region.center = start + Vector2(w, h) * distance
			region.fixed_center = region.center
			region.polygon_points = generate_rectangle(region.fixed_center, distance)
			polygons.append(region)
	return polygons


## Generate voronoi regions. [param start] is the top-left corner the grid is anchored at.
static func generate_voronoi_hexagon(size: Vector2, distance: float, start := Vector2()) -> Array[VoronoiRegion2D]:
	var polygons: Array[VoronoiRegion2D]
	# Flat-topped hexagons: columns sqrt(3) * 2 * distance apart, rows distance apart, with
	# even rows shifted by half a column. Counting columns by their real step keeps the grid
	# from being generated four times wider than requested.
	var column_step := sqrt(3) * 2 * distance
	for w in range(int(size.x / column_step) + 2):
		for h in range(int(size.y / distance) + 2):
			var cell := Vector2(w * sqrt(3) * 2, h)
			if h % 2 == 0:
				cell.x += sqrt(3)
			var region := VoronoiRegion2D.new()
			region.w = w
			region.h = h
			region.center = start + cell * distance
			region.fixed_center = region.center
			region.polygon_points = generate_hexagon(region.fixed_center, distance)
			polygons.append(region)
	return polygons


## Create voronoi regions from [member Voronoi2D.size] and
## [member Voronoi2D.distance_between_points], and draw them as children.
func display_voronoi():
	draw_voronoi(generate_voronoi(type, size, distance_between_points))


func draw_voronoi(voronoi: Array[VoronoiRegion2D]):
	for each in voronoi:
		_display_polygon(Vector2(), each)
		_display_point(Vector2(), each.center)


func _display_point(offset: Vector2, point: Vector2, color: Color = Color(1, 1, 1, 1)):
	var marker = Polygon2D.new()
	marker.position = point + offset
	marker.polygon = PackedVector2Array([Vector2(-2, -2), Vector2(-2, 2), Vector2(2, 2), Vector2(2, -2)])
	marker.color = color
	add_child(marker)
	if Engine.is_editor_hint():
		marker.set_owner(get_tree().get_edited_scene_root())


func _display_polygon(offset: Vector2, region: VoronoiRegion2D):
	var random_color = Color(randf(), randf(), randf(), 1)
	for polygon in region.polygon_points:
		var region_polygon = Polygon2D.new()
		var points = PackedVector2Array()
		for point in polygon:
			points.append(point + offset)
		region_polygon.polygon = points
		region_polygon.color = random_color
		region_polygon.set_meta("w", region.w)
		region_polygon.set_meta("h", region.h)
		add_child(region_polygon)
		if Engine.is_editor_hint():
			region_polygon.set_owner(get_tree().get_edited_scene_root())

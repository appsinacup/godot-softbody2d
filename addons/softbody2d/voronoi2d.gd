@tool
@icon("res://addons/softbody2d/voronoi_icon.png")
extends Node2D;

## A Vornoi 2D regions generator. Generates chunks of 5 voronoi regions.
##
## Can be used as a helper class to generate the regions, or as a standalone node to display the regions.[br]
## As a standalone node, set the [member Voronoi2D.size] for size of total space the voronoi regions will occupy. Then, either click the [member Voronoi2D.bake] or call the [method Voronoi2D.display_voronoi] method.[br]
## [br]
## Credits: Based on [b]arcanewright[/b]/[b]godot-chunked-voronoi-generator[/b]

class_name Voronoi2D

## Bake the voronoi regions as [Polygon2D] nodes children. Removes old children.
@export var bake := false :
	set (value):
		for child in get_children():
			remove_child(child)
			child.queue_free()
		display_voronoi()
	get:
		return false

## Clear the voronoi regions.
@export var clear := false :
	set (value):
		for child in get_children():
			remove_child(child)
			child.queue_free()
	get:
		return false

## Aproximate size of the  regions
@export var size := Vector2(100,100);
## Type of the  regions
@export var type := "hexagon";
## Distance between points in the region defined with [member Voronoi2D.size]
@export var distance_between_points: float = 10;

## Generate hexagonal points around the center
static func generate_hexagon(center: Vector2, dist: float) -> Array[PackedVector2Array]:
	dist = (2 / sqrt(3)) * dist
	var points := PackedVector2Array()
	for i in range(6):  # Hexagon has 6 sides
		var angle = i * (PI / 3)  # 60 degrees in radians
		points.append(center + Vector2(cos(angle), sin(angle)) * dist)
	return [points]

## Generate hexagonal points around the center
static func generate_rectangle(center: Vector2, dist: float) -> Array[PackedVector2Array]:
	return [[center + Vector2(-dist, -dist) * 0.5,\
		center + Vector2(0, -dist) * 0.5, \
		center + Vector2(0, 0) * 0.5,\
		center + Vector2(-dist, 0) * 0.5], \
		
		[center + Vector2(0, 0) * 0.5,\
		center + Vector2(dist, 0) * 0.5, \
		center + Vector2(dist, dist) * 0.5,\
		center + Vector2(0, dist) * 0.5], \
		
		[center + Vector2(-dist, 0) * 0.5,\
		center + Vector2(0, 0) * 0.5, \
		center + Vector2(0, dist) * 0.5,\
		center + Vector2(-dist, dist) * 0.5], \
		
		[center + Vector2(0, -dist) * 0.5,\
		center + Vector2(dist, -dist) * 0.5, \
		center + Vector2(dist, 0) * 0.5,\
		center + Vector2(0, 0) * 0.5],]
	
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

static func generate_voronoi(type: String, size: Vector2, distance: float, start := Vector2()) -> Array[VoronoiRegion2D]:
	if type == "hexagon":
		return generate_voronoi_hexagon(size, distance / 2.0, start)
	else:
		return generate_voronoi_rectangle(size, distance, start)

## Generate voronoi regions
static func generate_voronoi_rectangle(size: Vector2, distance: float, start := Vector2()) -> Array[VoronoiRegion2D]:
	var polygons : Array[VoronoiRegion2D]
	for w in range(int(size.x / (distance)) + 1):
		for h in range(int(size.y / (distance)) + 1):
			var chunkLoc := Vector2(w, h)
			var voronoi_region := VoronoiRegion2D.new()
			voronoi_region.w = w
			voronoi_region.h = h
			voronoi_region.center = chunkLoc * distance
			voronoi_region.fixed_center = chunkLoc * distance
			voronoi_region.polygon_points = generate_rectangle(voronoi_region.fixed_center, distance)
			polygons.append(voronoi_region)
	return polygons
	
## Generate voronoi regions
static func generate_voronoi_hexagon(size: Vector2, distance: float, start := Vector2()) -> Array[VoronoiRegion2D]:
	var polygons : Array[VoronoiRegion2D]
	for w in range(int(size.x / (distance)) + 1):
		for h in range(int(size.y / (distance)) + 1):
			var chunkLoc := Vector2(w * sqrt(3) * 2, h)
			if h % 2 == 0:
				chunkLoc.x += sqrt(3)
			var voronoi_region := VoronoiRegion2D.new()
			voronoi_region.w = w
			voronoi_region.h = h
			voronoi_region.center = chunkLoc * distance
			voronoi_region.fixed_center = chunkLoc * distance
			voronoi_region.polygon_points = generate_hexagon(voronoi_region.fixed_center, distance)
			polygons.append(voronoi_region)
	return polygons


## Call this method to create voronoi regions based on [member Voronoi2D.size] for the region size, and [member Voronoi2D.distance_between_points] for distance between regions.
func display_voronoi():
	var voronoi = generate_voronoi(type, size, distance_between_points)
	draw_voronoi(voronoi)

func draw_voronoi(voronoi: Array[VoronoiRegion2D]):
	for each in voronoi:
		_display_polygon(Vector2(), each);
		_display_point(Vector2(), each.center)

func _display_point(offset:Vector2, point: Vector2, color:Color = Color(1,1,1,1)):
	var newPointPoly = Polygon2D.new();
	newPointPoly.position = point + offset;
	newPointPoly.polygon = PackedVector2Array([Vector2(-2,-2), Vector2(-2,2), Vector2(2,2), Vector2(2,-2)]);
	newPointPoly.color = color;
	add_child(newPointPoly)
	if Engine.is_editor_hint():
		newPointPoly.set_owner(get_tree().get_edited_scene_root())

func _display_polygon(offset:Vector2, polygons: VoronoiRegion2D):
	var random_color = Color(randf(), randf(), randf(), 1)
	for polygon in polygons.polygon_points:
		var newPoly = Polygon2D.new()
		var newPolyPoints = PackedVector2Array()
		for point in polygon:
			newPolyPoints.append(point + offset)
		newPoly.polygon = newPolyPoints
		newPoly.color = random_color
		newPoly.set_meta("w", polygons.w)
		newPoly.set_meta("h", polygons.h)
		add_child(newPoly)
		if Engine.is_editor_hint():
			newPoly.set_owner(get_tree().get_edited_scene_root())

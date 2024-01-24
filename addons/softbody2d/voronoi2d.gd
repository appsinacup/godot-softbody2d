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
## Distance between points in the region defined with [member Voronoi2D.size]
@export var distance_between_points: float = 10;

static func _generate_chunk_points_fixed(coords:Vector2, wRange: Vector2, hRange:Vector2, distance_between_points: float) -> PackedVector2Array:
	var initPoints = PackedVector2Array();
	for w in range(wRange.x, wRange.y):
		for h in range(hRange.x, hRange.y):
			var newPoint = Vector2(w*distance_between_points, h*distance_between_points);
			initPoints.append(newPoint)
	return initPoints;

static func _generate_chunk_voronoi(coords:Vector2, sizePerChunk: int, voronoiTolerance: float, distance_between_points: float) -> Array:
	var initPoints = _generate_chunk_points_fixed(coords, Vector2(0, sizePerChunk), Vector2(0, sizePerChunk), distance_between_points);
	var sorroundingPoints = PackedVector2Array();
	for i in range(-1, 2):
		for j in range(-1, 2):
			if (!(i == 0 && j == 0)):
				var xmin = 0;
				var xmax = 1;
				var ymin = 0;
				var ymax = 1;
				if (i == -1):
					xmin = 1 - voronoiTolerance;
				if (i == +1):
					xmax = voronoiTolerance;
				if (j== -1):
					ymin = 1 - voronoiTolerance;
				if (j== 1):
					ymax = voronoiTolerance;
				var tempPoints = _generate_chunk_points_fixed(Vector2(coords.x+i, coords.y+j), \
					Vector2(xmin*sizePerChunk, xmax*sizePerChunk), \
					Vector2(ymin*sizePerChunk, ymax*sizePerChunk), \
					distance_between_points);
				var resultPoints = PackedVector2Array();
				for point in tempPoints:
					var tempPoint = point + Vector2(i * sizePerChunk * distance_between_points, j * sizePerChunk * distance_between_points);
					resultPoints.append(tempPoint);
				sorroundingPoints.append_array(resultPoints)
	var allPoints = initPoints+sorroundingPoints;
	var allDelauney = Geometry2D.triangulate_delaunay(allPoints);
	var triangleArray = [];
	for triple in range(0, allDelauney.size()/3):
		triangleArray.append([allDelauney[triple*3], allDelauney[triple*3+1], allDelauney[triple*3+2]]);
	var circumcenters = PackedVector2Array();
	for triple in triangleArray:
		circumcenters.append(_get_circumcenter(allPoints[triple[0]], allPoints[triple[1]], allPoints[triple[2]]));
	var vCtrIdxWithVerts = [];
	var fixed_points = _generate_chunk_points_fixed(coords, Vector2(0, sizePerChunk), Vector2(0, sizePerChunk), distance_between_points);
	for point in range(initPoints.size()):
		var tempVerts = PackedVector2Array();
		for triangle in range(triangleArray.size()):
			if (point == triangleArray[triangle][0] || point == triangleArray[triangle][1] || point == triangleArray[triangle][2]):
				tempVerts.append(circumcenters[triangle]);
		tempVerts = _clowckwise_points(initPoints[point], tempVerts)
		
		vCtrIdxWithVerts.append([initPoints[point], fixed_points[point], tempVerts]);
	
	return vCtrIdxWithVerts;

static func _clowckwise_points(center:Vector2, sorrounding:PackedVector2Array) -> PackedVector2Array:
	var result = PackedVector2Array();
	var angles = PackedFloat32Array();
	var sortedIndexes = PackedInt32Array();
	for point in sorrounding:
		angles.append(center.angle_to_point(point));
	var remainingIdx = PackedInt32Array();
	for angle in range(angles.size()):
		remainingIdx.append(angle);
	for angle in range(angles.size()):
		var currentMin = PI;
		var currentTestIdx = 0;
		for test in range(remainingIdx.size()):
			if (angles[remainingIdx[test]] < currentMin):
				currentTestIdx = test;
				currentMin = angles[remainingIdx[test]];
		sortedIndexes.append(remainingIdx[currentTestIdx]);
		remainingIdx.remove_at(currentTestIdx);
	for index in sortedIndexes:
		result.append(sorrounding[index]);
	return result;

static func _get_circumcenter(a:Vector2, b:Vector2, c:Vector2):
	var result = Vector2(0,0)
	var midpointAB = Vector2((a.x+b.x) * 0.5,(a.y+b.y) * 0.5);
	var slopePerpAB = -((b.x-a.x)/(b.y-a.y));
	if (b.x-a.x) == 0 || (b.y-a.y) == 0:
		slopePerpAB = 0
	var midpointAC = Vector2((a.x+c.x) * 0.5,(a.y+c.y) * 0.5);
	var slopePerpAC = -((c.x-a.x)/(c.y-a.y));
	if (c.y-a.y) == 0 || (c.x-a.x) == 0:
		slopePerpAC = 0
	var bOfPerpAB = midpointAB.y - (midpointAB.x * slopePerpAB);
	var bOfPerpAC = midpointAC.y - (midpointAC.x * slopePerpAC);
	result.x = (bOfPerpAB - bOfPerpAC)/(slopePerpAC - slopePerpAB);
	if (bOfPerpAB - bOfPerpAC) == 0 || (slopePerpAC - slopePerpAB) == 0:
		result.x = 0
	result.y = slopePerpAB*result.x + bOfPerpAB;
	return result;

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

## Generate voronoi regions based on:[br]
## [param size] - total size of the resulting region.[br]
## [param distance_between_points] - distance between voronoi regions.[br]
## [param start] - start place for voronoi regions.[br]
## Returns Array of regions, where each region
static func generate_voronoi(size: Vector2, distance_between_points: float, start:= Vector2(), rand_seed = 0) -> Array[VoronoiRegion2D]:
	var polygons:Array[VoronoiRegion2D] = []
	var sizePerChunk := 5.0
	var totalX = size.x / (distance_between_points*sizePerChunk)
	var totalY = size.y / (distance_between_points*sizePerChunk)
	for w in int(totalX + 1):
		for h in int(totalY + 1):
			var chunkLoc = Vector2(w ,h)
			var voronoi = _generate_chunk_voronoi(chunkLoc, sizePerChunk, \
			0, distance_between_points)
			var i = 0
			for each in voronoi:
				var newPolyPoints := PackedVector2Array();
				var offset = Vector2(chunkLoc.x*sizePerChunk*distance_between_points,\
				chunkLoc.y*sizePerChunk*distance_between_points) + start
				for point in each[2]:
					newPolyPoints.append(point + offset);
				var voronoi_region := VoronoiRegion2D.new()
				voronoi_region.w = (w) * 5 + (i / 5)
				voronoi_region.h = (h) * 5 + (i % 5)
				i += 1
				voronoi_region.center = each[0] + offset
				voronoi_region.fixed_center = each[1] + offset
				var center = voronoi_region.fixed_center
				var dist = distance_between_points
				voronoi_region.polygon_points = [[center + Vector2(-dist, -dist) * 0.5,\
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
				polygons.append(voronoi_region)
	return polygons

## Call this method to create voronoi regions based on [member Voronoi2D.size] for the region size, and [member Voronoi2D.distance_between_points] for distance between regions.
func display_voronoi():
	var voronoi = generate_voronoi(size, distance_between_points)
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

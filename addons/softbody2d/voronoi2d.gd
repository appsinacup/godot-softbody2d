@tool
extends Node2D;
class_name Voronoi2D

@export var start := Vector2();
@export var end := Vector2(100,100);
@export var distBtwPoints: float = 30;

static func randomNumOnCoords(coords:Vector2, initialSeed:int):
	var result = initialSeed
	var randGen = RandomNumberGenerator.new();
	randGen.seed = coords.x;
	result += randGen.randi();
	var newy = randGen.randi() + coords.y;
	randGen.seed = newy;
	result += randGen.randi();
	randGen.seed = result;
	result = randGen.randi();
	return result;

static func generateChunkPoints(coords:Vector2, wRange: Vector2, hRange:Vector2, randomSeed: int, distBtwPoints: float, distBtwVariation: float) -> PackedVector2Array:
	var localRandSeed = randomNumOnCoords(coords, randomSeed);
	var initPoints = PackedVector2Array();
	for w in range(wRange.x, wRange.y):
		for h in range(hRange.x, hRange.y):
			var randGen = RandomNumberGenerator.new();
			var pointRandSeed = randomNumOnCoords(Vector2(w,h), localRandSeed);
			randGen.seed = pointRandSeed;
			var newPoint = Vector2(w*distBtwPoints + randGen.randf_range(-distBtwVariation, distBtwVariation)*distBtwPoints, h*distBtwPoints + randGen.randf_range(-distBtwVariation, distBtwVariation)*distBtwPoints);
			initPoints.append(newPoint)
	return initPoints;

static func generateChunkPointsFixed(coords:Vector2, wRange: Vector2, hRange:Vector2, distBtwPoints: float) -> PackedVector2Array:
	var initPoints = PackedVector2Array();
	for w in range(wRange.x, wRange.y):
		for h in range(hRange.x, hRange.y):
			var newPoint = Vector2(w*distBtwPoints, h*distBtwPoints);
			initPoints.append(newPoint)
	return initPoints;

static func generateChunkVoronoi(coords:Vector2, sizePerChunk: int, voronoiTolerance: float, randomSeed: int, distBtwPoints: float, distBtwVariation: float):
	var initPoints = generateChunkPoints(coords, Vector2(0, sizePerChunk), Vector2(0, sizePerChunk), randomSeed, distBtwPoints, distBtwVariation);
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
				var tempPoints = generateChunkPoints(Vector2(coords.x+i, coords.y+j), \
				Vector2(xmin*sizePerChunk, xmax*sizePerChunk), \
				Vector2(ymin*sizePerChunk, ymax*sizePerChunk), \
				randomSeed, distBtwPoints, distBtwVariation);
				var resultPoints = PackedVector2Array();
				for point in tempPoints:
					var tempPoint = point + Vector2(i * sizePerChunk * distBtwPoints, j * sizePerChunk * distBtwPoints);
					resultPoints.append(tempPoint);
				sorroundingPoints.append_array(resultPoints)
	var allPoints = initPoints+sorroundingPoints;
	var allDelauney = Geometry2D.triangulate_delaunay(allPoints);
	var triangleArray = [];
	for triple in range(0, allDelauney.size()/3):
		triangleArray.append([allDelauney[triple*3], allDelauney[triple*3+1], allDelauney[triple*3+2]]);
	var circumcenters = PackedVector2Array();
	for triple in triangleArray:
		circumcenters.append(getCircumcenter(allPoints[triple[0]], allPoints[triple[1]], allPoints[triple[2]]));
	var vCtrIdxWithVerts = [];
	var fixed_points = generateChunkPointsFixed(coords, Vector2(0, sizePerChunk), Vector2(0, sizePerChunk), distBtwPoints);
	for point in range(initPoints.size()):
		var tempVerts = PackedVector2Array();
		for triangle in range(triangleArray.size()):
			if (point == triangleArray[triangle][0] || point == triangleArray[triangle][1] || point == triangleArray[triangle][2]):
				tempVerts.append(circumcenters[triangle]);
		tempVerts = clowckwisePoints(initPoints[point], tempVerts)
		vCtrIdxWithVerts.append([fixed_points[point], tempVerts]);
	
	return vCtrIdxWithVerts;

static func clowckwisePoints(center:Vector2, sorrounding:PackedVector2Array) -> PackedVector2Array:
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

static func getCircumcenter(a:Vector2, b:Vector2, c:Vector2):
	var result = Vector2(0,0)
	var midpointAB = Vector2((a.x+b.x)/2,(a.y+b.y)/2);
	var slopePerpAB = -((b.x-a.x)/(b.y-a.y));
	var midpointAC = Vector2((a.x+c.x)/2,(a.y+c.y)/2);
	var slopePerpAC = -((c.x-a.x)/(c.y-a.y));
	var bOfPerpAB = midpointAB.y - (midpointAB.x * slopePerpAB);
	var bOfPerpAC = midpointAC.y - (midpointAC.x * slopePerpAC);
	result.x = (bOfPerpAB - bOfPerpAC)/(slopePerpAC - slopePerpAB);
	result.y = slopePerpAB*result.x + bOfPerpAB;
	return result;

static func generateVoronoi(size: Vector2, distBtwPoints: float, start:= Vector2(), edgeDist := 0.3) -> Array:
	var polygons = []
	var sizePerChunk = 5
	var totalX = size.x / (sizePerChunk* distBtwPoints)
	var totalY = size.y / (sizePerChunk* distBtwPoints)
	for w in int(totalX * 2 + 2):
		for h in int(totalY * 2 + 2):
			var chunkLoc = Vector2(w - totalX - 1,h - totalY - 1)
			var voronoi = generateChunkVoronoi(chunkLoc, sizePerChunk, \
			0.3, 0, distBtwPoints, edgeDist)
			for each in voronoi:
				var newPolyPoints := PackedVector2Array();
				var offset = Vector2(chunkLoc.x*sizePerChunk*distBtwPoints,chunkLoc.y*sizePerChunk*distBtwPoints) + start
				for point in each[1]:
					newPolyPoints.append(point + offset);
				polygons.append([each[0] + offset, newPolyPoints])
			var randSeed = randomNumOnCoords(size, 0);
	return polygons

func displayVoronoiForRect():
	var randSeed = 0
	var voronoi = generateVoronoi(end - start, distBtwPoints)
	for each in voronoi:
		randSeed = displayPolygon(Vector2(), each[1], randSeed);
	displayPoints(Vector2(), voronoi)

func displayPoints(offset:Vector2, points:PackedVector2Array, color:Color = Color(1,1,1,1)):
	for point in points:
		var newPointPoly = Polygon2D.new();
		newPointPoly.position = point + offset;
		newPointPoly.polygon = PackedVector2Array([Vector2(-2,-2), Vector2(-2,2), Vector2(2,2), Vector2(2,-2)]);
		newPointPoly.color = color;
		add_child(newPointPoly)
		if Engine.is_editor_hint():
			newPointPoly.set_owner(get_tree().get_edited_scene_root())

func displayPolygon(offset:Vector2, polygon:PackedVector2Array, randSeed):
	var newPoly = Polygon2D.new();
	var newPolyPoints = PackedVector2Array();
	for point in polygon:
		newPolyPoints.append(point + offset);
	newPoly.polygon = newPolyPoints;
	var randGen = RandomNumberGenerator.new()
	randGen.seed = randSeed;
	newPoly.color = Color(randGen.randf(), randGen.randf(), randGen.randf(), 1);
	add_child(newPoly)
	if Engine.is_editor_hint():
		newPoly.set_owner(get_tree().get_edited_scene_root())
	return randGen.randi();

@export var bake_voronoi := false :
	set (value):
		for child in get_children():
			remove_child(child)
			child.queue_free()
		displayVoronoiForRect()
	get:
		return false

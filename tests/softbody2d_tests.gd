extends Node2D

## Headless test suite for [SoftBody2D].
##
## Run with:
##   godot --headless res://tests/run_tests.tscn
##
## Exits with code 0 when everything passes and 1 otherwise, so it can be used in CI.
## Tests that need the Godot Rapier Physics extension are skipped, not failed, when it is
## not installed.

const TEXTURE := "res://samples/softbody2d/softbody2d_full.png"
const BREAKABLE_SCENE := "res://samples/softbody2d/tutorial.tscn"

var _passed := 0
var _failed := 0
var _skipped := 0
var _failures: Array[String] = []
var _current := ""

#region Framework


func _ready() -> void:
	print("\n================ SoftBody2D test suite ================")
	print("physics engine : %s" % ProjectSettings.get_setting("physics/2d/physics_engine", "DEFAULT"))
	print("rapier present : %s" % SoftBody2DPhysics.has_rapier())

	for test_name in _test_names():
		_current = test_name
		print("\n-- %s" % test_name)
		await call(test_name)
		_cleanup()

	print("\n================ %d passed, %d failed, %d skipped ================" % [_passed, _failed, _skipped])
	for failure in _failures:
		print("  FAILED: %s" % failure)
	get_tree().quit(1 if _failed > 0 else 0)


func _test_names() -> Array:
	var names := []
	for method in get_method_list():
		if method.name.begins_with("test_") and not names.has(method.name):
			names.append(method.name)
	names.sort()
	return names


func _check(label: String, condition: bool, detail: String = "") -> void:
	if condition:
		_passed += 1
		print("   PASS  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])
	else:
		_failed += 1
		_failures.append("%s / %s%s" % [_current, label, "" if detail == "" else "  (%s)" % detail])
		print("   FAIL  %s%s" % [label, "" if detail == "" else "  (%s)" % detail])


func _skip(reason: String) -> void:
	_skipped += 1
	print("   SKIP  %s" % reason)


func _cleanup() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()


func _simulate(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame


func test_18_break_mode_selects_one_criterion() -> void:
	# Both thresholds set at once: only the one matching the mode may act.
	var sb := _make(
		func(sb):
			sb.break_mode = SoftBody2D.BreakMode.NONE
			sb.break_distance_ratio = 1.2
			sb.break_force = 1.0
	)
	await _simulate(5)
	var before := _joint_count(sb)
	_deform(sb, Vector2(3.0, 3.0))
	await _simulate(90)
	_check(
		"BreakMode.NONE never breaks, whatever the thresholds say",
		_joint_count(sb) == before,
		"joints %d -> %d" % [before, _joint_count(sb)]
	)
	_cleanup()

	# DISTANCE mode must ignore a break_force low enough to shatter it instantly.
	var distance_mode := _make(
		func(sb):
			sb.break_mode = SoftBody2D.BreakMode.DISTANCE
			sb.break_distance_ratio = 20.0
			sb.break_force = 1.0
	)
	await _simulate(5)
	var distance_before := _joint_count(distance_mode)
	_deform(distance_mode, Vector2(1.2, 1.2))
	await _simulate(90)
	_check(
		"DISTANCE mode ignores break_force",
		_joint_count(distance_mode) == distance_before,
		"joints %d -> %d" % [distance_before, _joint_count(distance_mode)]
	)


#endregion

#region Helpers


func _make(configure := Callable()) -> SoftBody2D:
	var sb := SoftBody2D.new()
	sb.texture = load(TEXTURE)
	sb.vertex_interval = 40
	sb.can_sleep = false
	sb.gravity_scale = 0.0
	if configure.is_valid():
		configure.call(sb)
	add_child(sb)
	sb.create_softbody2d(true)
	return sb


func _load_breakable() -> SoftBody2D:
	var root := (load(BREAKABLE_SCENE) as PackedScene).instantiate()
	add_child(root)
	return root.get_node("BreakableSoftbody2D") as SoftBody2D


## Joints between skin neighbours only, leaving out the longer reach joints.
func _skin_joint_count(sb: SoftBody2D) -> int:
	var n := 0
	for b in sb.get_rigid_bodies():
		for joint in b.joints:
			if int(joint.get_meta("hops", 1)) == 1:
				n += 1
	return n


func _joint_count(sb: SoftBody2D) -> int:
	var n := 0
	for b in sb.get_rigid_bodies():
		n += b.joints.size()
	return n


## Mean distance from the centre. Grows when stretched, shrinks when squashed.
func _spread(sb: SoftBody2D) -> float:
	var bodies := sb.get_rigid_bodies()
	if bodies.is_empty():
		return 0.0
	var centre := sb.get_bones_center_position()
	var total := 0.0
	for b in bodies:
		total += b.rigidbody.global_position.distance_to(centre)
	return total / bodies.size()


## Scale every body's offset from the centre, deforming the softbody in place.
func _deform(sb: SoftBody2D, factor: Vector2) -> void:
	var centre := sb.get_bones_center_position()
	for b in sb.get_rigid_bodies():
		var rb := b.rigidbody as RigidBody2D
		if rb == null:
			continue
		rb.global_position = centre + (rb.global_position - centre) * factor
		rb.linear_velocity = Vector2.ZERO


## How far each body sits from where the remembered rest shape says it should be, after
## fitting that shape onto the current positions. 0 means the shape is perfectly restored.
func _shape_error(sb: SoftBody2D) -> float:
	var bodies := sb.get_rigid_bodies()
	if bodies.size() < 2:
		return 0.0
	var rest: Array[Vector2] = []
	var current: Array[Vector2] = []
	var rest_centre := Vector2()
	var current_centre := Vector2()
	for b in bodies:
		var r: Vector2 = b.rigidbody.get_meta("rest_position", b.rigidbody.position)
		rest.append(r)
		current.append(b.rigidbody.global_position)
		rest_centre += r
		current_centre += b.rigidbody.global_position
	rest_centre /= bodies.size()
	current_centre /= bodies.size()
	var sin_sum := 0.0
	var cos_sum := 0.0
	for i in bodies.size():
		var q := rest[i] - rest_centre
		var p := current[i] - current_centre
		sin_sum += q.cross(p)
		cos_sum += q.dot(p)
	var angle := atan2(sin_sum, cos_sum)
	var error := 0.0
	for i in bodies.size():
		var goal := current_centre + (rest[i] - rest_centre).rotated(angle)
		error += goal.distance_to(current[i])
	return error / bodies.size()


#endregion

#region Tests


func test_01_generation_invariants() -> void:
	var sb := _make()
	await _simulate(2)
	var bodies := sb.get_rigid_bodies()
	_check("bodies are generated", bodies.size() > 5, "count=%d" % bodies.size())
	_check("joints are generated", _joint_count(sb) > 5, "count=%d" % _joint_count(sb))
	_check("every body records its rest position", bodies.all(func(b): return b.rigidbody.has_meta("rest_position")))
	_check(
		"every joint records its rest distance",
		bodies.all(func(b): return b.joints.all(func(j): return j.has_meta("joint_distance")))
	)
	_check(
		"body starts as a single connected group",
		sb.get_clusters().size() == 1,
		"clusters=%d" % sb.get_clusters().size()
	)
	sb.debug_draw = SoftBody2D.DEBUG_DRAW_JOINTS | SoftBody2D.DEBUG_DRAW_SHAPES
	var draws := [0]
	sb.draw.connect(func(): draws[0] += 1)
	for _i in 5:
		await get_tree().process_frame
	_check("debug_draw redraws every drawn frame without errors", draws[0] >= 4, "draws=%d" % draws[0])


func test_02_regions_cover_whole_texture() -> void:
	var sb := _make()
	await _simulate(1)
	var lim_min := Vector2.INF
	var lim_max := -Vector2.INF
	for b in sb.get_rigid_bodies():
		lim_min = lim_min.min(b.rigidbody.position)
		lim_max = lim_max.max(b.rigidbody.position)
	var covered := lim_max - lim_min
	var tex: Vector2 = (load(TEXTURE) as Texture2D).get_size()
	# Bodies are inset from the edge by edge_clearance, so exact coverage is not
	# expected. Anything under half the texture means whole regions went missing.
	_check("bodies span the texture width", covered.x > tex.x * 0.5, "%.0f of %.0f px" % [covered.x, tex.x])
	_check("bodies span the texture height", covered.y > tex.y * 0.5, "%.0f of %.0f px" % [covered.y, tex.y])


func test_08_cut_splits_the_body() -> void:
	var sb := _make()
	await _simulate(5)
	_check("starts as one piece", sb.get_clusters().size() == 1)
	var centre := sb.get_bones_center_position()
	# A horizontal line well past both edges, so the cut goes all the way through.
	var removed := sb.cut(centre + Vector2(-10000, 0), centre + Vector2(10000, 0))
	_check("cut removed joints", removed > 0, "removed=%d" % removed)
	await _simulate(5)
	var clusters := sb.get_clusters().size()
	_check("cut separates the body into pieces", clusters >= 2, "clusters=%d" % clusters)
	var no_crossing := true
	for b in sb.get_rigid_bodies():
		for joint in b.joints:
			var other := b.rigidbody.global_position
			var target: Node2D = joint.get_node_or_null(joint.node_b)
			if target == null:
				continue
			if signf(other.y - centre.y) != signf(target.global_position.y - centre.y):
				if absf(other.y - centre.y) > 1.0 and absf(target.global_position.y - centre.y) > 1.0:
					no_crossing = false
	_check("no joints remain crossing the cut line", no_crossing)


func test_09_cut_pieces_keep_their_own_shape() -> void:
	var sb := _make()
	await _simulate(10)
	var centre := sb.get_bones_center_position()
	sb.cut(centre + Vector2(-10000, 0), centre + Vector2(10000, 0))
	await _simulate(60)
	var clusters: Array = sb.get_clusters()
	_check("pieces stay separated after simulating", clusters.size() >= 2, "clusters=%d" % clusters.size())
	# Each piece should still be intact: no piece collapsed to a point.
	var all_intact := true
	for cluster in clusters:
		if cluster.size() < 2:
			continue
		var spread := 0.0
		var c := Vector2()
		for child in cluster:
			c += child.rigidbody.global_position
		c /= cluster.size()
		for child in cluster:
			spread += child.rigidbody.global_position.distance_to(c)
		spread /= cluster.size()
		if spread < sb.vertex_interval * 0.2:
			all_intact = false
	_check("each piece keeps its own shape", all_intact)


func test_10_distance_breaking_respects_the_configured_ratio() -> void:
	var sb := _make(
		func(sb):
			sb.break_mode = SoftBody2D.BreakMode.DISTANCE
			sb.break_distance_ratio = 1.5
	)
	await _simulate(5)
	var before := _joint_count(sb)
	# Stretch by 3x, well past the 1.5x threshold, so every joint should be over its limit.
	_deform(sb, Vector2(3.0, 3.0))
	await _simulate(120)
	var after := _joint_count(sb)
	_check("joints break once stretched past the ratio", after < before, "joints %d -> %d" % [before, after])

	_cleanup()
	# The same stretch under a threshold that is never reached must not break anything.
	var stiff := _make(
		func(sb):
			sb.break_mode = SoftBody2D.BreakMode.DISTANCE
			sb.break_distance_ratio = 20.0
	)
	await _simulate(5)
	var stiff_before := _joint_count(stiff)
	_deform(stiff, Vector2(1.2, 1.2))
	await _simulate(120)
	_check(
		"joints survive when kept under the ratio",
		_joint_count(stiff) == stiff_before,
		"joints %d -> %d" % [stiff_before, _joint_count(stiff)]
	)


func test_11_no_body_is_retired_while_still_jointed() -> void:
	# Regression test. A body may only be taken out of the simulation once it has lost its
	# last joint; retiring the wrong one freezes everything still attached to it and leaves
	# stray pieces behind.
	var sb := _load_breakable()
	await _simulate(2)
	var violations := 0
	var guard := 0
	while _joint_count(sb) > 0 and guard < 600:
		guard += 1
		for b in sb.get_rigid_bodies():
			if b.joints.size() > 0:
				sb.remove_joint(b, b.joints[0])
				break
		await get_tree().physics_frame
		for b in sb.get_rigid_bodies():
			if _is_retired(b) and b.joints.size() > 0:
				violations += 1
	_check("no body is retired while it still has joints", violations == 0, "violations=%d" % violations)

	await _simulate(5)
	var jointless := 0
	var retired := 0
	for b in sb.get_rigid_bodies():
		if b.joints.size() == 0:
			jointless += 1
			if _is_retired(b):
				retired += 1
	_check(
		"every fully disconnected body is retired, leaving no stray pieces",
		retired == jointless,
		"%d of %d retired" % [retired, jointless]
	)


func _is_retired(child) -> bool:
	var rb: Node = child.rigidbody
	if rb.process_mode == Node.PROCESS_MODE_DISABLED:
		return true
	if rb is RigidBody2D and (rb as RigidBody2D).freeze:
		return true
	var shape: Node2D = child.shape
	if shape != null:
		if shape.scale == Vector2.ZERO:
			return true
		if shape is CollisionShape2D and (shape as CollisionShape2D).disabled:
			return true
	return false


func test_12_bake_scale_scales_geometry_not_the_node() -> void:
	var normal := _make()
	await _simulate(1)
	var normal_extent := _extent(normal)
	var normal_bodies := normal.get_rigid_bodies().size()
	_cleanup()

	var big := _make(
		func(sb):
			sb.bake_scale = Vector2(2, 2)
			sb.shape_type = "Rectangle"
	)
	await _simulate(1)
	var big_extent := _extent(big)
	_check(
		"doubling bake_scale roughly doubles the body",
		big_extent.x > normal_extent.x * 1.6 and big_extent.x < normal_extent.x * 2.4,
		"%.0f vs %.0f px" % [big_extent.x, normal_extent.x]
	)
	_check(
		"a bigger body gets more particles, not bigger ones",
		big.get_rigid_bodies().size() > normal_bodies,
		"%d vs %d bodies" % [big.get_rigid_bodies().size(), normal_bodies]
	)
	var shapes_ok := true
	for b in big.get_rigid_bodies():
		var shape: Shape2D = b.shape.shape
		var fit: float = b.rigidbody.get_meta("shape_fit", 1.0)
		if shape is RectangleShape2D and not is_equal_approx((shape as RectangleShape2D).size.x, big.radius * fit):
			shapes_ok = false
	_check(
		"collision shapes are not scaled twice", shapes_ok, "size == radius (%.1f) times the corner fit" % big.radius
	)
	_check(
		"texture mapping compensates for the baked scale",
		big.texture_scale.is_equal_approx(Vector2(0.5, 0.5)),
		str(big.texture_scale)
	)
	_check("the node itself stays unscaled", big.scale.is_equal_approx(Vector2.ONE))


func _extent(sb: SoftBody2D) -> Vector2:
	var lim_min := Vector2.INF
	var lim_max := -Vector2.INF
	for b in sb.get_rigid_bodies():
		lim_min = lim_min.min(b.rigidbody.position)
		lim_max = lim_max.max(b.rigidbody.position)
	return lim_max - lim_min


func test_20_edge_clearance_keeps_shapes_inside_the_texture() -> void:
	# Bodies are pushed inward until their collision shape fits inside the outline, and a body
	# in a corner too thin for that gets a smaller shape. Without clearance, shapes poke out.
	var results := {}
	for clearance in [0.0, -1.0]:
		var sb := _make(
			func(sb):
				sb.shape_type = "Circle"
				sb.edge_clearance = clearance
				sb.min_area = 0.08
		)
		await _simulate(1)
		results[clearance] = _worst_protrusion(sb)
		_cleanup()
	_check("without clearance, circles poke out of the texture", results[0.0] > 2.0, "%.1f px" % results[0.0])
	_check("with automatic clearance no circle pokes out", results[-1.0] < 0.5, "%.1f px" % results[-1.0])
	var squares := _make(
		func(sb):
			sb.shape_type = "Rectangle"
			sb.edge_clearance = -1.0
			sb.min_area = 0.08
	)
	await _simulate(1)
	_check(
		"with automatic clearance no square pokes out either",
		_worst_protrusion(squares) < 0.5,
		"%.1f px" % _worst_protrusion(squares)
	)


## Furthest any collision shape sample sits outside the rest outline, in pixels.
func _worst_protrusion(sb: SoftBody2D) -> float:
	var outline := PackedVector2Array()
	for i in sb.polygon.size() - sb.internal_vertex_count:
		outline.append(sb.polygon[i])
	var worst := 0.0
	for child in sb.get_rigid_bodies():
		var shape: Shape2D = child.shape.shape
		var xform := child.shape.global_transform
		var samples: Array[Vector2] = []
		if shape is CircleShape2D:
			for t in 16:
				var a := TAU * t / 16.0
				samples.append(xform * (Vector2(cos(a), sin(a)) * (shape as CircleShape2D).radius))
		elif shape is RectangleShape2D:
			var half: Vector2 = (shape as RectangleShape2D).size * 0.5
			for corner in [
				Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)
			]:
				samples.append(xform * (corner as Vector2))
		for p in samples:
			var local := sb.to_local(p)
			if Geometry2D.is_point_in_polygon(local, outline):
				continue
			var nearest := INF
			for i in outline.size():
				var segment_point := Geometry2D.get_closest_point_to_segment(
					local, outline[i], outline[(i + 1) % outline.size()]
				)
				nearest = minf(nearest, local.distance_to(segment_point))
			worst = maxf(worst, nearest)
	return worst


func test_21_joint_reach_holds_the_shape() -> void:
	# Two-hop joints resist shearing inside the solver. Leaned over and released, a softbody
	# with joint_reach 2 comes back; with reach 1 the pin lattice stays leaned.
	var errors := {}
	var joints := {}
	for reach in [1, 2]:
		var sb := _make(func(sb): sb.joint_reach = reach)
		await _simulate(10)
		joints[reach] = _joint_count(sb)
		_shear(sb, 0.8)
		await _simulate(240)
		errors[reach] = _shape_error(sb)
		_cleanup()
	_check("reach 2 adds joints", joints[2] > joints[1] * 1.5, "%d vs %d" % [joints[2], joints[1]])
	_check(
		"a leaned softbody comes back at reach 2 and stays leaned at reach 1",
		errors[2] < errors[1] * 0.5 and errors[2] < 10.0,
		"error %.1f px at reach 2 vs %.1f px at reach 1" % [errors[2], errors[1]]
	)
	var far := _make(func(sb): sb.joint_reach = 3)
	await _simulate(1)
	_check("reach 3 adds joints again", _joint_count(far) > joints[2], "%d" % _joint_count(far))


func test_24_angular_limits_bound_relative_rotation() -> void:
	# Two bodies, one frozen: the other hangs off it. Its rotation relative to the frozen one
	# must stay inside the limit, and swing further without one. Godot Physics's pin limits
	# misbehave with two pins per pair, so this is pinned on Rapier only.
	if not SoftBody2DPhysics.has_rapier():
		_skip("angular limits are only reliable on Rapier")
		return
	var rotations := {}
	for limit in [0.0, 5.0, 30.0]:
		var image := Image.create(120, 24, false, Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		var sb := SoftBody2D.new()
		sb.texture = ImageTexture.create_from_image(image)
		sb.vertex_interval = 40
		sb.pattern_type = "rectangle"
		sb.joint_reach = 1
		sb.softness = 60.0
		sb.gravity_scale = 1.0
		sb.linear_damp = 2.0
		sb.angular_damp = 2.0
		sb.can_sleep = false
		sb.angular_limit_enabled = limit > 0.0
		sb.angular_limit_lower = -limit
		sb.angular_limit_upper = limit
		add_child(sb)
		sb.create_softbody2d(true)
		# The leftmost body is held; measured is its direct neighbour, one joint away.
		var root_child: SoftBody2D.SoftBodyChild = sb.get_rigid_bodies()[0]
		for b in sb.get_rigid_bodies():
			if b.rigidbody.global_position.x < root_child.rigidbody.global_position.x:
				root_child = b
		var root_body := root_child.rigidbody as RigidBody2D
		var hanging := sb.get_joint_target(root_child.joints[0]) as RigidBody2D
		root_body.freeze = true
		await _simulate(240)
		rotations[limit] = absf(rad_to_deg(wrapf(hanging.rotation - root_body.rotation, -PI, PI)))
		_cleanup()
	_check("without a limit the neighbour twists past 5 degrees", rotations[0.0] > 6.0, "%.1f deg" % rotations[0.0])
	_check(
		"a 5 degree limit clamps it at 5 degrees",
		rotations[5.0] <= 5.5 and rotations[5.0] < rotations[0.0],
		"%.1f deg (unlimited %.1f)" % [rotations[5.0], rotations[0.0]]
	)
	_check("a 30 degree limit never exceeds 30 degrees", rotations[30.0] <= 30.5, "%.1f deg" % rotations[30.0])


func test_25_yield_strain_keeps_a_dent() -> void:
	# Squashed to half height: elastic springs back, plastic keeps most of the dent.
	var heights := {}
	for yield_strain in [0.0, 0.05]:
		var sb := _make(
			func(sb):
				sb.yield_strain = yield_strain
				sb.linear_damp = 2.0
		)
		await _simulate(10)
		var rest := _height(sb)
		_deform(sb, Vector2(1.0, 0.5))
		await _simulate(240)
		heights[yield_strain] = _height(sb) / rest
		_cleanup()
	_check("elastic springs back", heights[0.0] > 0.9, "%.0f%% of rest height" % (heights[0.0] * 100.0))
	_check("plastic keeps the dent", heights[0.05] < 0.85, "%.0f%% of rest height" % (heights[0.05] * 100.0))

	# Only squeezing sets. Yanking a body out stretches its joints, which never yield, so
	# it comes back; and no joint may end up squeezed more than yield_limit permanently.
	var sb := _make(
		func(sb):
			sb.yield_strain = 0.05
			sb.yield_limit = 0.3
			sb.linear_damp = 2.0
	)
	await _simulate(5)
	var centre := sb.get_center_body().rigidbody as RigidBody2D
	var start := centre.global_position
	centre.global_position += Vector2(120, 0)
	await _simulate(120)
	var worst_flow := 0.0
	for b in sb.get_rigid_bodies():
		for joint in b.joints:
			var original: float = joint.get_meta("original_distance")
			var rest: float = joint.get_meta("joint_distance")
			worst_flow = maxf(worst_flow, absf(rest / original - 1.0))
	_check("no joint flows past yield_limit", worst_flow <= 0.31, "worst %.2f" % worst_flow)
	_check(
		"a yanked interior body comes back instead of staying out",
		centre.global_position.distance_to(start) < 40.0,
		"%.0f px from where it was" % centre.global_position.distance_to(start)
	)


func test_26_skin_smoothing_keeps_welds_and_tears_still_open() -> void:
	# Each region has its own copies of border vertices. Smoothing must keep the copies
	# coincident (a welded surface), and a cut must let them separate (a visible tear).
	var sb := _make(func(sb): sb.skin_smoothing = 1.0)
	await _simulate(5)
	_check("border copies coincide before the cut", _split_copies(sb) == 0, "%d split" % _split_copies(sb))
	var centre := sb.get_bones_center_position()
	sb.cut(centre + Vector2(-10000, 0), centre + Vector2(10000, 0))
	_deform(sb, Vector2(1.0, 1.4))
	await _simulate(30)
	_check("copies along the cut separate afterwards", _split_copies(sb) > 0, "%d split" % _split_copies(sb))
	_check(
		"no vertex is still weighted to a bone in the other piece",
		_weights_across_pieces(sb) == 0,
		"%d crossing weights" % _weights_across_pieces(sb)
	)


## Vertex weights that reach from a vertex's own piece into another piece: they would draw
## slivers of texture between separated pieces.
func _weights_across_pieces(sb: SoftBody2D) -> int:
	var clusters := sb.get_clusters()
	var piece_of := {}
	for piece_index in clusters.size():
		for child in clusters[piece_index]:
			piece_of[int(child.bone.get_meta("idx"))] = piece_index
	var skeleton: Skeleton2D = sb.get_node(sb.skeleton)
	var owner_piece := {}
	for bone_index in skeleton.get_bone_count():
		for vertex in skeleton.get_bone(bone_index).get_meta("vert_owned"):
			owner_piece[vertex] = piece_of.get(bone_index, -1)
	var crossing := 0
	for bone_index in skeleton.get_bone_count():
		var weights := sb.get_bone_weights(bone_index)
		for vertex in weights.size():
			if weights[vertex] > 0.0 and owner_piece.get(vertex, -1) != piece_of.get(bone_index, -1):
				crossing += 1
	return crossing


## Pairs of polygon vertices that share a rest position but are skinned more than 2 px apart.
func _split_copies(sb: SoftBody2D) -> int:
	var skeleton: Skeleton2D = sb.get_node(sb.skeleton)
	var xforms: Array[Transform2D] = []
	var weights: Array[PackedFloat32Array] = []
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone(i)
		xforms.append(bone.transform * bone.rest.affine_inverse())
		weights.append(sb.get_bone_weights(i))
	var skinned := PackedVector2Array()
	for v in sb.polygon.size():
		var ranked := []
		for b in xforms.size():
			if v < weights[b].size() and weights[b][v] > 0.0:
				ranked.append([weights[b][v], b])
		ranked.sort_custom(func(a, c): return a[0] > c[0])
		var total := 0.0
		for k in mini(4, ranked.size()):
			total += ranked[k][0]
		var pos := Vector2.ZERO
		for k in mini(4, ranked.size()):
			pos += (ranked[k][0] / total) * (xforms[ranked[k][1]] * sb.polygon[v])
		skinned.append(pos if total > 0.0 else sb.polygon[v])
	var by_rest := {}
	for v in sb.polygon.size():
		var key := sb.polygon[v].snapped(Vector2(0.01, 0.01))
		if not by_rest.has(key):
			by_rest[key] = []
		by_rest[key].append(v)
	var split := 0
	for key in by_rest:
		var copies: Array = by_rest[key]
		for i in copies.size():
			for j in range(i + 1, copies.size()):
				if skinned[copies[i]].distance_to(skinned[copies[j]]) > 2.0:
					split += 1
	return split


func _height(sb: SoftBody2D) -> float:
	var lo := INF
	var hi := -INF
	for b in sb.get_rigid_bodies():
		lo = minf(lo, b.rigidbody.global_position.y)
		hi = maxf(hi, b.rigidbody.global_position.y)
	return hi - lo


func test_23_interior_strength_keeps_tears_from_starting_inside() -> void:
	# The centre body is yanked outward. With interior strength its confined joints hold, an
	# edge body pulled the same way still tears at the plain threshold.
	var broken := {}
	for strength in [1.0, 6.0]:
		var sb := _make(
			func(sb):
				sb.break_mode = SoftBody2D.BreakMode.DISTANCE
				sb.break_distance_ratio = 1.5
				sb.interior_strength = strength
				sb.max_breaks_per_step = 64
		)
		await _simulate(5)
		var before := _skin_joint_count(sb)
		var centre := sb.get_center_body().rigidbody as RigidBody2D
		centre.global_position += Vector2(80, 0)
		await _simulate(3)
		broken[strength] = before - _skin_joint_count(sb)
		_cleanup()
	_check("at strength 1 the centre body rips out", broken[1.0] > 0, "broke %d skin joints" % broken[1.0])
	_check("at strength 6 its skin joints hold", broken[6.0] == 0, "broke %d skin joints" % broken[6.0])

	var sb := _make(
		func(sb):
			sb.break_mode = SoftBody2D.BreakMode.DISTANCE
			sb.break_distance_ratio = 1.5
			sb.interior_strength = 6.0
			sb.max_breaks_per_step = 64
	)
	await _simulate(5)
	var before := _joint_count(sb)
	var edge_body: RigidBody2D = null
	var top := INF
	for b in sb.get_rigid_bodies():
		if b.rigidbody.get_meta("edge", false) and b.rigidbody.global_position.y < top:
			top = b.rigidbody.global_position.y
			edge_body = b.rigidbody
	_check("edge bodies are marked", edge_body != null)
	edge_body.global_position += Vector2(0, -80)
	await _simulate(3)
	_check(
		"an edge body still tears at the plain threshold",
		_joint_count(sb) < before,
		"joints %d -> %d" % [before, _joint_count(sb)]
	)


func test_22_angular_limits_reach_the_joints_in_radians() -> void:
	var sb := _make(
		func(sb):
			sb.angular_limit_enabled = true
			sb.angular_limit_lower = -15.0
			sb.angular_limit_upper = 15.0
	)
	await _simulate(1)
	var joint: PinJoint2D = sb.get_rigid_bodies()[0].joints[0]
	_check("angular_limit_enabled reaches the joint", joint.angular_limit_enabled)
	_check(
		"degrees on the softbody are radians on the joint",
		is_equal_approx(joint.angular_limit_upper, deg_to_rad(15.0)),
		"joint upper limit %.3f rad" % joint.angular_limit_upper
	)
	sb.angular_limit_upper = 30.0
	_check("changing the limit converts too", is_equal_approx(joint.angular_limit_upper, deg_to_rad(30.0)))


## Shear every body sideways in proportion to its height, deforming the softbody in place.
func _shear(sb: SoftBody2D, amount: float) -> void:
	var centre := sb.get_bones_center_position()
	for b in sb.get_rigid_bodies():
		var rb := b.rigidbody as RigidBody2D
		if rb == null:
			continue
		var offset := rb.global_position - centre
		rb.global_position = centre + Vector2(offset.x + offset.y * amount, offset.y)
		rb.linear_velocity = Vector2.ZERO


func test_13_rapier_reports_joint_reaction_force() -> void:
	if not SoftBody2DPhysics.has_rapier():
		_skip("Godot Rapier Physics is not installed")
		return
	var sb := _make(func(sb): sb.gravity_scale = 0.0)
	await _simulate(10)
	# An undisturbed softbody should be carrying almost no load.
	var idle_peak := _peak_joint_force(sb)
	# Now pull it apart and let the solver fight it.
	_deform(sb, Vector2(1.6, 1.6))
	await _simulate(3)
	var loaded_peak := _peak_joint_force(sb)
	_check("reaction impulse is readable and non-negative", loaded_peak >= 0.0, "peak=%.1f" % loaded_peak)
	_check(
		"a stretched softbody reports more joint load than an idle one",
		loaded_peak > idle_peak,
		"idle=%.1f loaded=%.1f" % [idle_peak, loaded_peak]
	)


func _peak_joint_force(sb: SoftBody2D) -> float:
	var peak := 0.0
	var delta := 1.0 / float(Engine.physics_ticks_per_second)
	for b in sb.get_rigid_bodies():
		for joint in b.joints:
			peak = maxf(peak, SoftBody2DPhysics.joint_reaction_impulse(joint).length() / delta)
	return peak


func test_14_force_breaking_tears_a_stretched_body() -> void:
	if not SoftBody2DPhysics.has_rapier():
		_skip("Godot Rapier Physics is not installed")
		return
	# Calibrate against what an undisturbed body carries, so the threshold is meaningful
	# regardless of mass and solver settings.
	var probe := _make()
	await _simulate(10)
	_deform(probe, Vector2(1.6, 1.6))
	await _simulate(3)
	var loaded_peak := _peak_joint_force(probe)
	_cleanup()
	if loaded_peak <= 0.0:
		_skip("no joint load measured, cannot calibrate a threshold")
		return

	var sb := _make(
		func(sb):
			sb.break_mode = SoftBody2D.BreakMode.FORCE
			sb.break_force = loaded_peak * 0.25
			sb.break_smoothing = 0.0
			sb.max_breaks_per_step = 64
	)
	await _simulate(10)
	var before := _joint_count(sb)
	_deform(sb, Vector2(1.6, 1.6))
	await _simulate(120)
	_check(
		"force breaking tears joints that are overloaded",
		_joint_count(sb) < before,
		"joints %d -> %d" % [before, _joint_count(sb)]
	)

	_cleanup()
	# A threshold far above anything the body experiences must never break.
	var tough := _make(
		func(sb):
			sb.break_mode = SoftBody2D.BreakMode.FORCE
			sb.break_force = loaded_peak * 1000.0
			sb.break_smoothing = 0.0
	)
	await _simulate(10)
	var tough_before := _joint_count(tough)
	_deform(tough, Vector2(1.6, 1.6))
	await _simulate(120)
	_check(
		"force breaking leaves joints alone below the threshold",
		_joint_count(tough) == tough_before,
		"joints %d -> %d" % [tough_before, _joint_count(tough)]
	)


func test_15_breaking_is_frame_rate_independent() -> void:
	# Breaking used to run on render frames, so the result depended on how fast the machine
	# drew. Same simulated time at two physics rates should give a similar result.
	var results := []
	for rate in [60, 120]:
		Engine.physics_ticks_per_second = rate
		var sb := _make(
			func(sb):
				sb.break_mode = SoftBody2D.BreakMode.DISTANCE
				sb.break_distance_ratio = 1.5
		)
		await _simulate(5)
		var before := _joint_count(sb)
		_deform(sb, Vector2(3.0, 3.0))
		await _simulate(rate)  # one second of simulated time
		results.append([before, _joint_count(sb)])
		_cleanup()
	Engine.physics_ticks_per_second = 60
	var broke_at_60: int = results[0][0] - results[0][1]
	var broke_at_120: int = results[1][0] - results[1][1]
	_check(
		"similar number of joints break at 60 and 120 Hz",
		(
			broke_at_60 > 0
			and broke_at_120 > 0
			and absf(float(broke_at_60 - broke_at_120)) < maxf(broke_at_60, broke_at_120) * 0.5
		),
		"broke %d at 60Hz, %d at 120Hz" % [broke_at_60, broke_at_120]
	)

#endregion

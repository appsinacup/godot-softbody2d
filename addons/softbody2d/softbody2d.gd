@tool
@icon("res://addons/softbody2d/softbody2d.svg")
class_name SoftBody2D
extends Polygon2D

## A 2D Softbody.
##
## Models an object as a softbody by creating:[br]
## - a set of [RigidBody2D] nodes, each with one [CollisionShape2D] and a set of [Joint2D]
##   nodes connected to adjacent bodies.[br]
## - one [Skeleton2D] node with a set of [Bone2D] nodes, each positioned by a
##   [RemoteTransform2D] on its rigidbody.[br]
##
## @tutorial: https://softbody2d.appsinacup.com/

## Called after a joint is removed.
signal joint_removed(rigid_body_a: SoftBodyChild, rigid_body_b: SoftBodyChild)

## Called when a body loses its last joint and is no longer part of the softbody.
signal body_detached(rigid_body: SoftBodyChild)

## Called after generation finishes, with the number of bodies that were created.
signal baked(body_count: int)

## How joints decide to break. Only one criterion is ever active.
enum BreakMode {
	## Joints never break.
	NONE,
	## Break when the two bodies a joint holds are pulled far enough apart. Works on any
	## physics engine, but only sees joints that are actually free to stretch: a chunk being
	## dragged as a unit never stretches its own joints, so it will not come apart.
	DISTANCE,
	## Break on the force the solver applies to hold a joint together. Needs the Rapier
	## physics extension. Reports load on every joint, including ones that never visibly
	## stretch, so it tears where the stress really is.
	FORCE,
}

const MAX_REGIONS := 400
## Bits of [member SoftBody2D.debug_draw].
const DEBUG_DRAW_JOINTS := 1
const DEBUG_DRAW_SHAPES := 2
const DEBUG_COLOR_SLACK := Color(0.25, 0.55, 1.0)
const DEBUG_COLOR_LOADED := Color(1.0, 0.25, 0.2)
const DEBUG_COLOR_UNKNOWN := Color(0.5, 0.5, 0.55)
const DEBUG_COLOR_SHAPE := Color(0.4, 1.0, 0.5, 0.9)
const DEBUG_COLOR_RETIRED := Color(1.0, 0.6, 0.3, 0.9)
## Editor scale edits are folded into [member bake_scale] once they settle, see [method _notification].
const SCALE_FOLD_DELAY := 0.4
const WARNING_NO_RIGIDBODIES := (
	"No rigidbodies created. Check the vertex_interval to be lower than texture size, "
	+ "or try updating the texture_epsilon, min_alpha and margin_pixels properties."
)
const WARNING_SCALED := (
	"SoftBody2D must not be scaled, physics does not support scaled bodies. "
	+ "Use bake_scale instead, which scales the generated geometry."
)
const WARNING_PARENT_SCALED := (
	"A parent of this SoftBody2D is scaled. Physics does not support scaled bodies, "
	+ "so the simulation will not match what is drawn."
)
const WARNING_SQUARES_ON_HEXAGONS := (
	"Rectangle shapes on the hexagon pattern overlap their diagonal neighbours and collide with "
	+ "the softbody's own bodies once they rotate. Use Circle, or the rectangle pattern."
)
const WARNING_FORCE_WITHOUT_RAPIER := (
	"break_mode is FORCE, which needs the Godot Rapier Physics extension to be installed "
	+ "and selected as the 2D physics engine. Without it no joint will ever break."
)

## Draw regions of edge polygon.[br]
## 1a. Creates edge vertices from texture.[br]
## 1b. Creates multiple voronoi regions with roughly same total size as the edge vertices AABB.[br]
## 1c. Delete the voronoi regions not inside the polygon.[br]
@export var draw_regions := false:
	set(value):
		if draw_regions == value:
			return
		draw_regions = value
		_request_regeneration()

## Distance between internal vertices.[br]
## Changing this also resets [member SoftBody2D.radius] to a value derived from it.
@export_range(0.1, 50, 1, "or_greater") var vertex_interval := 30:
	set(value):
		if vertex_interval == value:
			return
		vertex_interval = value
		radius = value - value * 0.05
		_request_regeneration()

## Scale baked into the generated geometry.[br]
## Use this instead of the node's [member Node2D.scale], which physics engines do not
## support on rigidbodies. Scaling the node in the editor folds the change in here
## automatically. [member SoftBody2D.vertex_interval] and [member SoftBody2D.radius] stay in
## world units, so a larger body gets more particles of the same size rather than bigger ones.
@export var bake_scale := Vector2.ONE:
	set(value):
		if bake_scale == value:
			return
		if is_zero_approx(value.x) || is_zero_approx(value.y):
			push_error("bake_scale cannot be zero on either axis.")
			return
		bake_scale = value
		_request_regeneration()

## Properties that relate to the image used to generate the polygons and regions
@export_group("Region")
## Type of shape to create pattern
@export_enum("rectangle", "hexagon") var pattern_type := "hexagon":
	set(value):
		if pattern_type == value:
			return
		pattern_type = value
		_request_regeneration()

## Create softbody with holes
@export var exclude_texture: Texture2D:
	set(value):
		if exclude_texture == value:
			return
		exclude_texture = value
		_request_regeneration()

## Epsilon for making polygon from texture. Smaller value results in more accurate result,
## but more vertices
@export_range(0.1, 50, 0.01, "or_greater") var texture_epsilon := 1:
	set(value):
		if texture_epsilon == value:
			return
		texture_epsilon = value
		_request_regeneration()

## Min alpha to consider the point part of polygon
@export_range(0.01, 1, 0.01, "or_greater") var min_alpha := 0.05:
	set(value):
		if min_alpha == value:
			return
		min_alpha = value
		_request_regeneration()

## Amount to grow or shrink the image with in pixels. Adds dilatation if positive, if
## negative adds erosion.
@export_range(-50, 50, 1, "or_greater") var margin_pixels := 0:
	set(value):
		if margin_pixels == value:
			return
		margin_pixels = value
		_request_regeneration()

## Offset from Texture Center for the polygon. Use this if some rigidbodies are positioned weirdly.
@export var polygon_offset := Vector2():
	set(value):
		if polygon_offset == value:
			return
		polygon_offset = value
		_request_regeneration()

## Minimum area of a region that was cut. If it's less than this, it will be added to
## another region close to it.
@export_range(0.01, 1, 0.01) var min_area := 0.2:
	set(value):
		if min_area == value:
			return
		min_area = value
		_request_regeneration()

## Set properties related to the generated joints between rigidbodies.
@export_group("Joint")
## The joint type. Pin yields a more sturdy softbody, and uses [PinJoint2D], while spring a
## more soft one, and uses [DampedSpringJoint2D].
@export_enum("pin", "spring") var joint_type := "pin":
	set(value):
		if joint_type == value:
			return
		joint_type = value
		_request_regeneration()

## Sets the [member Joint2D.bias] property of the joint.
@export_range(0, 2, 0.1, "or_greater") var bias: float = 0:
	set(value):
		bias = value
		_set_joint_property(&"bias", bias)

## Sets the [member Joint2D.disable_collision] property of the joint.
@export var disable_collision := true:
	set(value):
		disable_collision = value
		_set_joint_property(&"disable_collision", disable_collision)

## How far joints reach. 1 joins each body to its neighbours only, which is squishy but lets
## the softbody shear and sag under its own weight. 2 also joins each body to the bodies two
## hops away, anchored midway; those joints hold the overall shape inside the physics solver
## while the one-hop joints keep it squishy, so it comes back after being leaned or squashed.
## 3 reaches one hop further and is stiffer again. Each step roughly doubles the joint
## count.[br]
## Measured at [member SoftBody2D.softness] 60 on a resting softbody, 1 to 2: sag 15% to 8%,
## shape error after a lean 22 px to 6 px, and no more self collision.
@export_range(1, 3) var joint_reach := 2:
	set(value):
		if joint_reach == value:
			return
		joint_reach = value
		_request_regeneration()

## Squeeze past which a joint takes a permanent set. A joint pushed shorter than its rest
## length by more than this share is re-anchored at its current length, so a dent stays:
## clay rather than rubber. Stretching always springs back. 0 keeps the softbody fully
## elastic. Interior joints need [member SoftBody2D.interior_strength] times as much.
@export_range(0, 1, 0.01) var yield_strain := 0.0

## Most permanent squeeze a joint may accumulate, as a share of its original length. Past
## it the joint stops yielding and stays elastic from where it flowed to.
@export_range(0.01, 0.9, 0.01) var yield_limit := 0.3

@export_subgroup("Break")
## Which break criterion to use. The thresholds for the other modes are hidden in the
## inspector, since only the selected one has any effect.
@export var break_mode: BreakMode = BreakMode.DISTANCE:
	set(value):
		if break_mode == value:
			return
		break_mode = value
		notify_property_list_changed()

## Joints break once stretched this many times past the distance they were created at.
## 0 disables breaking. Used when [member SoftBody2D.break_mode] is [constant BreakMode.DISTANCE].
@export_range(0, 2, 0.1, "or_greater") var break_distance_ratio := 0.0

## Joints break once the force holding them together exceeds this value. 0 disables
## breaking. Used when [member SoftBody2D.break_mode] is [constant BreakMode.FORCE].[br]
## Pick it by watching the load your softbody actually sees, then setting the threshold
## below the peak you want to survive.
@export_range(0, 100000, 1, "or_greater") var break_force := 0.0

## Joints break once the torque they apply exceeds this value, so bodies tear under
## twisting and not only under pulling. 0 disables it.
@export_range(0, 100000, 1, "or_greater") var break_torque := 0.0

## How much force readings are smoothed before being compared against
## [member SoftBody2D.break_force].[br]
## 0 breaks the moment one reading crosses the threshold, so a single spike snaps a joint.
## Closer to 1 the readings are averaged over time and the joint only breaks under a
## sustained pull; a brief knock is shrugged off.
@export_range(0, 0.99, 0.01) var break_smoothing := 0.5

## How much tougher a joint deep inside the softbody is than one at its surface.[br]
## A joint between two interior bodies that still have all their joints needs this many
## times the break threshold; joints at the outline, or next to bodies that already lost a
## joint, break at the threshold itself. Tears then start at the surface or at existing
## damage and run inward, instead of anywhere a body happens to be pulled. 1 treats every
## joint the same.
@export_range(1, 10, 0.1, "or_greater") var interior_strength := 4.0

## Maximum number of joints that may break in a single physics step.[br]
## Caps the cost of the cascade when a softbody is destroyed all at once.
@export_range(1, 64, 1, "or_greater") var max_breaks_per_step := 3

@export_subgroup("DampedSpringJoint")
## Relevant only if you picked [member SoftBody2D.joint_type] = "spring". Sets the
## [member DampedSpringJoint2D.stiffness] property of the joint.
@export_range(0.1, 128, 0.1, "or_greater") var stiffness: float = 10:
	set(value):
		stiffness = value
		_set_joint_property(&"stiffness", stiffness, "DampedSpringJoint2D")

## Relevant only if you picked [member SoftBody2D.joint_type] = "spring". Sets the
## [member DampedSpringJoint2D.damping] property of the joint.
@export_range(0.01, 16, 0.1, "or_greater") var damping: float = 0.2:
	set(value):
		damping = value
		_set_joint_property(&"damping", damping, "DampedSpringJoint2D")

## Sets the [member DampedSpringJoint2D.rest_length] property of the joint based on the
## distance between bones.
@export_range(0, 2, 0.1, "or_greater") var rest_length_ratio: float = 0:
	set(value):
		rest_length_ratio = value
		_for_each_joint(
			func(joint: Joint2D): joint.set(&"rest_length", joint.get_meta("joint_distance") * rest_length_ratio),
			"DampedSpringJoint2D"
		)

## Sets the [member DampedSpringJoint2D.length] property of the joint based on the distance
## between bones.
@export_range(0, 2, 0.1, "or_greater") var length_ratio: float = 0:
	set(value):
		length_ratio = value
		_for_each_joint(
			func(joint: Joint2D): joint.set(&"length", joint.get_meta("joint_distance") * length_ratio),
			"DampedSpringJoint2D"
		)

@export_subgroup("PinJoint")
## Relevant only if you picked [member SoftBody2D.joint_type] = "pin". Sets the
## [member PinJoint2D.softness] property of the joint.
@export_range(0, 100, 0.1, "or_greater") var softness: float = 60:
	set(value):
		softness = value
		_set_joint_property(&"softness", softness, "PinJoint2D")

## Relevant only if you picked [member SoftBody2D.joint_type] = "pin". Sets the
## [member PinJoint2D.angular_limit_enabled] property of the joint.
@export var angular_limit_enabled: bool = false:
	set(value):
		angular_limit_enabled = value
		_set_joint_property(&"angular_limit_enabled", angular_limit_enabled, "PinJoint2D")

## Relevant only if you picked [member SoftBody2D.joint_type] = "pin". Sets the
## [member PinJoint2D.angular_limit_lower] property of the joint, in degrees.
@export_range(-180, 180, 0.1, "suffix:°") var angular_limit_lower: float = 0.0:
	set(value):
		angular_limit_lower = value
		_set_joint_property(&"angular_limit_lower", deg_to_rad(angular_limit_lower), "PinJoint2D")

## Relevant only if you picked [member SoftBody2D.joint_type] = "pin". Sets the
## [member PinJoint2D.angular_limit_upper] property of the joint, in degrees.
@export_range(-180, 180, 0.1, "suffix:°") var angular_limit_upper: float = 0.0:
	set(value):
		angular_limit_upper = value
		_set_joint_property(&"angular_limit_upper", deg_to_rad(angular_limit_upper), "PinJoint2D")

## Properties that change every shape created for this softbody.
@export_group("Shape")
## Sets the [member Shape2D size].
@export_range(2, 50, 0.1, "or_greater") var radius := 20:
	set(value):
		radius = value
		for body in get_rigid_bodies():
			if body.shape:
				SoftBody2DBuilder.size_shape(body.shape.shape, radius, body.rigidbody.get_meta("shape_fit", 1.0))

## What kind of shape to create for each rigidbody. Circles are the right choice for the
## hexagon pattern: squares of the same size overlap their diagonal neighbours at rest and
## reach past their second neighbours once they rotate, so the softbody collides with itself.
@export_enum("Circle", "Rectangle") var shape_type := "Circle":
	set(value):
		if shape_type == value:
			return
		shape_type = value
		for body in get_rigid_bodies():
			if body.shape:
				var fit: float = body.rigidbody.get_meta("shape_fit", 1.0)
				body.shape.shape = SoftBody2DBuilder.new_shape(shape_type, radius, fit)

## Least distance a body may sit from the texture outline, so its collision shape does not
## poke out of the drawn softbody. Bodies closer than this are pushed inward along their
## local edge. -1 fits it to the shape automatically (half of [member SoftBody2D.radius]),
## 0 disables it.
@export_range(-1, 50, 0.5, "or_greater") var edge_clearance := -1.0:
	set(value):
		if edge_clearance == value:
			return
		edge_clearance = value
		_request_regeneration()

## How the texture follows the bodies. Purely visual.
@export_group("Skin")
## How far the texture blends across region borders. 0 pins every vertex to its own region's
## bone; higher values let nearby bones pull too, so the surface bends smoothly instead of
## kinking at every border. Baked into the weights at generation.
@export_range(0, 1, 0.05) var skin_smoothing := 0.5:
	set(value):
		if skin_smoothing == value:
			return
		skin_smoothing = value
		_request_regeneration()

## Properties that change every rigidbody created for this softbody.
@export_group("RigidBody")
## Sets the mass.
@export var mass := 0.1:
	set(value):
		mass = value
		_set_body_property(&"mass", mass)

## Sets the can_sleep.
@export var can_sleep := true:
	set(value):
		can_sleep = value
		_set_body_property(&"can_sleep", can_sleep)

## Sets the gravity scale. Each rigidbody will have [member RigidBody2D.gravity_scale] set to this amount.
@export_range(-1, 1, 0.01) var gravity_scale := 1.0:
	set(value):
		gravity_scale = value
		_set_body_property(&"gravity_scale", gravity_scale)

## Sets the constant force. Each rigidbody will have [member RigidBody2D.constant_force] set to this amount.
@export var constant_force := Vector2():
	set(value):
		constant_force = value
		_set_body_property(&"constant_force", constant_force)

## Sets the constant torque. Each rigidbody will have [member RigidBody2D.constant_torque] set to this amount.
@export var constant_torque := 0.0:
	set(value):
		constant_torque = value
		_set_body_property(&"constant_torque", constant_torque)

## Sets the [member PhysicsBody2D.collision_layer].
@export_flags_2d_physics var collision_layer := 1:
	set(value):
		collision_layer = value
		_set_body_property(&"collision_layer", collision_layer)

## Sets the [member PhysicsBody2D.collision_mask].
@export_flags_2d_physics var collision_mask := 1:
	set(value):
		collision_mask = value
		_set_body_property(&"collision_mask", collision_mask)

## Exclude [member PhysicsBody2D.add_collision_exception_with].
@export var exclude_array: Array[Node] = []:
	set(value):
		if exclude_array == value:
			return
		for body in get_rigid_bodies():
			for exclude in exclude_array:
				if exclude != null:
					body.rigidbody.remove_collision_exception_with(exclude)
		exclude_array = value
		for body in get_rigid_bodies():
			for exclude in exclude_array:
				if exclude != null:
					body.rigidbody.add_collision_exception_with(exclude)
	get:
		if !exclude_array:
			return []
		return exclude_array

## A custom rigidbody scene from which to create the rigidbody. Useful if you want to have
## custom rigidbodies with custom scripts.
@export var rigidbody_scene: PackedScene:
	set(value):
		if rigidbody_scene == value:
			return
		rigidbody_scene = value
		_request_regeneration()

## Sets the [member RigidBody2D.physics_material_override].
@export var physics_material_override: PhysicsMaterial:
	set(value):
		physics_material_override = value
		_set_body_property(&"physics_material_override", physics_material_override)

## Sets the [member RigidBody2D.linear_damp]. Slightly overdamped bodies read as softer and
## settle without jitter.
@export_range(0, 100, 0.01, "or_greater") var linear_damp := 0.0:
	set(value):
		linear_damp = value
		_set_body_property(&"linear_damp", linear_damp)

## Sets the [member RigidBody2D.angular_damp].
@export_range(0, 100, 0.01, "or_greater") var angular_damp := 0.0:
	set(value):
		angular_damp = value
		_set_body_property(&"angular_damp", angular_damp)

## Draws on top of the texture, in the editor and in game. Joints are coloured by load, blue
## when slack and red at the break threshold, or at the highest load seen so far when nothing
## breaks. With Rapier the load is the joint's reaction force, otherwise its stretch.
## Collision shapes are green, orange once their body has left the softbody.
@export_group("Debug")
@export_flags("Joints", "Shapes") var debug_draw := 0:
	set(value):
		debug_draw = value
		queue_redraw()

var _bones_array: Array[Bone2D]
var _skeleton_node: Skeleton2D
var _soft_body_rigidbodies_array: Array[SoftBodyChild]
var _soft_body_rigidbodies_dict: Dictionary
# Joint caches are keyed by instance id, so entries never hold a reference to a freed joint.
var _joint_target := Dictionary()
var _joint_rest_distance_squared := Dictionary()
var _joint_force_stress := Dictionary()
var _joint_torque_stress := Dictionary()
var _lattice := SoftBody2DLattice.new(self)
var _scale_at_ready := Vector2.ONE
var _scale_fold_generation := 0
var _regeneration_pending := false
var _debug_peak_load := 0.0

## The center of the softbody at the time the node became ready. Call
## [method SoftBody2D.get_bones_center_position] for the current value.
@onready var bone_center_position = get_bones_center_position()
@onready var _last_texture = texture


## A rigidbody of the softbody together with its bone, joints and collision shape.
## [member joints] are the joints parented to this body: every pair of bodies is joined by
## one joint, which lives on one of the two. Use [method SoftBody2D.get_joint_target] for the
## body on the other end.
class SoftBodyChild:
	var rigidbody: PhysicsBody2D
	var bone: Bone2D
	var joints: Array[Joint2D]
	var shape: CollisionShape2D


#region Lifecycle


func _ready():
	if Engine.is_editor_hint():
		_scale_at_ready = scale
		set_notify_local_transform(true)
		return
	_update_vars()


func _set(property, value):
	if property == "texture":
		texture = value as Texture2D
		# Keep the editor poll in _process from regenerating a second time.
		_last_texture = texture
		_request_regeneration()
		return true
	return false


# Only the knobs of the selected break mode show.
func _validate_property(property: Dictionary) -> void:
	var hidden := false
	match property.name:
		"break_distance_ratio":
			hidden = break_mode != BreakMode.DISTANCE
		"break_force", "break_torque", "break_smoothing":
			hidden = break_mode != BreakMode.FORCE
		"max_breaks_per_step", "interior_strength":
			hidden = break_mode == BreakMode.NONE
	if hidden:
		property.usage = PROPERTY_USAGE_NO_EDITOR


func _get_configuration_warnings():
	var warnings: Array[String] = []
	if break_mode == BreakMode.FORCE && !SoftBody2DPhysics.has_rapier():
		warnings.append(WARNING_FORCE_WITHOUT_RAPIER)
	if texture == null:
		warnings.append("No texture set.")
	if get_child_count() == 0:
		warnings.append(WARNING_NO_RIGIDBODIES)
	if !get_node_or_null(skeleton):
		warnings.append("Skeleton2D empty.")
	if scale != Vector2.ONE:
		warnings.append(WARNING_SCALED)
	if shape_type == "Rectangle" && pattern_type == "hexagon":
		warnings.append(WARNING_SQUARES_ON_HEXAGONS)
	var parent_2d := get_parent() as Node2D
	if parent_2d && parent_2d.get_global_transform().get_scale() != Vector2.ONE:
		warnings.append(WARNING_PARENT_SCALED)
	return warnings


# Physics engines do not support scaled rigidbodies, so an editor scale edit is folded into
# bake_scale once it settles. The gizmo and the inspector both end up here; a scene loading
# with a saved scale does not, because it is not ready yet.
func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED && _scale_needs_folding():
		_schedule_scale_fold()


func _scale_needs_folding() -> bool:
	return (
		Engine.is_editor_hint()
		&& is_inside_tree()
		&& is_node_ready()
		&& scale != _scale_at_ready
		&& !scale.is_equal_approx(Vector2.ONE)
		&& !is_zero_approx(scale.x)
		&& !is_zero_approx(scale.y)
	)


# The gizmo rewrites scale on every mouse motion, each time relative to the scale at drag
# start, so folding per event would compound. Wait for the drag to settle instead.
func _schedule_scale_fold() -> void:
	_scale_fold_generation += 1
	var generation := _scale_fold_generation
	get_tree().create_timer(SCALE_FOLD_DELAY).timeout.connect(
		func():
			if generation == _scale_fold_generation && _scale_needs_folding():
				_fold_scale_into_bake_scale()
	)


func _fold_scale_into_bake_scale() -> void:
	var folded := bake_scale * scale
	scale = Vector2.ONE
	_scale_at_ready = Vector2.ONE
	bake_scale = folded


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		# Picks up texture changes made outside the inspector.
		if texture != _last_texture:
			_last_texture = texture
			_request_regeneration()
	elif _skeleton_node:
		# The skin is visual, so it follows the bodies once per drawn frame, not per physics tick.
		_lattice.update_skin_rotations(global_rotation)
	if debug_draw != 0:
		queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() || !_skeleton_node:
		return
	if yield_strain > 0.0:
		_process_yielding()
	_process_breaking(delta)


#endregion

#region Public API


## Create debug regions. Good to visualize how softbody regions will look in the end
func create_regions():
	var regions := SoftBody2DRegions.new(self)
	var generated := regions.generate()
	if generated.is_empty():
		return
	_apply_generated_polygon(generated)
	var voronoi_node := Voronoi2D.new()
	add_child(voronoi_node)
	var limits := regions.polygon_limits()
	voronoi_node.size = limits[1] - limits[0]
	voronoi_node.distance_between_points = vertex_interval
	if Engine.is_editor_hint():
		voronoi_node.set_owner(get_tree().get_edited_scene_root())
	voronoi_node.draw_voronoi(generated["regions"])


## Call this to create a new softbody at runtime.
func create_softbody2d(runtime: bool = false):
	# Setters fire while a scene loads, before the node is in the tree; nothing to build then.
	if !runtime && (!Engine.is_editor_hint() || !is_inside_tree()):
		return
	clear_softbody2d()
	if draw_regions:
		create_regions()
		return
	var generated := SoftBody2DRegions.new(self).generate()
	if generated.is_empty() || (generated["regions"] as Array).is_empty():
		push_error("No regions created. Vertex interval is probably too big.")
		return
	_apply_generated_polygon(generated)
	var skeleton_node := SoftBody2DBuilder.new(self).build(generated)
	_update_soft_body_rigidbodies(skeleton_node)
	if !Engine.is_editor_hint():
		_update_vars()
	baked.emit(_soft_body_rigidbodies_array.size())


# Setters regenerate through here so one edit that touches several properties (or a drag
# in the inspector) rebuilds once, at the end of the frame, instead of once per property.
# Editor only: at runtime setters never regenerate, [method create_softbody2d] does.
func _request_regeneration() -> void:
	if !Engine.is_editor_hint() || !is_inside_tree() || _regeneration_pending:
		return
	_regeneration_pending = true
	_regenerate_now.call_deferred()


func _regenerate_now() -> void:
	_regeneration_pending = false
	create_softbody2d()


func _apply_generated_polygon(generated: Dictionary) -> void:
	set_polygon(generated["vertices"])
	set_uv(PackedVector2Array())
	set_internal_vertex_count(generated["internal_vertex_count"])
	set_polygons(generated["polygons"])
	# Vertices are generated in world units, so the texture mapping has to be stretched by
	# the inverse of bake_scale to still line up with them.
	texture_scale = Vector2.ONE / bake_scale


## Call this to clear all children, polygons and bones.
func clear_softbody2d():
	_clear_polygon()
	for child in get_children():
		child.queue_free()
		remove_child(child)
	clear_bones()
	_soft_body_rigidbodies_array = []
	_soft_body_rigidbodies_dict.clear()
	_joint_target.clear()
	_joint_rest_distance_squared.clear()
	_joint_force_stress.clear()
	_joint_torque_stress.clear()
	_lattice.reset()


## Remove the joint between two bodies. Useful if you want to make breakable softbodies.[br]
## Also updates the polygon weights, the bone look-at targets and retires bodies that lost
## their last joint.
func remove_joint(rigid_body_child: SoftBodyChild, joint: Joint2D):
	if Engine.is_editor_hint():
		_update_vars()
	var body_b := get_joint_target(joint)
	if body_b == null:
		push_error("SoftBody2D.remove_joint: joint '%s' points at a missing body." % joint.name)
		return
	var bone_a_idx := _bone_index_by_name(rigid_body_child.rigidbody.get_meta("bone_name"))
	var bone_b_idx := _bone_index_by_name(body_b.get_meta("bone_name"))
	if bone_a_idx < 0 || bone_b_idx < 0:
		push_error("SoftBody2D.remove_joint: could not resolve both bones of joint '%s'." % joint.name)
		return
	var bone_a := _bones_array[bone_a_idx]
	var bone_b := _bones_array[bone_b_idx]
	var child_a := _child_for_bone(bone_a)
	var child_b := _child_for_bone(bone_b)
	if child_a == null || child_b == null:
		push_error("SoftBody2D.remove_joint: could not resolve both bodies of joint '%s'." % joint.name)
		return

	var pieces_before := _lattice.get_cluster_indices().size()
	_free_joint_pair(child_a, child_b, joint)
	_split_shared_weights(bone_a_idx, bone_b_idx)
	if int(joint.get_meta("hops", 1)) == 1:
		child_a.rigidbody.set_meta("damaged", true)
		child_b.rigidbody.set_meta("damaged", true)
		_disconnect_bones(bone_a, bone_a_idx, bone_b, bone_b_idx)
		_retire_if_lone(bone_a, child_a)
		_retire_if_lone(bone_b, child_b)
	_update_soft_body_rigidbodies(_skeleton_node)
	_lattice.invalidate()
	if _lattice.get_cluster_indices().size() != pieces_before:
		_drop_weights_between_pieces()
	joint_removed.emit(child_a, child_b)


## Cut the softbody along a line segment given in global coordinates, removing every joint
## that crosses it. Returns how many joints were removed.[br]
## Use this for slicing with a blade, a laser or a swipe gesture. Whether the cut actually
## separates the softbody depends on the line reaching all the way across it.
func cut(from: Vector2, to: Vector2) -> int:
	var removed := 0
	for rigid_body in get_rigid_bodies():
		# remove_joint mutates this array, so iterate a copy.
		for joint in rigid_body.joints.duplicate():
			if joint == null || joint.is_queued_for_deletion():
				continue
			var body_b := get_joint_target(joint)
			if body_b == null:
				continue
			var joint_from := rigid_body.rigidbody.global_position
			if Geometry2D.segment_intersects_segment(joint_from, body_b.global_position, from, to) != null:
				remove_joint(rigid_body, joint)
				removed += 1
	return removed


## Get all the bodies, including joints and shape
func get_rigid_bodies() -> Array[SoftBodyChild]:
	if _soft_body_rigidbodies_array.is_empty() || Engine.is_editor_hint():
		if !_skeleton_node:
			_skeleton_node = get_node_or_null(skeleton)
		_update_soft_body_rigidbodies(_skeleton_node)
	return _soft_body_rigidbodies_array


## The body on the far side of [param joint]. [member Joint2D.node_b] is a path relative to
## the joint, so this works for any hierarchy. Cached per joint.
func get_joint_target(joint: Joint2D) -> PhysicsBody2D:
	var id := joint.get_instance_id()
	if _joint_target.has(id):
		var cached = _joint_target[id]
		if is_instance_valid(cached):
			return cached
	var body := joint.get_node_or_null(joint.node_b) as PhysicsBody2D
	if body != null:
		_joint_target[id] = body
	return body


## Computes the center of the softbody. Returns the node's own position if it has no bodies.
func get_bones_center_position() -> Vector2:
	var bodies := _soft_body_rigidbodies_array
	if bodies.is_empty():
		return global_position
	var center = Vector2()
	for body in bodies:
		center = center + body.rigidbody.global_position
	return center / bodies.size()


## Get the body located in the center
func get_center_body() -> SoftBodyChild:
	var bodies := get_rigid_bodies()
	var rb_array := bodies.map(func(body): return body.rigidbody)
	var center_rb := SoftBody2DBuilder.node_nearest_centre(rb_array)
	return _soft_body_rigidbodies_dict[center_rb]


## Apply an impulse to every body.[br]
## [param position] is an offset from each body's own center of mass, so a non-zero value
## applies the same offset to all of them. To push from a point in the world, use
## [method SoftBody2D.apply_impulse_at_point].
func apply_impulse(impulse: Vector2, position: Vector2 = Vector2(0, 0)):
	for softbody_el in get_rigid_bodies():
		var rigidbody := softbody_el.rigidbody as RigidBody2D
		if rigidbody:
			rigidbody.apply_impulse(impulse, position)


## Apply a force to every body.[br]
## [param position] is an offset from each body's own center of mass, so a non-zero value
## applies the same offset to all of them.
func apply_force(force: Vector2, position: Vector2 = Vector2(0, 0)):
	for softbody_el in get_rigid_bodies():
		var rigidbody := softbody_el.rigidbody as RigidBody2D
		if rigidbody:
			rigidbody.apply_force(force, position)


## Apply an impulse originating at a global point, so bodies further from it are pushed
## with the correct lever arm. This is usually what explosions and hits want.[br]
## If [param falloff_radius] is greater than 0, the impulse fades linearly to nothing at
## that distance from [param global_point].
func apply_impulse_at_point(impulse: Vector2, global_point: Vector2, falloff_radius: float = 0.0) -> void:
	for softbody_el in get_rigid_bodies():
		var body := softbody_el.rigidbody as RigidBody2D
		if body == null:
			continue
		var scaled_impulse := impulse
		if falloff_radius > 0.0:
			var distance := body.global_position.distance_to(global_point)
			if distance >= falloff_radius:
				continue
			scaled_impulse *= 1.0 - distance / falloff_radius
		body.apply_impulse(scaled_impulse, global_point - body.global_position)


## Get the connected groups of bodies. Right after generation there is one group; every time
## breaking splits the softbody, another one appears.[br]
## Each entry is an array of [SoftBodyChild].
func get_clusters() -> Array:
	var bodies := get_rigid_bodies()
	var result := []
	for cluster in _lattice.get_cluster_indices():
		var group: Array[SoftBodyChild] = []
		for idx in cluster:
			if idx < bodies.size():
				group.append(bodies[idx])
		result.append(group)
	return result


#endregion

#region Runtime state


func _update_vars():
	_skeleton_node = get_node_or_null(skeleton)
	if get_child_count() == 0:
		return
	if !_skeleton_node:
		push_warning("SoftBody2D has bodies but no Skeleton2D. Re-generate the softbody.")
		return
	_bones_array.clear()
	for bone in _skeleton_node.get_children():
		if bone is Bone2D:
			_bones_array.append(bone)
	_update_soft_body_rigidbodies(_skeleton_node)
	_cache_joint_state()
	_disable_legacy_lookat()


# Scenes generated by older versions carry a look-at modification stack and persistent pose
# overrides; both would overwrite the skin rotations written each step, so they are turned off.
func _disable_legacy_lookat() -> void:
	var stack := _skeleton_node.get_modification_stack()
	if stack:
		stack.enabled = false
	for i in _skeleton_node.get_bone_count():
		_skeleton_node.set_bone_local_pose_override(i, Transform2D(), 0.0, false)


func _cache_joint_state() -> void:
	_joint_target.clear()
	_joint_rest_distance_squared.clear()
	_joint_force_stress.clear()
	_joint_torque_stress.clear()
	for rigid_body in get_rigid_bodies():
		for joint in rigid_body.joints:
			var body_b := get_joint_target(joint)
			if body_b == null:
				push_warning("SoftBody2D: joint '%s' points at a missing body." % joint.name)
				continue
			var rest_distance: float
			if joint.has_meta("joint_distance"):
				rest_distance = joint.get_meta("joint_distance")
			else:
				# Softbody generated by an older version of the plugin.
				rest_distance = rigid_body.rigidbody.global_position.distance_to(body_b.global_position)
			_joint_rest_distance_squared[joint.get_instance_id()] = rest_distance * rest_distance
	_lattice.invalidate()


func _forget_joint(joint: Joint2D) -> void:
	var id := joint.get_instance_id()
	_joint_target.erase(id)
	_joint_rest_distance_squared.erase(id)
	_joint_force_stress.erase(id)
	_joint_torque_stress.erase(id)


func _update_soft_body_rigidbodies(skeleton_node: Skeleton2D = null):
	if !skeleton_node:
		return
	var bones_by_name := {}
	for bone in skeleton_node.get_children():
		bones_by_name[bone.name] = bone
	var result: Array[SoftBodyChild]
	_soft_body_rigidbodies_dict.clear()
	for child in get_children():
		if child is Skeleton2D || !bones_by_name.has(child.name):
			continue
		var softbody_child = SoftBodyChild.new()
		softbody_child.rigidbody = child as PhysicsBody2D
		softbody_child.bone = bones_by_name[child.name]
		for rb_child in child.get_children():
			if rb_child is CollisionShape2D:
				if softbody_child.shape == null:
					softbody_child.shape = rb_child
			elif rb_child is Joint2D && !rb_child.is_queued_for_deletion():
				softbody_child.joints.append(rb_child)
		result.append(softbody_child)
		_soft_body_rigidbodies_dict[softbody_child.rigidbody] = softbody_child
	_soft_body_rigidbodies_array = result


func _set_joint_property(property: StringName, value: Variant, joint_class := "") -> void:
	_for_each_joint(func(joint: Joint2D): joint.set(property, value), joint_class)


func _for_each_joint(apply: Callable, joint_class := "") -> void:
	for body in get_rigid_bodies():
		for joint in body.joints:
			if joint_class.is_empty() || joint.is_class(joint_class):
				apply.call(joint)


func _set_body_property(property: StringName, value: Variant) -> void:
	for body in get_rigid_bodies():
		body.rigidbody.set(property, value)


#endregion

#region Joint removal


func _bone_index_by_name(bone_name: String) -> int:
	for i in _bones_array.size():
		if _bones_array[i].name == bone_name:
			return i
	return -1


func _child_for_bone(bone: Bone2D) -> SoftBodyChild:
	for rigid_body in get_rigid_bodies():
		if rigid_body.bone == bone:
			return rigid_body
	return null


# Scenes from older versions joint every pair in both directions; the reciprocal goes too.
func _free_joint_pair(child_a: SoftBodyChild, child_b: SoftBodyChild, joint: Joint2D) -> void:
	child_a.joints.erase(joint)
	var name_a: StringName = child_a.rigidbody.name
	for joint_b in child_b.joints:
		if _last_name(joint_b.node_a) == name_a || _last_name(joint_b.node_b) == name_a:
			child_b.joints.erase(joint_b)
			_forget_joint(joint_b)
			joint_b.queue_free()
			break
	_forget_joint(joint)
	joint.queue_free()


func _last_name(path: NodePath) -> StringName:
	return path.get_name(path.get_name_count() - 1)


# Each region has its own copies of the border vertices; the copies coincide because both
# bones weight them alike. Tearing is letting each side's copies drop the other bone.
func _split_shared_weights(bone_a_idx: int, bone_b_idx: int) -> void:
	var weights_a := get_bone_weights(bone_a_idx)
	var weights_b := get_bone_weights(bone_b_idx)
	for vertex in _bones_array[bone_a_idx].get_meta("vert_owned"):
		weights_b[vertex] = 0.0
	for vertex in _bones_array[bone_b_idx].get_meta("vert_owned"):
		weights_a[vertex] = 0.0
	set_bone_weights(bone_a_idx, weights_a)
	set_bone_weights(bone_b_idx, weights_b)


# Smoothing lets a vertex be pulled by bones up to two hops away, so once the softbody has
# split into pieces, weights that reach across pieces would stretch slivers of texture
# between them. Every vertex keeps only the bones of the piece its own region belongs to.
func _drop_weights_between_pieces() -> void:
	var bodies := get_rigid_bodies()
	var piece_of := {}
	var pieces := _lattice.get_cluster_indices()
	for piece_index in pieces.size():
		for body_index in pieces[piece_index]:
			piece_of[int(bodies[body_index].bone.get_meta("idx"))] = piece_index
	# The outline ring (the first vertices) is owned by no region and drawn by no triangle.
	var owner_piece := PackedInt32Array()
	owner_piece.resize(polygon.size())
	owner_piece.fill(-1)
	for bone_index in _bones_array.size():
		for vertex in _bones_array[bone_index].get_meta("vert_owned"):
			owner_piece[vertex] = piece_of.get(bone_index, -1)
	for bone_index in _bones_array.size():
		var piece: int = piece_of.get(bone_index, -1)
		var weights := get_bone_weights(bone_index)
		var changed := false
		for vertex in weights.size():
			if weights[vertex] > 0.0 && owner_piece[vertex] != piece:
				weights[vertex] = 0.0
				changed = true
		if changed:
			set_bone_weights(bone_index, weights)


# The connection metadata is what survives saving the scene.
func _disconnect_bones(bone_a: Bone2D, bone_a_idx: int, bone_b: Bone2D, bone_b_idx: int) -> void:
	_disconnect_bone(bone_a, bone_b.name, bone_b_idx)
	_disconnect_bone(bone_b, bone_a.name, bone_a_idx)


func _disconnect_bone(bone: Bone2D, other_name: String, other_idx: int) -> void:
	var paths: Array = bone.get_meta("connected_nodes_paths")
	var indices: Array = bone.get_meta("connected_nodes_idx")
	paths.erase(NodePath(other_name))
	indices.erase(other_idx)
	bone.set_meta("connected_nodes_paths", paths)
	bone.set_meta("connected_nodes_idx", indices)


func _retire_if_lone(bone: Bone2D, child: SoftBodyChild) -> void:
	var connected: Array = bone.get_meta("connected_nodes_paths")
	if !connected.is_empty():
		return
	SoftBody2DBuilder.hide_lone_bone(bone)
	_free_reach_joints_of(child)
	_retire_lone_body(child, bone)


# A body whose skin neighbours are all gone must not stay tethered by its longer joints.
func _free_reach_joints_of(child: SoftBodyChild) -> void:
	for other in get_rigid_bodies():
		for joint in other.joints.duplicate():
			if int(joint.get_meta("hops", 1)) == 1:
				continue
			if other != child && get_joint_target(joint) != child.rigidbody:
				continue
			other.joints.erase(joint)
			_forget_joint(joint)
			joint.queue_free()


# A body that lost its last joint is no longer part of the softbody. Its region fades out
# by hide_lone_bone; the body is retired here so no invisible collider is left behind.
func _retire_lone_body(child: SoftBodyChild, bone: Bone2D) -> void:
	if child == null || child.rigidbody == null:
		return
	child.rigidbody.rotation = bone.rotation
	if child.shape:
		child.shape.set_deferred("disabled", true)
	if child.rigidbody is RigidBody2D:
		child.rigidbody.set_deferred("freeze", true)
	for node in child.rigidbody.get_children():
		if node is RemoteTransform2D:
			# No neighbour left to look at, so the bone takes its rotation from the body.
			node.update_rotation = true
			break
	body_detached.emit(child)


#endregion

#region Yielding


func _process_yielding() -> void:
	for child in get_rigid_bodies():
		for joint in child.joints:
			if joint == null || joint.is_queued_for_deletion():
				continue
			var target := get_joint_target(joint)
			if target == null:
				continue
			var rest: float = joint.get_meta("joint_distance", 0.0)
			var original: float = joint.get_meta("original_distance", rest)
			if rest <= 0.0:
				continue
			var now := child.rigidbody.global_position.distance_to(target.global_position)
			# Only compression sets; a stretched joint always springs back.
			var squeeze := 1.0 - now / rest
			if squeeze <= yield_strain * _joint_strength(child, target):
				continue
			if 1.0 - now / original > yield_limit:
				continue
			_yield_joint(joint, child.rigidbody, target, now)


# The joint's current length becomes its rest length. Pins are re-anchored midway; springs
# get their rest and max length scaled to it.
func _yield_joint(joint: Joint2D, body_a: PhysicsBody2D, body_b: PhysicsBody2D, length: float) -> void:
	joint.set_meta("joint_distance", length)
	_joint_rest_distance_squared[joint.get_instance_id()] = length * length
	if joint is DampedSpringJoint2D:
		joint.rest_length = length * rest_length_ratio
		joint.length = length * length_ratio
		return
	SoftBody2DBuilder.reanchor(joint, (body_a.global_position + body_b.global_position) * 0.5, body_a, body_b)


#endregion

#region Breaking


func _process_breaking(delta: float) -> void:
	if !_breaking_active():
		return
	var broken := 0
	for rigid_body in get_rigid_bodies():
		# remove_joint mutates this array, so iterate a copy.
		for joint in rigid_body.joints.duplicate():
			if broken >= max_breaks_per_step:
				return
			if joint == null || joint.is_queued_for_deletion():
				continue
			if _should_break_joint(joint, rigid_body, delta):
				broken += 1
				remove_joint(rigid_body, joint)


func _breaking_active() -> bool:
	match break_mode:
		BreakMode.DISTANCE:
			return break_distance_ratio > 0.0
		BreakMode.FORCE:
			return (break_force > 0.0 || break_torque > 0.0) && SoftBody2DPhysics.has_rapier()
		_:
			return false


func _should_break_joint(joint: Joint2D, rigid_body: SoftBodyChild, delta: float) -> bool:
	var body_b := get_joint_target(joint)
	if body_b == null:
		return false
	var strength := _joint_strength(rigid_body, body_b)
	if break_mode == BreakMode.FORCE:
		return _exceeds_force_threshold(joint, delta, strength) || _exceeds_torque_threshold(joint, delta, strength)
	if break_mode == BreakMode.DISTANCE:
		return _exceeds_distance_threshold(joint, rigid_body, body_b, strength)
	return false


# Interior joints between undamaged bodies are confined by everything around them, so they
# get interior_strength times the threshold. Surface joints and joints next to damage do not.
func _joint_strength(child_a: SoftBodyChild, body_b: PhysicsBody2D) -> float:
	if interior_strength <= 1.0:
		return 1.0
	if child_a.rigidbody.get_meta("edge", false) || body_b.get_meta("edge", false):
		return 1.0
	var child_b: SoftBodyChild = _soft_body_rigidbodies_dict.get(body_b)
	if _is_damaged(child_a) || (child_b != null && _is_damaged(child_b)):
		return 1.0
	return interior_strength


func _is_damaged(child: SoftBodyChild) -> bool:
	return child.rigidbody.get_meta("damaged", false)


# The reaction impulse is what the solver had to apply to keep the joint together, so it
# reports load even on joints that never visibly stretch.
func _exceeds_force_threshold(joint: Joint2D, delta: float, strength: float) -> bool:
	if break_force <= 0.0:
		return false
	var force := SoftBody2DPhysics.joint_reaction_impulse(joint).length() / delta
	return _smoothed_stress(_joint_force_stress, joint, force) > break_force * strength


func _exceeds_torque_threshold(joint: Joint2D, delta: float, strength: float) -> bool:
	if break_torque <= 0.0:
		return false
	var torque := absf(SoftBody2DPhysics.joint_reaction_angular_impulse(joint)) / delta
	return _smoothed_stress(_joint_torque_stress, joint, torque) > break_torque * strength


func _smoothed_stress(cache: Dictionary, joint: Joint2D, reading: float) -> float:
	var id := joint.get_instance_id()
	var previous: float = cache.get(id, reading)
	var stress := lerpf(reading, previous, break_smoothing)
	cache[id] = stress
	return stress


func _exceeds_distance_threshold(
	joint: Joint2D, rigid_body: SoftBodyChild, body_b: PhysicsBody2D, strength: float
) -> bool:
	if break_distance_ratio <= 0.0:
		return false
	# Measured against the original length, so plastic flow counts toward the tear.
	var original: float = joint.get_meta("original_distance", 0.0)
	var rest_squared: float = (
		original * original if original > 0.0 else _joint_rest_distance_squared.get(joint.get_instance_id(), 0.0)
	)
	if rest_squared <= 0.0:
		return false
	var limit_ratio := 1.0 + (break_distance_ratio - 1.0) * strength
	var limit_squared := rest_squared * limit_ratio * limit_ratio
	return limit_squared < rigid_body.rigidbody.global_position.distance_squared_to(body_b.global_position)


#endregion

#region Debug draw


func _draw() -> void:
	if debug_draw == 0:
		return
	var children := get_rigid_bodies()
	var to_local_xform := global_transform.affine_inverse()
	if debug_draw & DEBUG_DRAW_JOINTS:
		_draw_joints(children, to_local_xform)
	if debug_draw & DEBUG_DRAW_SHAPES:
		_draw_shapes(children, to_local_xform)


func _draw_joints(children: Array[SoftBodyChild], to_local_xform: Transform2D) -> void:
	for child in children:
		for joint in child.joints:
			if joint == null || joint.is_queued_for_deletion():
				continue
			var target := get_joint_target(joint)
			if target == null:
				continue
			var load := _joint_load_fraction(joint, child, target)
			var colour := DEBUG_COLOR_UNKNOWN if load < 0.0 else DEBUG_COLOR_SLACK.lerp(DEBUG_COLOR_LOADED, load)
			draw_line(
				to_local_xform * child.rigidbody.global_position, to_local_xform * target.global_position, colour, 2.0
			)


# 0 slack to 1 at the break threshold. Reaction force with Rapier, stretch otherwise; -1
# when there is nothing to measure against.
func _joint_load_fraction(joint: Joint2D, child_a: SoftBodyChild, body_b: PhysicsBody2D) -> float:
	var body_a := child_a.rigidbody
	var strength := _joint_strength(child_a, body_b)
	if SoftBody2DPhysics.has_rapier() && !Engine.is_editor_hint():
		var force := SoftBody2DPhysics.joint_reaction_impulse(joint).length() * Engine.physics_ticks_per_second
		_debug_peak_load = maxf(_debug_peak_load, force)
		var full_scale := (
			break_force * strength if break_mode == BreakMode.FORCE && break_force > 0.0 else _debug_peak_load
		)
		return clampf(force / full_scale, 0.0, 1.0) if full_scale > 0.0 else 0.0
	var rest: float = joint.get_meta("joint_distance", 0.0)
	if rest <= 0.0:
		return -1.0
	var stretch := absf(body_a.global_position.distance_to(body_b.global_position) / rest - 1.0)
	var breaking_stretch := (break_distance_ratio - 1.0) * strength
	var full_scale := breaking_stretch if break_mode == BreakMode.DISTANCE && breaking_stretch > 0.0 else 0.5
	return clampf(stretch / full_scale, 0.0, 1.0)


func _draw_shapes(children: Array[SoftBodyChild], to_local_xform: Transform2D) -> void:
	for child in children:
		var collision := child.shape
		if collision == null || collision.disabled || collision.shape == null:
			continue
		var colour := DEBUG_COLOR_SHAPE
		if child.rigidbody is RigidBody2D && (child.rigidbody as RigidBody2D).freeze:
			colour = DEBUG_COLOR_RETIRED
		var shape_xform := to_local_xform * collision.global_transform
		var shape := collision.shape
		if shape is CircleShape2D:
			draw_arc(shape_xform.origin, (shape as CircleShape2D).radius, 0.0, TAU, 24, colour, 1.5)
		elif shape is RectangleShape2D:
			var half := (shape as RectangleShape2D).size * 0.5
			var corners := PackedVector2Array()
			for corner in [
				Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)
			]:
				corners.append(shape_xform * (corner as Vector2))
			corners.append(corners[0])
			draw_polyline(corners, colour, 1.5)


#endregion

#region Polygon generation


func _clear_polygon():
	set_polygon(PackedVector2Array())
	set_polygons([])
	set_uv(PackedVector2Array())
	set_internal_vertex_count(0)

#endregion

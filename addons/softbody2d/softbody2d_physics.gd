@tool
class_name SoftBody2DPhysics
extends RefCounted

## Physics backend helpers for [SoftBody2D].
##
## Wraps the extra APIs exposed by [url=https://godot.rapier.rs]Godot Rapier Physics[/url]
## so the plugin can use them when available and silently fall back to plain Godot Physics
## when they are not. Calls go through [method ClassDB.class_call_static], so this file has
## no hard dependency on the Rapier extension being installed.

## Extra body parameter ids, mirroring the constants on the Rapier physics server.
enum BodyParam {
	CONTACT_SKIN = 0,
	DOMINANCE = 1,
	SOFT_CCD = 2,
	MASSLESS = 3,
	ADDITIONAL_SOLVER_ITERATIONS = 4,
}

const _SERVER := &"RapierPhysicsServer2D"
const _ENGINE_SETTING := "physics/2d/physics_engine"
const _ENGINE_NAME := "Rapier2D"

static var _rapier_available := -1


## Whether Rapier is installed [i]and[/i] is the active 2D physics engine. Cached after
## the first call. Having the extension installed is not enough: with Godot Physics
## selected the Rapier server never sees the joints, so every query returns zero.
static func has_rapier() -> bool:
	if _rapier_available == -1:
		var installed := ClassDB.class_exists(_SERVER)
		var active: bool = ProjectSettings.get_setting(_ENGINE_SETTING, "") == _ENGINE_NAME
		_rapier_available = 1 if installed && active else 0
	return _rapier_available == 1


## World-space linear impulse the joint applied to hold its constraint on the last physics
## step. Divide by the step delta to get a force. Returns [constant Vector2.ZERO] when
## Rapier is not available.
static func joint_reaction_impulse(joint: Joint2D) -> Vector2:
	if !has_rapier() || joint == null:
		return Vector2.ZERO
	var result: Variant = ClassDB.class_call_static(_SERVER, &"joint_get_reaction_impulse", joint.get_rid())
	return result if result is Vector2 else Vector2.ZERO


## World-space angular impulse the joint applied to hold its constraint on the last physics
## step. Returns 0 when Rapier is not available.
static func joint_reaction_angular_impulse(joint: Joint2D) -> float:
	if !has_rapier() || joint == null:
		return 0.0
	var result: Variant = ClassDB.class_call_static(_SERVER, &"joint_get_reaction_angular_impulse", joint.get_rid())
	return result if result is float else 0.0


## Set how rigidly a joint holds its constraint. Higher [param natural_frequency] is
## stiffer, [param damping_ratio] of 1 is critically damped. No-op without Rapier.
static func joint_set_softness(joint: Joint2D, natural_frequency: float, damping_ratio: float) -> void:
	if !has_rapier() || joint == null:
		return
	ClassDB.class_call_static(_SERVER, &"joint_set_softness", joint.get_rid(), natural_frequency, damping_ratio)


## Enable or disable a joint without destroying it. No-op without Rapier.
static func joint_set_enabled(joint: Joint2D, enabled: bool) -> void:
	if !has_rapier() || joint == null:
		return
	ClassDB.class_call_static(_SERVER, &"joint_set_enabled", joint.get_rid(), enabled)


## Strongest single contact impulse acting on a body during the last physics step. Needs no
## contact monitoring. Returns 0 when Rapier is not available.
static func body_max_contact_impulse(body: PhysicsBody2D) -> float:
	if !has_rapier() || body == null:
		return 0.0
	var result: Variant = ClassDB.class_call_static(_SERVER, &"body_get_max_contact_impulse", body.get_rid())
	return result if result is float else 0.0


## Set an extra body parameter. No-op without Rapier.
static func body_set_extra_param(body: PhysicsBody2D, param: BodyParam, value: Variant) -> void:
	if !has_rapier() || body == null:
		return
	ClassDB.class_call_static(_SERVER, &"body_set_extra_param", body.get_rid(), int(param), value)

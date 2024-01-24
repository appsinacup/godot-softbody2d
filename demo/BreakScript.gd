@tool
extends Node2D

@export var softbody : SoftBody2D
@export var rb_index: int = 0
@export var joint_index: int = 0
@export var remove_joint :bool = false:
	set (value):
		remove_joint_func(softbody.get_rigid_bodies()[rb_index], softbody.get_rigid_bodies()[rb_index].joints[joint_index])
	get:
		return false
	

# Called when the node enters the scene tree for the first time.
func remove_joint_func(rb: SoftBody2D.SoftBodyChild, joint: Joint2D):
	softbody.remove_joint(rb, joint)


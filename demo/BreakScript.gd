@tool
extends Node2D

@onready var softbody = $BreakableSoftbody2D
@export var remove_joint_index: int = 0
@export var remove_joint :bool = false:
	set (value):
		remove_joint_func()
	get:
		return false
	

# Called when the node enters the scene tree for the first time.
func remove_joint_func():
	var rb : SoftBody2D.SoftBodyChild = softbody.get_rigid_bodies()[remove_joint_index]
	for joint in rb.joints:
		softbody.remove_joint(rb, joint)
		return


extends Node

@export var softbody2d: SoftBody2D
@export var force: Vector2

func _on_timer_timeout():
	softbody2d.apply_force(force)

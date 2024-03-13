extends HSlider

@export var softbody: SoftBody2D

# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_value_changed(value):
	softbody.scale.x = value
	softbody.scale.y = value
	softbody.create_softbody2d(true)
	#softbody.scale.x = value

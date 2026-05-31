extends Camera3D

var delta_passed := 0.0
var frames := 0
@onready var label = $Display/CanvasLayer/Label
func _process(delta: float) -> void:
	label.text = "FPS = %s" % str(round(1/delta))

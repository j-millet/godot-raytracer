extends Camera3D

var delta_passed := 0.0
var frames := 0
@onready var label = $Display/CanvasLayer/Label
func _process(delta: float) -> void:
	delta_passed += delta
	frames += 1
	if delta_passed > 1.0:
		label.text = "FPS = %s" % str(frames)
		delta_passed -= 1.0
		frames = 0

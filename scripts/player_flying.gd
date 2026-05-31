extends Node3D


@export var speed := 1.0
@export var running_speed := 2.0
var running := false
@export var sensitivity := 1.0
var delta := 1.0

var screen_size := DisplayServer.screen_get_size()

func _ready():
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func move_in_direction(direction: Vector3, delta:float):
	self.position += direction * delta * (speed if not running else running_speed)

func _process(delta: float) -> void:

	if Input.is_action_pressed("run"):
		running = true
	else:
		running = false
	if Input.is_action_pressed("forward"):
		move_in_direction(self.basis.z,delta)
	if Input.is_action_pressed("back"):
		move_in_direction(-self.basis.z,delta)
	if Input.is_action_pressed("left"):
		move_in_direction(self.basis.x,delta)
	if Input.is_action_pressed("right"):
		move_in_direction(-self.basis.x,delta)
	if Input.is_action_pressed("up"):
		move_in_direction(self.basis.y,delta)
	if Input.is_action_pressed("down"):
		move_in_direction(-self.basis.y,delta)
	if Input.is_action_pressed("escape"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _input(event):
	if event is InputEventMouseButton:
		if event.button_index == 1:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		
	if event is InputEventMouseMotion:
		self.rotation += Vector3(event.relative.y/float(screen_size.y) * sensitivity,-event.relative.x/float(screen_size.x) * sensitivity,0)

	

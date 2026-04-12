extends Node

@onready var display := %Display
@onready var player := %Player
# Create a local rendering device.
var rd := RenderingServer.get_rendering_device()

var playerPos: Vector3
var playerRot: Vector3

var elapsedFramesNoMovement := 1
# Load GLSL shader
var shader_file := load("res://raymond.glsl")
var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
var shader := rd.shader_create_from_spirv(shader_spirv)

var texture_rd : RID
var texture_wrapper : Texture2DRD

var img : Image

var screen_size := DisplayServer.screen_get_size()
var height_width_ratio := float(screen_size.y)/float(screen_size.x)

@export var rays_per_pixel := 2;
@export var max_ray_bounces := 2;
@export var box_test_threshold := 10;
@export var fov := 70.0
var objects: Array[RTMesh]

var spheres: PackedVector4Array

var constant_uniform: RID

func get_all_children(in_node, array := []):
	array.push_back(in_node)
	for child in in_node.get_children():
		array = get_all_children(child, array)
	return array

func _ready():
	
	await get_tree().process_frame
	playerPos = player.position
	playerRot = player.rotation
	for node in get_all_children(get_tree().get_root()):
		if node is RTMesh:
			objects.append(node)
		
	
	constant_uniform = make_constant_uniform_set()
	
	img = Image.create(screen_size.x,screen_size.y,false,Image.FORMAT_RGBAF)
	img.fill(Color(0, 0, 0, 1))
	
	var textureView := RDTextureView.new()
	var textureFormat := RDTextureFormat.new()
	textureFormat.width = screen_size.x
	textureFormat.height = screen_size.y
	textureFormat.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	textureFormat.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT 
	)
	
	texture_rd = rd.texture_create(textureFormat, textureView, [img.get_data()])
	
	texture_wrapper = Texture2DRD.new()
	texture_wrapper.texture_rd_rid = texture_rd
	
	display.texture = texture_wrapper
	

func vec3_to_vec4(vec3: Vector3, w:float = 0.0) -> Vector4:
	return Vector4(vec3.x,vec3.y,vec3.z,w)

func make_uniform_from_packed_byte_array(bytes:PackedByteArray, binding: int = 0) -> RDUniform:
	var buffer := rd.storage_buffer_create(bytes.size(), bytes)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding # this needs to match the "binding" in our shader file
	uniform.add_id(buffer)
	return uniform

func make_constant_uniform_set() -> RID:
	var constants := PackedInt32Array([max_ray_bounces,box_test_threshold])
	var vertices := PackedVector4Array()
	var indices := PackedInt32Array()
	var normals := PackedVector4Array()
	var bvhs := PackedByteArray()
	
	var total_indices := 0

	for o in objects:	

		var past_size = vertices.size()
		
		vertices.resize(vertices.size() + o.mesh_vertices.size())
		normals.resize(normals.size() + o.mesh_normals.size())
		
		for idx in o.mesh_indices:
			indices.append(idx + past_size)
			
		for i in range(len(o.mesh_vertices)):
			vertices[past_size + i] = vec3_to_vec4(o.mesh_vertices[i])
			normals[past_size + i] = vec3_to_vec4(o.mesh_normals[i])
	
		for bvh in o.bvh:
			bvhs.append_array(bvh.toPackedByteArray())


	return rd.uniform_set_create(
		[
			make_uniform_from_packed_byte_array(constants.to_byte_array(),0),
			make_uniform_from_packed_byte_array(vertices.to_byte_array(),1),
			make_uniform_from_packed_byte_array(indices.to_byte_array(),2),
			make_uniform_from_packed_byte_array(normals.to_byte_array(),3),
			make_uniform_from_packed_byte_array(bvhs,4),
		], shader, 1)
		
func make_uniform_set() -> RID:
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = 0
	uniform.add_id(texture_rd)
	
	#print(vec3_to_vec4(self.transform.basis * Vector3(-0.5,0.5,1).normalized()),)
	var cfov = cos(fov * 0.01745329252)
	var fov_multiplier = sqrt((1-height_width_ratio**2 - cfov*height_width_ratio**2 - cfov)/(cfov+1))
	var input_camera := PackedVector4Array([
		vec3_to_vec4(player.position),
		vec3_to_vec4(player.transform.basis * Vector3( 1 * fov_multiplier, 1*height_width_ratio,1).normalized()),
		vec3_to_vec4(player.transform.basis * Vector3(-1 * fov_multiplier, 1*height_width_ratio,1).normalized()),
		vec3_to_vec4(player.transform.basis * Vector3( 1 * fov_multiplier,-1*height_width_ratio,1).normalized()),
		vec3_to_vec4(player.transform.basis * Vector3(-1 * fov_multiplier,-1*height_width_ratio,1).normalized()),
		Vector4(elapsedFramesNoMovement,0,0,0)
		])
		
	var obj_array := PackedByteArray()
	
	var total_indices := 0
	var total_bvh := 0
	for obj in objects:
		var ret = obj.toPackedByteArray(total_indices,total_bvh)
		obj_array.append_array(ret[0])
		total_indices += ret[1]
		total_bvh += ret[2]
		
		
	return rd.uniform_set_create(
		[
			uniform,
			make_uniform_from_packed_byte_array(
				input_camera.to_byte_array(),1
			),
			make_uniform_from_packed_byte_array(
				obj_array,2
			)
		],
		shader, 
		0)
	

func submit_pipeline(uniform_set:RID):
	var pipeline := rd.compute_pipeline_create(shader)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
	rd.compute_list_bind_uniform_set(compute_list,constant_uniform,1)
	rd.compute_list_dispatch(compute_list, screen_size.x/32, screen_size.y/32, 1)
	rd.compute_list_end()

func vsum(v:Vector3):
	return v.x + v.y + v.z

func _process(delta):
	if vsum(player.position - playerPos) == 0 and vsum(player.rotation -playerRot) == 0:
		elapsedFramesNoMovement += 1
	else:
		playerPos = player.position
		playerRot = player.rotation
		elapsedFramesNoMovement = 1
	var us = make_uniform_set()
	submit_pipeline(us)
	rd.free_rid(us)

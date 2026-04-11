class_name RTMesh extends MeshInstance3D

class BVHBBox:
	var aabbStart: Vector4
	var aabbEnd: Vector4
	var verticesStart: int
	var verticesEnd: int
	var childLeftIdx: int
	var childRightIdx: int
	
	func instantiate(
		start: Vector4,
		end: Vector4,
		vertexStart: int,
		vertexEnd: int,
		clIdx: int,
		crIdx: int
	) -> BVHBBox:
		self.aabbStart = start
		self.aabbEnd = end
		self.verticesStart = vertexStart
		self.verticesEnd = vertexEnd
		self.childLeftIdx = clIdx
		self.childRightIdx = crIdx
		
		return self
		
	func toPackedByteArray() -> Array:
		var obj_array := PackedByteArray()
		
		obj_array.append_array(PackedVector4Array([self.aabbStart,self.aabbEnd]).to_byte_array())
		obj_array.append_array(PackedInt32Array([self.verticesStart ,self.verticesEnd,self.childLeftIdx,self.childRightIdx]).to_byte_array())
		
		return obj_array
	
@export var is_sphere: bool
@export var diffusionColor: Color
@export var emissionColor: Color
@export var emissionIntensity: float
@export var roughness: float


var bvh: Array[BVHBBox]

func vec3_to_vec4(vec3: Vector3, w:float = 0.0) -> Vector4:
	return Vector4(vec3.x,vec3.y,vec3.z,w)
	
func _ready() -> void:
	var my_aabb = self.global_transform * self.get_aabb()
	bvh = [BVHBBox.new().instantiate(vec3_to_vec4(my_aabb.position),vec3_to_vec4(my_aabb.end),0,self.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size(),0,0)]

func toPackedByteArray(total_vertex_indices:int, total_bvh_indices: int) -> Array:
	var obj_array := PackedByteArray()
	
	
	var rot := Quaternion.from_euler(self.global_rotation)
	obj_array.append_array(PackedVector4Array(
		[
			vec3_to_vec4(self.global_position),
			Vector4(rot.x,rot.y,rot.z,rot.w),
			vec3_to_vec4(self.scale),
		]).to_byte_array())
	
	var obj_indices = self.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size()
	obj_array.append_array(
		PackedInt32Array([
			total_bvh_indices,
			total_vertex_indices,
			total_vertex_indices+obj_indices,
			int(is_sphere),
		]).to_byte_array())
	
	obj_array.append_array(PackedVector4Array([
		Vector4(
			diffusionColor.r,
			diffusionColor.g,
			diffusionColor.b,
			diffusionColor.a
			),
		Vector4(
			emissionColor.r,
			emissionColor.g,
			emissionColor.b,
			emissionColor.a
			)
	]).to_byte_array())
	
	obj_array.append_array(PackedFloat32Array([emissionIntensity,roughness,0,0]).to_byte_array())
	
	return [obj_array,obj_indices, len(bvh)]
	

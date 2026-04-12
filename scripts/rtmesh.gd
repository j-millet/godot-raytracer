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
	
	func _to_string() -> String:
		return "{0}; {1} - {2}".format([self.verticesEnd-self.verticesStart,self.childLeftIdx,self.childRightIdx])
		
@export var is_sphere: bool
@export var diffusionColor: Color
@export var emissionColor: Color
@export var emissionIntensity: float
@export var roughness: float


var bvh: Array[BVHBBox]
var mesh_vertices: PackedVector3Array
var mesh_indices: PackedInt32Array
var mesh_normals: PackedVector3Array


var bvh_depth := 0
var bvh_max_leaf_tris := 0

const bvh_max_depth = 31

func vec3_to_vec4(vec3: Vector3, w:float = 0.0) -> Vector4:
	return Vector4(vec3.x,vec3.y,vec3.z,w)

func get_aabb_from_mesh(indicesStart:int, indicesEnd: int) -> Array[Vector3]:
	var minVals = Vector3(INF,INF,INF)
	var maxVals = -1*Vector3(INF,INF,INF)
	for i in range(indicesStart, indicesEnd):
		minVals.x = min(minVals.x, mesh_vertices[mesh_indices[i]].x)
		maxVals.x = max(maxVals.x, mesh_vertices[mesh_indices[i]].x)
		
		minVals.y = min(minVals.y, mesh_vertices[mesh_indices[i]].y)
		maxVals.y = max(maxVals.y, mesh_vertices[mesh_indices[i]].y)
		
		minVals.z = min(minVals.z, mesh_vertices[mesh_indices[i]].z)
		maxVals.z = max(maxVals.z, mesh_vertices[mesh_indices[i]].z)
	return [minVals,maxVals]

func split_bbox(bbox:BVHBBox) -> Array[BVHBBox]:
	if bbox.verticesEnd - bbox.verticesStart <= 8*3:
		return [bbox]
	var extent = bbox.aabbEnd - bbox.aabbStart
	var axis = 0
	if extent.y > extent.x:
		axis = 1
	if extent.z > extent[axis]:
		axis = 2
	
	var split = (bbox.aabbStart[axis] + bbox.aabbEnd[axis]) / 2.0
	
	var less_than_ptr = bbox.verticesStart
	for i in range(bbox.verticesStart,bbox.verticesEnd,3):
		var tri_center = (mesh_vertices[mesh_indices[i]] + mesh_vertices[mesh_indices[i+1]] + mesh_vertices[mesh_indices[i+2]])/3
		if tri_center[axis] >= split:
			continue
		
		for j in range(3):
			var tempI = mesh_indices[less_than_ptr+j]
			mesh_indices[less_than_ptr+j] = mesh_indices[i+j] 
			mesh_indices[i+j] = tempI
		
		less_than_ptr += 3
	if less_than_ptr == bbox.verticesStart ||  less_than_ptr == bbox.verticesEnd:
		return [bbox]
		
	var result: Array[BVHBBox] = []
	var aabb = get_aabb_from_mesh(bbox.verticesStart,less_than_ptr)
	result.append(BVHBBox.new().instantiate(vec3_to_vec4(aabb[0]),vec3_to_vec4(aabb[1]),bbox.verticesStart,less_than_ptr,0,0))
	
	aabb = get_aabb_from_mesh(less_than_ptr,bbox.verticesEnd)
	result.append(BVHBBox.new().instantiate(vec3_to_vec4(aabb[0]),vec3_to_vec4(aabb[1]),less_than_ptr,bbox.verticesEnd,0,0))
	return result

func make_bbox_cube(bbox:BVHBBox):
	var center = ( bbox.aabbStart +  bbox.aabbEnd) / 2.0
	var size = ( bbox.aabbEnd -  bbox.aabbStart).abs()
	var cube = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	mesh.size = Vector3(size.x,size.y,size.z)
	cube.mesh = mesh
	cube.position = Vector3(center.x,center.y,center.z)
	var wire_mat = StandardMaterial3D.new()
	wire_mat.flags_unshaded = true
	wire_mat.albedo_color = Color(1, 0, 0,0.1)
	wire_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire_mat.flags_transparent = true
	cube.set_surface_override_material(0, wire_mat)
	add_child(cube)
	
func make_bvh(idx: int,depth=0):
	bvh_depth = max(bvh_depth,depth)
	if depth > bvh_max_depth:
		return
	var root = bvh[idx]
	var split:Array[BVHBBox] = split_bbox(root)
	
	if len(split) == 1:
		make_bbox_cube(root)
		bvh_max_leaf_tris = max(bvh_max_leaf_tris, (root.verticesEnd-root.verticesStart)/3)
		return
	#if depth > -1:
		
	
	var len_curr = len(bvh)
	root.childLeftIdx = len_curr
	root.childRightIdx = len_curr+1
	bvh.append_array(split)
	bvh[idx] = root
	make_bvh(len_curr,depth+1)
	make_bvh(len_curr+1,depth+1)
	
func _ready() -> void:
	var arrays = self.mesh.surface_get_arrays(0)
	self.mesh_vertices = arrays[Mesh.ARRAY_VERTEX]
	self.mesh_indices = arrays[Mesh.ARRAY_INDEX]
	self.mesh_normals = arrays[Mesh.ARRAY_NORMAL]
	
	var aabb_result = get_aabb_from_mesh(0,mesh_indices.size())
	self.bvh = [(BVHBBox
		.new()
		.instantiate(
			vec3_to_vec4(aabb_result[0]),
			vec3_to_vec4(aabb_result[1]),
			0,
			self.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size(),
			0,0))]
	make_bvh(0)
	print("{0}; {1}; {2}; {3}".format([len(bvh),bvh_depth,bvh_max_leaf_tris,mesh_vertices.size()]))

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
	

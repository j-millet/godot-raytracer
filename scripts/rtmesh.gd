class_name RTMesh extends MeshInstance3D



class Triangle:
	var v0: Vector3
	var e1: Vector3
	var e2: Vector3
	var n0: Vector3
	var n1: Vector3
	var n2: Vector3
	
	func instantiate(
		v0: Vector3,
		e1: Vector3,
		e2: Vector3,
		n0: Vector3,
		n1: Vector3,
		n2: Vector3,
	) -> Triangle:
		self.v0 = v0
		self.e1 = e1
		self.e2 = e2
		self.n0 = n0
		self.n1 = n1
		self.n2 = n2
		return self
		
	func vec3_to_vec4(vec3: Vector3, w:float = 0.0) -> Vector4:
		return Vector4(vec3.x,vec3.y,vec3.z,w)
	
	func toPackedVector4Array() -> PackedVector4Array:
		return PackedVector4Array([
			self.vec3_to_vec4(self.v0),
			self.vec3_to_vec4(self.e1),
			self.vec3_to_vec4(self.e2),
			self.vec3_to_vec4(self.n0),
			self.vec3_to_vec4(self.n1),
			self.vec3_to_vec4(self.n2),
		])
	
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
var triangles: Array[Triangle]


var bvh_depth := 0
var bvh_max_leaf_tris := 0

const bvh_max_depth = 31
const bvh_num_bins = 16

func vec3_to_vec4(vec3: Vector3, w:float = 0.0) -> Vector4:
	return Vector4(vec3.x,vec3.y,vec3.z,w)

func get_aabb_from_mesh(indicesStart:int, indicesEnd: int) -> Array[Vector3]:
	var minVals = Vector3(INF, INF, INF)
	var maxVals = -1 * Vector3(INF, INF, INF)

	for i in range(indicesStart, indicesEnd):
		var tri = triangles[i]
		var verts = [tri.v0, tri.v0 + tri.e1, tri.v0 + tri.e2]
		for v in verts:
			minVals = Vector3(
				min(minVals.x, v.x),
				min(minVals.y, v.y),
				min(minVals.z, v.z),
			)
			maxVals = Vector3(
				max(maxVals.x, v.x),
				max(maxVals.y, v.y),
				max(maxVals.z, v.z),
			)

	return [minVals, maxVals]

func get_aabb_area(aabbStart: Vector3, aabbEnd: Vector3) -> float:
	var dx = abs(aabbEnd.x - aabbStart.x)
	var dy = abs(aabbEnd.y - aabbStart.y)
	var dz = abs(aabbEnd.z - aabbStart.z)

	return 2.0 * (dx * dy + dy * dz + dz * dx)
	
func get_split_with_cost_at(bbox: BVHBBox, axis: int, proportion: float):
	#var extent = bbox.aabbEnd - bbox.aabbStart
	var split = bbox.aabbEnd[axis] * proportion + bbox.aabbStart[axis] * (1-proportion)
	
	var less_than_ptr = bbox.verticesStart
	var countLeft = 0
	var countRight = 0
	for i in range(bbox.verticesStart,bbox.verticesEnd):
		var tri = self.triangles[i]
		var tri_center = tri.v0 + (tri.e1 + tri.e2) / 3.0
		if tri_center[axis] >= split:
			countRight	+= 1
			continue
		
		countLeft += 1
		var temp = triangles[less_than_ptr]
		triangles[less_than_ptr] = triangles[i]
		triangles[i] = temp
		
		less_than_ptr += 1
		
	if less_than_ptr == bbox.verticesStart ||  less_than_ptr == bbox.verticesEnd:
		return [[bbox],INF]

	var aabbLeft = get_aabb_from_mesh(bbox.verticesStart,less_than_ptr)
	var aabbRight = get_aabb_from_mesh(less_than_ptr,bbox.verticesEnd)
	
	var result: Array[BVHBBox] = []
	result.append(BVHBBox.new().instantiate(vec3_to_vec4(aabbLeft[0]),vec3_to_vec4(aabbLeft[1]),bbox.verticesStart,less_than_ptr,0,0))
	result.append(BVHBBox.new().instantiate(vec3_to_vec4(aabbRight[0]),vec3_to_vec4(aabbRight[1]),less_than_ptr,bbox.verticesEnd,0,0))
	
	var cost = get_aabb_area(aabbLeft[0],aabbLeft[1])*countLeft + get_aabb_area(aabbRight[0],aabbRight[1])*countRight
	return [result,cost]

func split_bbox(bbox:BVHBBox) -> Array[BVHBBox]:
	if bbox.verticesEnd - bbox.verticesStart <= 8:
		return [bbox]
		
	var best_axis: int = 0
	var best_proportion: float = 0.0
	var best_split_cost:float = INF
	var best_split_result: Array[BVHBBox] = [bbox]
	for axis in range(3):
		for split in range(1,bvh_num_bins):
			var proportion = float(split)/float(bvh_num_bins)
			var split_result = get_split_with_cost_at(bbox,axis,proportion)
			if split_result[1] < best_split_cost:
				best_axis = axis
				best_proportion = proportion
				best_split_cost = split_result[1]
				best_split_result = split_result[0]
				
	return get_split_with_cost_at(bbox,best_axis,best_proportion)[0]

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
		bvh_max_leaf_tris = max(bvh_max_leaf_tris, root.verticesEnd-root.verticesStart)
		return
	#if depth > -1:
		
	
	var len_curr = len(bvh)
	root.childLeftIdx = len_curr
	root.childRightIdx = len_curr+1
	bvh.append_array(split)
	bvh[idx] = root
	make_bvh(len_curr,depth+1)
	make_bvh(len_curr+1,depth+1)
	
func get_tris():
	"""Get PackedVector4Array of triangles: v0,e1,e2,n012"""
	for i in range(0,len(self.mesh_indices),3):
		var i1 = self.mesh_indices[i]
		var i2 = self.mesh_indices[i+1]
		var i3 = self.mesh_indices[i+2]
		self.triangles.append(
			Triangle.new().instantiate(
				self.mesh_vertices[i1],
				self.mesh_vertices[i2] - self.mesh_vertices[i1],
				self.mesh_vertices[i3] - self.mesh_vertices[i1],
				self.mesh_normals[i1],
				self.mesh_normals[i2],
				self.mesh_normals[i3],
			)
		)
	
func _ready() -> void:
	var arrays = self.mesh.surface_get_arrays(0)
	self.mesh_vertices = arrays[Mesh.ARRAY_VERTEX]
	self.mesh_indices = arrays[Mesh.ARRAY_INDEX]
	self.mesh_normals = arrays[Mesh.ARRAY_NORMAL]
	self.get_tris()
	
	var aabb_result = get_aabb_from_mesh(0,triangles.size())
	print(get_aabb_area(aabb_result[0],aabb_result[1]))
	self.bvh = [(BVHBBox
		.new()
		.instantiate(
			vec3_to_vec4(aabb_result[0]),
			vec3_to_vec4(aabb_result[1]),
			0,
			self.triangles.size(),
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
	
	var obj_indices = self.triangles.size()
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
	

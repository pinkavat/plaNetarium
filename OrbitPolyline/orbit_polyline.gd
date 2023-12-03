extends MeshInstance3D
class_name OrbitPolyline

## 3D drawing faculty for orbital lookahead cache.
##
## TODO doc


var size : int	# TODO
var space_scale : float # TODO 

# Mesh buffers.
var _surface_arrays := []
var _positions : PackedVector3Array
var _next_positions : PackedFloat32Array
var _colours : PackedColorArray
var _uvs : PackedVector2Array

# Shader expects two tris per line segment; here are specs.
const UV_LOOKUP = [Vector2(0, -1), Vector2(1,1), Vector2(0, 1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 1)]
const VERTICES_PER_POINT : int = len(UV_LOOKUP)


# Colour of the line
var color := Color.WHITE

# TODO: linkage of cache size/cache resizing concerns.
func _init(space_scale_ : float):
	space_scale = space_scale_

# TODO: separated init and setup due to dependency clashing in plaNetarium core
func setup(size_ : int):
	size = size_
	
	# Resize backing buffers
	_positions.resize(size * VERTICES_PER_POINT)
	_next_positions.resize(size * VERTICES_PER_POINT * 3) # Bear in mind
	_colours.resize(size * VERTICES_PER_POINT)
	_uvs.resize(size * VERTICES_PER_POINT)
	
	# Initialize Shader material (TODO repath)
	var material := ShaderMaterial.new()
	material.shader = load("res://OrbitPolyline/Polyline3DTestShader.gdshader")
	set_material_override(material)
	material.set_shader_parameter("line_width", 8.0) # TODO adj. param
	
	# Initially create mesh
	mesh = ArrayMesh.new()
	_surface_arrays.resize(Mesh.ARRAY_MAX)
	_surface_arrays[Mesh.ARRAY_VERTEX] = _positions
	_surface_arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_surface_arrays[Mesh.ARRAY_COLOR] = _colours
	_surface_arrays[Mesh.ARRAY_CUSTOM0] = _next_positions
	
	# Set up UVs
	for i in size:
		for j in VERTICES_PER_POINT:
			var vertex_index = i * VERTICES_PER_POINT + j
			_uvs[vertex_index] = UV_LOOKUP[j]
			_colours[vertex_index].a = 0.0


# Regenerate the mesh from the updated buffers
func _recommit_mesh():	
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays, [],{}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)


# Callback linked to the gravitee's buffer by signal
# TODO spec
func add_point(index : int, data):
	
	#var time = data[0] # TODO this is TIME QUANTUM of the gravitee
	var pos : Vector3 = data.get_rel_pos().vec3() * space_scale
	
	var prior_index := (index + (size - 1)) % size
	
	var backing_index := index * VERTICES_PER_POINT
	var backing_prior_index := prior_index * VERTICES_PER_POINT
	var backing_prior_in_next := backing_prior_index *  3
	
	var bi = 0
	for i in VERTICES_PER_POINT:
		
		# Add the current point and make it transparent
		_positions[backing_index + i] = pos
		_colours[backing_index + i].a = 0.0
		
		# Point the prior at the current and make it untransparent
		_next_positions[backing_prior_in_next + bi] = pos.x
		_next_positions[backing_prior_in_next + bi + 1] = pos.y
		_next_positions[backing_prior_in_next + bi + 2] = pos.z
		bi += 3
		
		_colours[backing_prior_index + i] = color
	
	_recommit_mesh()

# TODO: kludge fix for the zero-setting bug; needs a clean.
func change_point(index : int, data):
	
	#var time = data[0] # TODO this is TIME QUANTUM of the gravitee
	var pos : Vector3 = data.get_rel_pos().vec3() * space_scale
	
	var backing_index := index * VERTICES_PER_POINT
	
	for i in VERTICES_PER_POINT:
		
		# Set the current point
		_positions[backing_index + i] = pos
	
	_recommit_mesh()


# TODO doc
func invalidate(index : int, _throwaway):
	
	var backing_index := index * VERTICES_PER_POINT
	
	for i in VERTICES_PER_POINT:
		_colours[backing_index + i].a = 0.0
	
	_recommit_mesh()

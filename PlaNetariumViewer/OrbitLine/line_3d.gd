extends MeshInstance3D
class_name Line3Dc

## Draws a list of 3D points as a connected line, using an absurd shader.
##
## The 'c' stands for 'custom' and it's to avoid hiding a potential future
## engine class.


# ========== CONTROL ==========

var line_width : float:
	set(value):
		line_width = value
		material_override.set_shader_parameter("line_width", line_width)


## Redraw function: call once done changing things to push the mesh.
func redraw():
	mesh.clear_surfaces()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _surface_arrays, [],{}, Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)


## Resize function: call to erase the line and set the backing buffers to a
## new size.
func resize(new_size : int):
	_size = new_size
	
	# Resize backing buffers
	_positions.resize(new_size * _VERTICES_PER_POINT)
	_next_positions.resize(new_size * _VERTICES_PER_POINT * 3) # Bear in mind
	_colours.resize(new_size * _VERTICES_PER_POINT)
	_uvs.resize(new_size * _VERTICES_PER_POINT)
	
	# Set up UVs and clear colour
	for i in new_size:
		for j in _VERTICES_PER_POINT:
			var vertex_index = i * _VERTICES_PER_POINT + j
			_uvs[vertex_index] = _UV_LOOKUP[j]
			_colours[vertex_index].a = 0.0


## Set the position of the point at the given index. 
func change_point_position(index : int, pos : Vector3):
	
	var prior_index := (index + (_size - 1)) % _size

	var backing_index := index * _VERTICES_PER_POINT
	var backing_prior_index := prior_index * _VERTICES_PER_POINT
	var backing_prior_in_next := backing_prior_index *  3

	var bi = 0
	for i in _VERTICES_PER_POINT:

		# Set the current point
		_positions[backing_index + i] = pos

		# Point the prior point at the current point
		_next_positions[backing_prior_in_next + bi] = pos.x
		_next_positions[backing_prior_in_next + bi + 1] = pos.y
		_next_positions[backing_prior_in_next + bi + 2] = pos.z
		bi += 3


## Set the colour of the point at the given index.
func change_point_color(index : int, color : Color):
	var backing_index := index * _VERTICES_PER_POINT
	for i in _VERTICES_PER_POINT:
		_colours[backing_index + i] = color


func _init(initial_size : int):
	
	# Initially create mesh
	mesh = ArrayMesh.new()
	_surface_arrays.resize(Mesh.ARRAY_MAX)
	_surface_arrays[Mesh.ARRAY_VERTEX] = _positions
	_surface_arrays[Mesh.ARRAY_TEX_UV] = _uvs
	_surface_arrays[Mesh.ARRAY_COLOR] = _colours
	_surface_arrays[Mesh.ARRAY_CUSTOM0] = _next_positions
	
	# Load the shader
	var material := ShaderMaterial.new()
	material.shader = preload("./line_3d.gdshader")
	material_override = material
	
	# Resize to set up backing arrays
	resize(initial_size)


# ========== ENTRAILS ==========

# Number of points in the line
var _size : int

# Mesh buffers.
var _surface_arrays := []
var _positions : PackedVector3Array
var _next_positions : PackedFloat32Array
var _colours : PackedColorArray
var _uvs : PackedVector2Array

# Shader expects two tris per line segment; here are specs.
const _UV_LOOKUP = [Vector2(0, -1), Vector2(1,1), Vector2(0, 1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 1)]
const _VERTICES_PER_POINT : int = len(_UV_LOOKUP)

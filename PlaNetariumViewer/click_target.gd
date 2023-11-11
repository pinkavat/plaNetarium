extends Node2D
class_name ClickTarget

## 2D child of a 3D object; will place itself at the object's position,
## display a circle of a fixed size, and field clicks thereon.

## If a 3D sphere centered on the parent object of this radius has a greater apparent
## radius on screen than the clicktarget's radius, the clicktarget will hide itself.
var parent_apparent_min_rad = 0.00127 # TODO

## Displayed circle radius, in pixels
var radius : float = 20.0

## Displayed circle colour
var color : Color = Color.AQUA

## Emitted on click
signal clicked

# Must follow camera gimbal in tree order!
func _process(_delta):
	
	# Get camera
	var camera = get_viewport().get_camera_3d()
	
	# Get parent's 3D position
	var parent_pos = get_parent().global_position
	# Transform to match 3D parent
	global_position = camera.unproject_position(parent_pos)
	
	# Check to see if the object we're representing is larger on screen than we are
	var test_pos = to_local(camera.unproject_position(parent_pos + Vector3(0, parent_apparent_min_rad, 0)))
	
	# Hide and disable clicks if behind camera, target sphere is large enough, or parent is hidden
	if camera.is_position_behind(parent_pos) or test_pos.length_squared() > (radius * radius) or not get_parent().is_visible_in_tree():
		hide()
	else:
		show()



# Draw an empty circle around the target point
func _draw():
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, color, 4.0)


# Field mouse clicks
func _input(event):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if visible and to_local(event.position).length_squared() < (radius * radius):
			get_viewport().set_input_as_handled()
			
			clicked.emit()

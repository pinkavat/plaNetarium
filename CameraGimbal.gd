extends Node3D

# Camera Gimbal control script
#
# Manages drag-to-pan, zooming, and click-to-refocus.
#
# TODO: Right now, It's click and drag to pan, and two-finger scroll to zoom.
# Godot has a 'magnify gesture' for a trackpad pinch but for some weird reason it
# can't detect direction.
#
# TODO zoom smoothing, dynamic zoom limits


#var rotate_speed_gesture := 0.01 
var rotate_speed_mouse := 0.002
var zoom_speed_gesture := 1.0
var move_lerp_factor := 6.0

# TODO: dynamic (or a least parametrized as exposed!)
var min_zoom := 1.5
var max_zoom := 100.0


@onready var camera = $Camera3D

var grabbed := false
var azimuth := 0.0
var altitude := 0.0
var target_node = null


# Position interpolation to target
func _process(delta):
	var target_pos = target_node.global_position if target_node else Vector3.ZERO
	global_position = global_position.lerp(target_pos, delta * move_lerp_factor)


# Helper for multiple kinds of camera rotation
# (from when two-finger swipe was pan, not zoom)
func rotate_camera(delta : Vector2, speed : float):
	# Update rotors
	azimuth += -delta.x * speed
	altitude = clampf(altitude - delta.y * speed, -PI/2., PI/2.)
	
	# Rotate camera
	transform.basis = Basis()
	rotate_y(azimuth)
	rotate_object_local(Vector3(1, 0, 0), altitude)


# Click/drag handling
func _unhandled_input(event):
	if grabbed:
		
		# Mouse up
		if event is InputEventMouseButton and not event.is_pressed():
			get_viewport().set_input_as_handled()
			grabbed = false
		
		# Mouse drag
		elif event is InputEventMouseMotion:
			get_viewport().set_input_as_handled()
			
			rotate_camera(event.relative, rotate_speed_mouse)
			
	else:
		
		# Two-finger swipe
		if event is InputEventPanGesture:
			get_viewport().set_input_as_handled()
			
			#rotate_camera(event.delta, rotate_speed_gesture)
			camera.position.z = clampf(camera.position.z + event.delta.y * zoom_speed_gesture, min_zoom, max_zoom)
		
		
		# Clicking, possibly drag start
		elif event is InputEventMouseButton and event.is_pressed():
			if event.button_index == MOUSE_BUTTON_LEFT:
				get_viewport().set_input_as_handled()
				
				# Fire a ray to see if camera is to move
				
				var params := PhysicsRayQueryParameters3D.new()
				params.from = camera.project_ray_origin(event.position)
				params.to = params.from + camera.project_ray_normal(event.position) * camera.far
				params.collide_with_bodies = false
				params.collide_with_areas = true
				params.collision_mask = 0x1
				var ray_result = get_world_3d().direct_space_state.intersect_ray(params)
				
				if ray_result and ray_result["collider"].is_in_group("camera_targetable"):
					# We hit a targetable node; retarget the camera
					target_node = ray_result["collider"]
				else:
					# Ray didn't hit anything, so it's a grab-to-move.
					grabbed = true

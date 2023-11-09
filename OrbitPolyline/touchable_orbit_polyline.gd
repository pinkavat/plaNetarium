extends OrbitPolyline
class_name TouchableOrbitPolyline

## OrbitPolyline extended with mouse-contact checking.

## Get the cache index of the closest point to the mouse.
func get_closest_point_to_mouse() -> int:
	# TODO: disambiguate between two very close points.
	
	var closest : int = 0
	var closest_dist_squared = INF
	
	var camera := get_viewport().get_camera_3d()
	var mouse_pos := get_viewport().get_mouse_position()
	
	for i in range(0, len(_positions), VERTICES_PER_POINT):
		var point := _positions[i]
		var screen_point := camera.unproject_position(point)	# TODO SCALE INSENSITIVE!!!
		
		var dist_squared := screen_point.distance_squared_to(mouse_pos)
		if dist_squared < closest_dist_squared:
			closest_dist_squared = dist_squared
			@warning_ignore("integer_division")
			closest = i / VERTICES_PER_POINT
	
	return closest

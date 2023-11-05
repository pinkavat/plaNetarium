extends Node2D

## Unprojects the parent Node3D's position and makes it the self's position.

func _physics_process(_delta):
	global_position = get_viewport().get_camera_3d().unproject_position(get_parent().global_position)

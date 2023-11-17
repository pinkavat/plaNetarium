extends Node3D
class_name ScreenSizeDetector

## Emits signals when a specified spatial length, measured from self position along
## the camera's X-axis, is above or below a certain 2D length on screen.

# TODO: Doesn't WORK! PROJECTION SUFFERS FROM THE BEHIND_THE_BACK PROBLEM!

# TODO hysteresis
# TODO relative to screen dimension rather than absolute pixel, especially for upper range!

## Emitted when the parent's screen size enters the range between min_area and max_area
signal entered_bounds

## Emitted when the parent's screen size exits the range between min_area and max_area
signal exited_bounds

## The 3D spatial distance to be evaluated.
var measuring_dist : float = 1.0

## lower bound, in 2D units.
var min_len : float = 0.0

## upper bound, in 2D units.
var max_len : float = INF



var _in_bounds := true

func _process(_delta):
	
	var camera := get_viewport().get_camera_3d()
	var measure_terminus := global_position + (camera.transform.basis.x * measuring_dist)
	var screen_line := camera.unproject_position(measure_terminus) - camera.unproject_position(global_position)
	var screen_len := screen_line.length()
	
	if screen_len < min_len or screen_len > max_len:
		# Left range
		if _in_bounds:
			exited_bounds.emit()
			_in_bounds = false
	else:
		# Entered range
		if not _in_bounds:
			entered_bounds.emit()
			_in_bounds = true

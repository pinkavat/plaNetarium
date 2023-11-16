extends Line3Dc
class_name OrbitLineConstant

## Orbit-visualizing line for fixed bodies (Gravitors).

# TODO: THESE ARE THE SAME REFERENCE AXES SHARED BY 
# UNIVERSAL KEPLER, and have the SAME DEPENDENCY PROBLEM.
const _REFERENCE_AXIS = Vector3(1, 0, 0)
const _REFERENCE_NORMAL = Vector3(0, 1, 0)

## Initialize with elliptical parameters.
func _init(
	scale_factor : float, 
	semimajor_axis : float, 
	eccentricity : float, 
	arg_periapsis : float,
	inclination : float,
	ascending_long : float,
	color := Color.WHITE,
	):
	
	# Sample the ellipse 
	# TODO: there's better ways, of course!
	const ELLIPSE_SEGMENTS = 256
	var thetaStep = TAU / ELLIPSE_SEGMENTS
	var theta = TAU
	
	super._init(ELLIPSE_SEGMENTS + 1)

	for i in (ELLIPSE_SEGMENTS + 1):
		var radius = scale_factor * (semimajor_axis * (1 - eccentricity * eccentricity)) / (1 + eccentricity * cos(theta))
		change_point_position(i, Vector3(radius * cos(theta), 0, radius * sin(theta)))
		change_point_color(i, color)
		theta -= thetaStep
	
	# Draw the line
	redraw()
	
	# Do the necessary rotations to align argperi, inclin, asc.long
	# (cribbed from Universal Kepler: if it's wrong, that's wrong too)
	rotate(_REFERENCE_NORMAL, ascending_long)
	var ascending_axis := _REFERENCE_AXIS.rotated(_REFERENCE_NORMAL, ascending_long)
	rotate(ascending_axis, inclination)
	var inclined_normal := _REFERENCE_NORMAL.rotated(ascending_axis, inclination)
	rotate(inclined_normal, arg_periapsis)

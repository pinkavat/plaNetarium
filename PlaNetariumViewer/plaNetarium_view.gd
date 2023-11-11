extends Node3D
class_name PlaNetariumView

## PlaNetarium User Interface, handling visualization and input.
##
## TODO doc. Unlike the PlaNetarium core, do reach into this as much as needful.

## The PlaNetarium this view is of; must be set by the using context before
## any other calls are made.
var planetarium : PlaNetarium


## Since too-large values might lead to weirdness with clipping planes, etc. We
## shrink everything coming out of the PlaNetarium by this factor.
var space_scale := 1e-10


## Attempted time advance per second, as applied in process loop.
var time_scale := 128000.0 # seconds, arbitrarily (TODO INITVAL AND SETTING)


## Whether the view is attempting to advance simulation time or not.
var running := true


## How many microseconds each process call is allowed to use.
var tick_budget_usec : int = 8000



## Simulation time. READ ONLY -- PlaNetarium isn't designed to run backwards, nor
## to jump at random into the future.
var sim_time := 0.0


# Each object in a plaNetarium is visualized by a collection of Nodes. The
# mapping from ID name to these subtrees is stored here.
# Philosophy: None of the subtrees care about the plaNetarium, space_scale, etc.
var _views := {}


# Camera Gimbal: owns the camera, fields camera controls, and handles camera moves.
# NOTE: to ensure proper projection (2D overlays like orbits and clicktargets)
# camera must precede all these in tree order (i.e. its process call runs first).
@onready var _camera_gimbal := get_node("CameraGimbal")


# ========== VIEWING PLANETARIUM OBJECTS ==========

# TODO: property setters for viewing the root body.

## Removes the Nodal subtree associated with this object, if it exists.
func unload(body_name : StringName):
	var subtree = _views.get(body_name)
	if subtree:
		_views.erase(body_name)
		subtree.queue_free()


## Instances and adds a subtree showing the indicated large body, if it exists.
func load_large_body(body_name : StringName, properties : Dictionary):
	if body_name in _views:
		unload(body_name)
	
	# Instantiate and set up a large body viewer
	var large_body_view = preload("res://PlaNetariumViewer/LargeBodyView/large_body_view.tscn").instantiate()
	
	# TODO temp planet mesh sizing
	large_body_view.get_node("TempPlanetMesh").scale *= space_scale * 6_371_000.0 * 2.0
	
	# TODO: colour etc. ('properties' dict lookup?)
	var new_mat := StandardMaterial3D.new()
	new_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	new_mat.albedo_color = properties.get('color', Color.MAGENTA)
	large_body_view.get_node("TempPlanetMesh").set_surface_override_material(0, new_mat)
	
	# TODO: orbit
	
	var click_target = large_body_view.get_node("ClickTarget")
	click_target.color = properties.get('color', Color.MAGENTA)
	click_target.clicked.connect(_camera_gimbal._start_move_towards.bind(large_body_view))
	
	_views[body_name] = large_body_view
	add_child(large_body_view)


enum ViewType {
	UNPREDICTABLE,	## No orbit shown.
	PREDICTABLE,	## Orbit shown, but no maneuvers.
	CONTROLLABLE,	## Orbit and maneuvers shown.
	CONTROLLED,		## Orbit and maneuvers shown and editable; touching orbit will show lookahead.
}

## Instances and adds a subtree showing the indicated small body, if it exists;
## bells and whistles are specified by the view_type.
func load_small_body(body_name : StringName, view_type: ViewType, properties : Dictionary):
	if body_name in _views:
		unload(body_name)
	
	var new_view
	match view_type:
		
		ViewType.UNPREDICTABLE:
			# Setup for unpredictable view
			new_view = preload("res://PlaNetariumViewer/SmallBodyView/unpredictable_small_body_view.tscn").instantiate()
	
	# Setup shared by all views
	var click_target = new_view.get_node("ClickTarget")
	click_target.color = properties.get('color', Color.MAGENTA)
	click_target.clicked.connect(_camera_gimbal._start_move_towards.bind(new_view))
	
	_views[body_name] = new_view
	add_child(new_view)



# ========== TIME-PROCESS LOOP ==========

## TODO: physics process?
## TODO: camera to physics, too? Maybe that's the holdup?
func _process(delta):
	
	var tick_start_time := Time.get_ticks_usec()
	var current_tick_budget := tick_budget_usec
	
	if running:
		
		# Attempt to advance plaNetarium sim time
		var state = planetarium.move_to_time(sim_time)
		
		if state:
			# Tick succeeded. Update view to reflect:
			
			for view_name in _views:
				var pos = state.get_pos_of(view_name) * space_scale
				var view = _views[view_name]
				
				# TODO
				view.global_position = pos
				#if view.has_method(""):
				#	pass
			
			# Advance time.
			sim_time += delta * time_scale
	
	# With remaining time in tick, advance plaNetarium caches, etc.
	current_tick_budget -= Time.get_ticks_usec() - tick_start_time
	planetarium.do_background_work(current_tick_budget)






# =============== TODO for conversion ==================


#func _process(delta):

#
#	# Reticle placement
#	#var mouse_closest_index := orbit_line.get_closest_point_to_mouse()
#	#var closest_state = sponch.long_cache._backing[mouse_closest_index]
#	#$Reticle.global_position = (closest_state.get_pos().vec3()) * space_scale


#
#	$CameraGimbal/Camera3D.position.z = $CameraGimbal.min_zoom * 10.0
#	$CameraGimbal._start_move_towards($TestTarget2)
#	$CameraGimbal.move_amount = 0.0
#
#	orbit_line = TouchableOrbitPolyline.new(sponch.long_cache.length(), space_scale)
#	sponch.long_cache.added_item.connect(orbit_line.add_point)
#	sponch.long_cache.changed_item.connect(orbit_line.change_point)
#	sponch.long_cache.invalidate.connect(orbit_line.invalidate)
#	add_child(orbit_line)

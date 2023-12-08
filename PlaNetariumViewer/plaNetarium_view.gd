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
var tick_budget_usec : int = 16000 # 8000



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
	
	# Set up constant orbit line
	var semimajor_axis = planetarium.get_property_of(body_name, &"semimajor_axis")
	var orbit_line = OrbitLineConstant.new(
		space_scale, 
		semimajor_axis,
		planetarium.get_property_of(body_name, &"eccentricity"),
		planetarium.get_property_of(body_name, &"arg_periapsis"),
		planetarium.get_property_of(body_name, &"inclination"),
		planetarium.get_property_of(body_name, &"ascending_long"),
		properties.get('color', Color.MAGENTA))
	
	# Add a screen-size detector to it, based on its semimajor axis length
	# TODO DOESNT: WORK SEE CODE
	#var screen_size_detector = ScreenSizeDetector.new()
	#screen_size_detector.measuring_dist = semimajor_axis * space_scale
	#screen_size_detector.min_len = 10.0
	#screen_size_detector.max_len = 8000.0
	#screen_size_detector.entered_bounds.connect(orbit_line.show)
	#screen_size_detector.exited_bounds.connect(orbit_line.hide)
	#orbit_line.add_child(screen_size_detector)
	
	# Parent the orbitline to the parent gravitor, or the view if the parent is root.
	var parent_view = _views.get(planetarium.get_property_of(body_name, &"parent_name"), self)
	parent_view.add_child(orbit_line)
	
	# TODO: REPLACE CLICKTARGET'S RESPONSE TO SCREEN SIZE DETECTOR WITH SELF?
	var click_target = large_body_view.get_node("ClickTarget")
	click_target.color = properties.get('color', Color.MAGENTA)
	click_target.clicked.connect(_camera_gimbal._start_move_towards.bind(large_body_view))
	#screen_size_detector.entered_bounds.connect(click_target.force_show)
	#screen_size_detector.exited_bounds.connect(click_target.force_hide)
	
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
		
		ViewType.PREDICTABLE:
			# Setup for predictable view
			
			# TODO This is TERRIBLE!
			new_view = preload("res://PlaNetariumViewer/SmallBodyView/unpredictable_small_body_view.tscn").instantiate()
			var orbit_line = OrbitPolyline.new(space_scale)
			orbit_line.color = properties.get('color', Color.MAGENTA)
			planetarium.connect_orbit_line(body_name, orbit_line)
			
			# TODO add set and regen funcs for ref frame
			planetarium.change_gravitee_reference_gravitor(body_name, &"earth")
			_views[&"earth"].add_child(orbit_line)
			
			# TODO hmmm. Transform concerns!
			#var temp_recenterer = Node.new()
			#temp_recenterer.add_child(orbit_line)
			#new_view.add_child(temp_recenterer)
	
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
				var pos = state.get_pos_of(view_name)
				var view = _views[view_name]
				
				# TODO CRASH DETECTION -- crashed 'tees return null sans explanation
				if pos:
					view.global_position = pos * space_scale
				#if view.has_method("set_pos"):
				#	view.set_pos(pos)
			
			# Advance time.
			sim_time += delta * time_scale
	
	# With remaining time in tick, advance plaNetarium caches, etc.
	current_tick_budget -= Time.get_ticks_usec() - tick_start_time
	planetarium.do_background_work(current_tick_budget)

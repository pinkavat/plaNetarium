extends Node3D

# Test driver script

var sponch : Gravitee
var orbit_line : TouchableOrbitPolyline

var sim_time := 0.0

var time_scale := 128000.0
var space_scale := 1e-10
var running := true

var valid_tick_count = 0


var planetarium : PlaNetarium



var tick_budget_usec : int = 8000

# TODO: physics process?
# TODO: camera to physics, too? Maybe that's the holdup?
func _process(delta):
	
	var tick_start_time := Time.get_ticks_usec()
	var current_tick_budget := tick_budget_usec
	
	# Reticle placement
	#var mouse_closest_index := orbit_line.get_closest_point_to_mouse()
	#var closest_state = sponch.long_cache._backing[mouse_closest_index]
	#$Reticle.global_position = (closest_state.get_pos().vec3()) * space_scale
	
	
	# Time speed controls
	if Input.is_action_just_pressed("ui_right"):
		time_scale *= 2.0
	elif Input.is_action_just_pressed("ui_left"):
		time_scale /= 2.0
	if Input.is_action_just_pressed("ui_accept"):
		running = not running
	
	
	if running:
		
		var state = planetarium.move_to_time(sim_time)
		
		if state:
			
			# Tick succeeded. Move sprites:
			$TestTarget2.global_position = state.get_pos_of(&"earth") * space_scale
			$TestTarget3.global_position = state.get_pos_of(&"sponch") * space_scale
			
			# Advance time.
			sim_time += delta * time_scale
		
	
	current_tick_budget -= Time.get_ticks_usec() - tick_start_time
	planetarium.do_background_work(current_tick_budget)
	

#		#$Label.text = $Label.text + "\ncache tail: "+str(sponch.long_cache.get_at(sponch.long_cache_tail).qtime * sponch.time_quantum)+"\n("+str(sponch.long_cache_tail)+"/"+str(sponch.long_cache.length())+")"+"\ncurrent time: "+ str(sim_time) + " (" +str(sim_time/60.0/60.0)+ " hours)" +"\nvalid ticks: " + str(valid_tick_count)# + "\ntimestep: " + str(sponch.timestep)
#		$Label.text = $Label.text + "\ngravitor cache hit/miss rate: " + str(float(cache_hits)/float(cache_misses))
#		$Label.text = $Label.text + "\ncurrent primary: " + str(sponch.long_cache.get_at(0).primary.name)

func _ready():
	
	# NEW CODE
	
	planetarium = PlaNetarium.new(&"sol", 1.327e20)
	planetarium.add_large_body(&"earth", &"sol", {"mu" : 3.986e14}, {"periapsis":147.1e9, "apoapsis":152.1e9})
	
	
	
	# OLD CODE
	
	# Two BELOW LINES NEEDED TO SUBSTANTIATE LUNAR ORBIT ONLY
	var sol = Gravitor.make_root_gravitor("sol", 1.327e20)
	var earth = sol.add_child_from_apsides("earth", 3.986e14, 147.1e9, 152.1e9)
	$TestTarget2.scale *= space_scale * 6_371_000.0 * 2.0
	$TestTarget3.scale = $TestTarget2.scale
	
	$CameraGimbal/Camera3D.position.z = $CameraGimbal.min_zoom * 10.0
	$CameraGimbal._start_move_towards($TestTarget2)
	$CameraGimbal.move_amount = 0.0
	
	$TestTarget2/ClickTarget.clicked.connect($CameraGimbal._start_move_towards.bind($TestTarget2))
	$TestTarget3/ClickTarget2.clicked.connect($CameraGimbal._start_move_towards.bind($TestTarget3))
	
	var lunar_orbit := UniversalKepler.initial_conditions_from_apsides(3.986e14, 363e6, 405e6)
	var lunar_global = [lunar_orbit[0].add(earth.pos_0), lunar_orbit[1].add(earth.vel_0)]
	
	#sponch = Gravitee.new(lunar_global[0], lunar_global[1], 0.0, cached_gravitor_query)
	sponch = planetarium.temp_add_small_body(&"sponch", lunar_global[0], lunar_global[1], 0.0)
	
	orbit_line = TouchableOrbitPolyline.new(sponch.long_cache.length(), space_scale)
	sponch.long_cache.added_item.connect(orbit_line.add_point)
	sponch.long_cache.changed_item.connect(orbit_line.change_point)
	sponch.long_cache.invalidate.connect(orbit_line.invalidate)
	add_child(orbit_line)

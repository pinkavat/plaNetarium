extends Node3D

# Test driver script

var sponch : Gravitee

var sol : Gravitor
var earth : Gravitor
var moon : Gravitor

var sim_time := 0.0

var time_scale := 128000.0
var space_scale := 1e-10

var valid_tick_count = 0

func _process(delta):
	
	# Time speed controls
	if Input.is_action_just_pressed("ui_right"):
		time_scale *= 2.0
	elif Input.is_action_just_pressed("ui_left"):
		time_scale /= 2.0
	
#	sim_time += time_scale * delta
#	temp_move_planets(sim_time)
	
	var state = sponch.state_at_time(sim_time, true)
	if is_instance_of(state, TYPE_INT):
		if state == 1:
			sponch.propagate_cache()
			$Label.text = "propagating cache up to " + str(sponch.cache.get_at(sponch.tail)[0] * sponch.time_quantum)
			
			$SponchPrediction.global_position = (sponch.cache.get_at(sponch.tail)[1].vec3()) * space_scale
		elif state == 2:
			sponch.cache.shift_left(sponch.cache.length() - 1) # TODO: hadn't thought of this
			sponch.tail = 0
			$Label.text = "forcemoving cache head TODO"
		else:
			#print("no data avail, advancing time anyway")
			$Label.text = "no data available, advancing anyway"
			sim_time += time_scale * delta

			# Move fixed planets
			temp_move_planets(sim_time)
	else:
		#print(sim_time, ": ", state)
		$Label.text = "valid tick"
		valid_tick_count += 1
		sim_time += delta * time_scale
		# Move fixed planets
		temp_move_planets(sim_time)
		# Move sponch
		$TestTarget3.global_position = state[0].vec3() * space_scale
		
	$Label.text = $Label.text + "\ncurrent time: "+ str(sim_time) +"\nvalid ticks: " + str(valid_tick_count) + "\ntimestep: " + str(sponch.timestep)


func temp_move_planets(time):
		
		# Get state
		var state := sol.all_states_at_time(time)
		
		$TestTarget2.global_position = (state["earth"][0].vec3()) * space_scale
		#$TestTarget3.global_position = (state["moon"][0].vec3()) * space_scale

func _ready():
	sol = Gravitor.make_root_gravitor("sol", 1.327e20)
	earth = sol.add_child_from_apsides("earth", 3.986e14, 147.1e9, 152.1e9)
	#moon = earth.add_child_from_apsides("moon", 4.905e12, 363e6, 405e6)
	
	var lunar_orbit := UniversalKepler.initial_conditions_from_apsides(3.986e14, 363e6, 405e6)
	var lunar_global = [lunar_orbit[0].add(earth.pos_0), lunar_orbit[1].add(earth.vel_0)]
	
	#sponch = Gravitee.new(moon.pos_0.add(earth.pos_0), moon.vel_0.add(earth.vel_0), 0.0, sol.all_states_at_time)
	#sponch = Gravitee.new(DoubleVector3.new(147461658472.428, 0, -535222439.85885), DoubleVector3.new(-156.266628704918, 0, -31359.6968614126), 0.0, sol.all_states_at_time)
	sponch = Gravitee.new(lunar_global[0], lunar_global[1], 0.0, sol.all_states_at_time)
	#sponch = Gravitee.new(earth.pos_0.add(DoubleVector3.new(6628000, 0, 0)), earth.vel_0.add(DoubleVector3.new(0, 7750, 0)), 0.0, sol.all_states_at_time)
	#print(sol.all_states_at_time(0.0))

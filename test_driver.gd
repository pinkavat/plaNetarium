extends Node3D

# Test driver script

var sponch

var planetarium : PlaNetarium
var view : PlaNetariumView

func _ready():
	
	# TODO stringname-name testing
	
	planetarium = PlaNetarium.new(&"sol", 1.327e20)
	
	view = $PlaNetariumView
	view.planetarium = planetarium
	
	planetarium.add_large_body(&"earth", &"sol", {"mu" : 3.986e14}, {"periapsis":147.1e9, "apoapsis":152.1e9})
	view.load_large_body(&"earth", {"color" : Color.LIME_GREEN})
	
	# Baroque way of adding a small body at a position!
	# TODO: WHEN THESE GO, REMOVE THE ASSOCIATED CODE IN GRAVITOR!
	var sol = Gravitor.make_root_gravitor("sol", 1.327e20)
	var earth = sol.add_child_from_apsides("earth", 3.986e14, 147.1e9, 152.1e9)
	var lunar_orbit := UniversalKepler.initial_conditions_from_apsides(3.986e14, 363e6, 405e6)
	var lunar_global = [lunar_orbit[0].add(earth.pos_0), lunar_orbit[1].add(earth.vel_0)]
	sponch = planetarium.temp_add_small_body(&"sponch", lunar_global[0], lunar_global[1], 0.0)
	view.load_small_body(&"sponch", PlaNetariumView.ViewType.UNPREDICTABLE, {"color" : Color.GRAY})

#		#$Label.text = $Label.text + "\ncache tail: "+str(sponch.long_cache.get_at(sponch.long_cache_tail).qtime * sponch.time_quantum)+"\n("+str(sponch.long_cache_tail)+"/"+str(sponch.long_cache.length())+")"+"\ncurrent time: "+ str(sim_time) + " (" +str(sim_time/60.0/60.0)+ " hours)" +"\nvalid ticks: " + str(valid_tick_count)# + "\ntimestep: " + str(sponch.timestep)
#		$Label.text = $Label.text + "\ngravitor cache hit/miss rate: " + str(float(cache_hits)/float(cache_misses))
#		$Label.text = $Label.text + "\ncurrent primary: " + str(sponch.long_cache.get_at(0).primary.name)


func _process(_delta):
	# Temporary time speed controls
	if Input.is_action_just_pressed("ui_right"):
		view.time_scale *= 2.0
	elif Input.is_action_just_pressed("ui_left"):
		view.time_scale /= 2.0
	if Input.is_action_just_pressed("ui_accept"):
		view.running = not view.running

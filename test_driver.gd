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
	view.load_large_body(&"earth", {"color" : Color.SKY_BLUE})
	
	planetarium.add_large_body(&"venus", &"sol", {"mu" : 3.249e14}, {"periapsis":107.5e9, "apoapsis":108.9e9})
	view.load_large_body(&"venus", {"color" : Color.LIME_GREEN})
	
	planetarium.add_large_body(&"mars", &"sol", {"mu" : 4.283e13}, {"periapsis":206.7e9, "apoapsis":249.2e9})
	view.load_large_body(&"mars", {"color" : Color.ORANGE_RED})
	
	# Baroque way of adding a small body at a position!
	# TODO: WHEN THESE GO, REMOVE THE ASSOCIATED CODE IN GRAVITOR!
	var sol = Gravitor.make_root_gravitor("sol", 1.327e20)
	var earth = sol.add_child_from_apsides("earth", 3.986e14, 147.1e9, 152.1e9)
	var lunar_orbit := UniversalKepler.initial_conditions_from_apsides(3.986e14, 363e6, 405e6)
	var lunar_global = [lunar_orbit[0].add(earth.pos_0), lunar_orbit[1].add(earth.vel_0)]
	planetarium.temp_add_small_body(&"sponch", lunar_global[0].vec3(), lunar_global[1].vec3(), 0.0)
	view.load_small_body(&"sponch", PlaNetariumView.ViewType.PREDICTABLE, {"color" : Color.GRAY})
	
	planetarium.temp_add_small_body(&"quell", lunar_orbit[0].mul(2.0).add(earth.pos_0).vec3(), lunar_global[1].vec3(), 0.0)
	view.load_small_body(&"quell", PlaNetariumView.ViewType.PREDICTABLE, {"color" : Color.ORANGE})
	
	planetarium.temp_add_small_body(&"quert", lunar_orbit[0].mul(8.0).add(earth.pos_0).vec3(), lunar_global[1].vec3(), 0.0)
	view.load_small_body(&"quert", PlaNetariumView.ViewType.PREDICTABLE, {"color" : Color.YELLOW})


func _process(_delta):
	# Temporary time speed controls
	if Input.is_action_just_pressed("ui_right"):
		view.time_scale *= 2.0
	elif Input.is_action_just_pressed("ui_left"):
		view.time_scale /= 2.0
	if Input.is_action_just_pressed("ui_accept"):
		view.running = not view.running
	
	
	$Label.text = "cache hit/miss ratio: " + str(planetarium.get_cache_ratio())

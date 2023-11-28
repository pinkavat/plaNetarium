extends Node3D

# Test driver script

var sponch

var planetarium : PlaNetarium
var view : PlaNetariumView


func _ready():
	
	# TODO stringname-name testing.
	
	planetarium = PlaNetarium.new(&"sol", 1.327e20)
	
	view = $PlaNetariumView
	view.planetarium = planetarium
	
	planetarium.add_gravitor(&"earth", &"sol", {"mu" : 3.986e14}, {"periapsis":147.1e9, "apoapsis":152.1e9})
	view.load_large_body(&"earth", {"color" : Color.SKY_BLUE})

	planetarium.add_gravitor(&"venus", &"sol", {"mu" : 3.249e14}, {"periapsis":107.5e9, "apoapsis":108.9e9})
	view.load_large_body(&"venus", {"color" : Color.LIME_GREEN})

	planetarium.add_gravitor(&"mars", &"sol", {"mu" : 4.283e13}, {"periapsis":206.7e9, "apoapsis":249.2e9})
	view.load_large_body(&"mars", {"color" : Color.ORANGE_RED})
	
	planetarium.add_gravitor(&"phobos", &"mars", {"mu" : 7.13e-3}, {"periapsis":9.234e6, "apoapsis":9.518e6})
	view.load_large_body(&"phobos", {"color" : Color.DARK_RED})
	
#	planetarium.add_gravitor(&"nibiru", &"sol", {"mu" : 1.0}, {"periapsis":110.5e9, "apoapsis":310.5e9,"arg_periapsis":PI/4.0 ,"inclination":PI/4.0, "ascending_long":PI/4.0})
#	view.load_large_body(&"nibiru", {"color" : Color.GREEN_YELLOW})
	
	var earth_orbit := UniversalKepler.initial_conditions_from_apsides(1.327e20, 147.1e9, 152.1e9)
	var lunar_orbit := UniversalKepler.initial_conditions_from_apsides(3.986e14, 363e6, 405e6)
	var lunar_global = [lunar_orbit[0].add(earth_orbit[0]), lunar_orbit[1].add(earth_orbit[1])]

	planetarium.add_gravitee(&"sponch", lunar_global[0].vec3(), lunar_global[1].vec3(), 0.0)
	view.load_small_body(&"sponch", PlaNetariumView.ViewType.PREDICTABLE, {"color" : Color.GRAY})

	planetarium.add_gravitee(&"quell", lunar_orbit[0].mul(2.0).add(earth_orbit[0]).vec3(), lunar_global[1].vec3(), 0.0)
	view.load_small_body(&"quell", PlaNetariumView.ViewType.PREDICTABLE, {"color" : Color.ORANGE})

	planetarium.add_gravitee(&"quert", lunar_orbit[0].mul(8.0).add(earth_orbit[0]).vec3(), lunar_global[1].vec3(), 0.0)
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

extends Node3D

# Test driver script

var sponch : Gravitee

var sol : Gravitor
var earth : Gravitor
var moon : Gravitor

var sim_time := 0.0


func _process(delta):
	var state = sponch.state_at_time(sim_time, true)
	if is_instance_of(state, TYPE_INT):
		if state:
			sponch.propagate_cache()
			print("propagating cache")
		else:
			print("no data avail, advancing time anyway")
			sim_time += delta * 20.0
	else:
		print(sim_time, ": ", state)
		sim_time += delta * 20.0


func _ready():
	sol = Gravitor.make_root_gravitor(1.327e20)
	earth = sol.add_child_from_apsides(3.986e14, 147.1e9, 152.1e9)
	moon = earth.add_child_from_apsides(4.905e12, 363e6, 405e6)
	
	sponch = Gravitee.new(moon.pos_0.add(earth.pos_0), moon.vel_0.add(earth.vel_0), 0.0, sol.all_states_at_time)
	
	print(sol.all_states_at_time(0.0))

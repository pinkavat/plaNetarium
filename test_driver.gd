extends Node3D

# Test driver script

var sponch : Gravitee
var sim_time := 0.0

func _ready():
	sponch = Gravitee.new(DoubleVector3.ZERO(), DoubleVector3.ZERO(), 0.0)

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

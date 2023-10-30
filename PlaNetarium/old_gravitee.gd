class_name OldGravitee
extends RefCounted

## Body subject to the influence of gravity sources (a satellite).
##
## TODO: document
## All state propagations are stored in a canonical 'lookahead cache'; sub-sim-quantum
## time increments are achieved by propagating forward from the nearest cache element.
##
## TODO: retire. Proof-of-concept proved.


## In order to allow caching of Gravitor state, Gravitees compute their states at
## integer time quanta, to increase the chance that two Gravitees will share times.
## This value specifies the amount of simulation time per time quantum
var time_quantum : float = 0.1	# TODO TODO: spec and setting (in init or not?)

## TODO doc
var timestep : int = 1

## The lookahead cache; stores [time quantum, pos doublevec, vel doublevec] "tuples".
var cache : RingBuffer

## The cache's tail: index of last valid state in the cache.
var tail : int

## Callable callback that returns the name->[pos, vel, mu] dictionary from the Gravitors,
## for use in the propagator.
var state_fetch : Callable


## Initialize a new Gravitee, with an initial Cartesian state (position and velocity) at
## the given time. Provide the callable that furnishes the gravitor state array.
## Optionally specify the initial lookahead cache size (positive integer).
func _init(pos_0 : DoubleVector3, vel_0 : DoubleVector3, time_0 : float, 
	state_fetch_ : Callable, cache_size : int = 256
	) -> void:
	
	state_fetch = state_fetch_
	
	# Work out the initial time quantum
	var time_quant_0 = int(time_0 / time_quantum) + 1
	var time_to_mark = (float(time_quant_0) * time_quantum) - time_0
	
	# Propagate initial state forward to said quantum
	var prop_state = _propagate(pos_0, vel_0, time_0, time_to_mark)
	
	# Set up the lookahead cache with initial state data
	cache = RingBuffer.new(cache_size)
	cache.set_at(0, [time_quant_0, prop_state[0], prop_state[1]])
	tail = 0


## Get the Cartesian state of this gravitee at the given exact time.
## Will return the following:
##	- if the requested time PRECEDES any cached time, returns integer 0
##		("we don't know and can't ever")
##	- if the requested time is BEYOND the last cached time and there are still empty 
##		positions in the cache, returns integer 1
##		("we don't know, but might in a few ticks")
##	- if the requested time is BEYOND the last cached time and there aren't any empty
##		positions in the cache, returns integer 2
##		("request is beyond visible horizon")
##	- if the requested time falls WITHIN the cache, returns [pos doublevec, vel doublevec]
##
## if update_cache is true, the cache head will move to the time quantum preceding the request.
## (that is, set it to true for simulation time-advance, and false for prediction)
func state_at_time(time : float, update_cache : bool = false):
	
	var time_as_quant = int(time / time_quantum)
	
	if time_as_quant < cache.get_at(0)[0]:
		# Precedes cache
		return 0
	
	elif time_as_quant >= cache.get_at(tail)[0]:
		# Succeeds cache (exact edge case discarded)
		if tail == (cache.length() - 1):
			# No more cache space
			return 2
		else:
			# More cache space; requested time may possibly be computed
			return 1
	
	else:
		
		# Perform binary search on the cache to find the closest smaller quantum
		var bsearch_left = 0
		var bsearch_right = tail
		
		while(bsearch_left < bsearch_right):
			@warning_ignore("integer_division") # Dear me, Godot, dear me.
			var mid = int((bsearch_right - bsearch_left) / 2) + bsearch_left + 1
			if time_as_quant >= cache.get_at(mid)[0]:
				bsearch_left = mid
			else:
				bsearch_right = mid - 1
		
		var preceding_index = bsearch_left
		
		var preceding_state = cache.get_at(preceding_index)
		var preceding_time = float(preceding_state[0] * time_quantum)
		var step_time = time - preceding_time
		
		# If we're an updating step, move the cache head
		if update_cache:
			cache.shift_left(preceding_index)
			tail -= preceding_index
		
		# Subpropagate forward from the cached time to get the actual desired state
		return _propagate(preceding_state[1], preceding_state[2], preceding_time, step_time)


## Attempts to fill the next empty slot in the cache by propagating once
## forward from the previous slot. Does nothing if the cache is full.
func propagate_cache() -> void:
	if tail < (cache.length() - 1):
		var last_state = cache.get_at(tail)
		var last_time = float(last_state[0]) * time_quantum
		
		var new_state
		# TODO: PEFRL may be better than Forest-Ruth, but can't double the timestep within the
		# same epsilon (TODO why not) -- we may need more GRANULAR control over timestep size
		# TODO: Also don't forget that timesteps ought to be TIME TRACKS -- i.e. time VALUES
		# are shared wherever possible so that gravitor caching can hit better.
		
		while true: # TODO safetyvalve; rehash the logic -- proof of concept good!
			var half_state = _propagate(last_state[1], last_state[2], last_time, float(timestep) * time_quantum)
			half_state = _propagate(half_state[0], half_state[1], last_time + float(timestep) * time_quantum, float(timestep) * time_quantum)
			var full_state = _propagate(last_state[1], last_state[2], last_time, float(timestep * 2) * time_quantum)
		
			if half_state[0].equals_approx(full_state[0], 2.0): # TODO hyperparam
				timestep *= 2
				new_state = half_state
				break
			else:
				timestep /= 2
		
		tail += 1
		cache.set_at(tail, [last_state[0] + timestep, new_state[0], new_state[1]])



# ========== PROPAGATOR ==========

func _propagate(pos : DoubleVector3, vel : DoubleVector3, time : float, dt : float) -> Array:
	# Fetch the gravitor states
	# TODO time consideration: 'before' or 'after'? Or is it OK as-is?
	# TODO or even time-slice (that'd be abysmal performance-wise!)
	var gravitors = state_fetch.call(time)
	
	# Run the Integrator and return result
	#return _ruth_forest_integrator(pos, vel, dt, _gravity_force_get.bind(gravitors))
	return _PEFRL_integrator(pos, vel, dt, _gravity_force_get.bind(gravitors))


# Helper for getting gravity force from position; bind the gravitors before passing this
# as a callable to the integrator
# TODO can we shrink/speed this...?
func _gravity_force_get(pos : DoubleVector3, gravitors : Dictionary) -> DoubleVector3:
	var acc = DoubleVector3.ZERO() # TODO nomenclt.
	for gravitor in gravitors.values():
		var rel_pos := pos.sub(gravitor[0]) # 0 : gravitor position
		var rel_pos_dot := rel_pos.dot(rel_pos)
		var grav_mag : float = gravitor[2] / rel_pos_dot # 2: gravitor mu
				
		var acc_normal = rel_pos.div(-sqrt(rel_pos_dot))
				
		acc = acc.add(acc_normal.mul(grav_mag))
	return acc


# TODO doc
# Old Forest-ruth integrator (probably not the most efficient implementation, either)
#
# Forest, E.; Ruth, Ronald D. (1990). "Fourth-order symplectic integration". 
# Physica D. 43: 105–117. doi:10.1016/0167-2789(90)90019-L.
func _ruth_forest_integrator(cur_pos : DoubleVector3, cur_vel : DoubleVector3, dt : float, gravity_getter : Callable) -> Array:
	const cbrt_two := pow(2.0, 1.0 / 3.0)
	const _c_0 := 1.0 / (2.0 * (2.0 - cbrt_two))
	const _c_1 := (1.0 - cbrt_two) / (2.0 * (2.0 - cbrt_two))
	const _d_0 := 1.0 / (2.0 - cbrt_two)
	const c := [_c_0, _c_1, _c_1, _c_0]
	const d := [_d_0, -cbrt_two / (2.0 - cbrt_two), _d_0, 0.0]
	
	var pos := cur_pos.clone()
	var vel := cur_vel.clone()
	for i in range(4):
		pos = pos.add(vel.mul(c[i] * dt))
		
		var acc = gravity_getter.call(pos)
		
		vel = vel.add(acc.mul(d[i] * dt))
		
	return [pos, vel]


# Position-Extended-Forest-Ruth-Like, nominally 340x more accurate than Forest-Ruth, at the cost
# of one more force sample.
#
# Omelyan, Igor & Mryglod, Ihor & Reinhard, Folk. (2002). "Optimized Forest-Ruth- and Suzuki-like algorithms for integration of 
# motion in many-body systems". Computer Physics Communications. 146. 188. 10.1016/S0010-4655(02)00451-4. 
func _PEFRL_integrator(cur_pos : DoubleVector3, cur_vel : DoubleVector3, dt : float, gravity_getter : Callable) -> Array:
	const xi = 0.1786178958448091
	const lambda = -0.2123418310626054
	const chi = -0.06626458266981849
	
	var pos := cur_pos.clone() # TODO we really need to get this discrepancy sorted, esp. vis. handbacks etc.
	var vel := cur_vel.clone() # Honestly the whole thing should be data-oriented C++
	
	# Begin PEFRL steps (loop unrolled -- why not, eh?)
	pos = pos.add(vel.mul(xi * dt))
	
	var acc = gravity_getter.call(pos) # "Update forces" pass
	vel = vel.add(acc.mul(dt * (0.5 - lambda)))
	pos = pos.add(vel.mul(dt * chi))
	
	acc = gravity_getter.call(pos)
	vel = vel.add(acc.mul(dt * lambda))
	pos = pos.add(vel.mul(dt * (1.0 - 2.0 * (chi + xi))))
	
	acc = gravity_getter.call(pos)
	vel = vel.add(acc.mul(dt * lambda))
	pos = pos.add(vel.mul(dt * chi))
	
	acc = gravity_getter.call(pos)
	vel = vel.add(acc.mul(dt * (0.5 - lambda)))
	pos = pos.add(vel.mul(dt * xi))
	
	return [pos, vel]

class_name Gravitee
extends RefCounted

## Body subject to the influence of gravity sources (a satellite).
##
## TODO: document
## All state propagations are stored in a canonical 'lookahead cache'; sub-sim-quantum
## time increments are achieved by propagating forward from the nearest cache element.


## In order to allow caching of Gravitor state, Gravitees compute their states at
## integer time quanta, to increase the chance that two Gravitees will share times.
## This value specifies the amount of simulation time per time quantum
var time_quantum : float = 0.1	# TODO TODO: spec and setting (in init or not?)


## The lookahead cache; stores [time quantum, pos doublevec, vel doublevec] "tuples".
var cache : RingBuffer


## The cache's tail: index of last valid state in the cache.
var tail : int


## Initialize a new Gravitee, with an initial Cartesian state (position and velocity) at
## the given time. Optionally specify the initial lookahead cache size (positive integer).
func _init(pos_0 : DoubleVector3, vel_0 : DoubleVector3, time_0 : float, cache_size : int = 256) -> void:
	
	# Work out the initial time quantum
	var time_quant_0 = int(time_0 / time_quantum) + 1
	var time_to_mark = (float(time_quant_0) * time_quantum) - time_0
	
	# Propagate initial state forward to said quantum
	var prop_state = _propagation_wrapper(pos_0, vel_0, time_to_mark)
	
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
			var mid = int((bsearch_right - bsearch_left) / 2) + bsearch_left + 1
			if time_as_quant >= cache.get_at(mid)[0]:
				bsearch_left = mid
			else:
				bsearch_right = mid - 1
		
		var preceding_index = bsearch_left
		
		var preceding_state = cache.get_at(preceding_index)
		var step_time = time - float(preceding_state[0] * time_quantum)
		
		# If we're an updating step, move the cache head
		if update_cache:
			cache.shift_left(preceding_index)
			tail -= preceding_index
		
		# Subpropagate forward from the cached time to get the actual desired state
		return _propagation_wrapper(preceding_state[1], preceding_state[2], step_time)


## Attempts to fill the next empty slot in the cache by propagating once
## forward from the previous slot. Does nothing if the cache is full.
func propagate_cache() -> void:
	if tail < (cache.length() - 1):
		var last_state = cache.get_at(tail)
		
		var timestep := 1 # TODO timestep
		
		var new_state = _propagation_wrapper(last_state[1], last_state[2], float(timestep) * time_quantum)
		tail += 1
		cache.set_at(tail, [last_state[0] + timestep, new_state[0], new_state[1]])


# TODO
func _propagation_wrapper(pos : DoubleVector3, vel : DoubleVector3, dt : float) -> Array:
	return [pos, vel]

extends RefCounted
class_name Gravitee

## Body subject to the influence of gravity sources (a satellite).
##
## TODO: document



## In order to allow caching of Gravitor state, Gravitees compute their states at
## integer time quanta, to increase the chance that two Gravitees will share times.
## This value specifies the amount of simulation time per time quantum
static var time_quantum : float = 0.01	# TODO TODO: spec and setting (in init or not?)


## The long cache; stores integration states of State type (inner class below).
## Called 'long' because unlike previous PlaNetarium prototypes, this one isn't
## exhaustive over local valid timesteps. We throw out and recompute intermediate
## steps to show a larger timespan. Note that the long cache is still CANONICAL.
var long_cache : RingBuffer

## The long cache's tail: index of last valid state in the long cache.
var long_cache_tail : int


## Callback that returns the name->[pos, vel, mu] dictionary from the Gravitors,
## given a time.
var state_fetch : Callable


## In order for the smart propagator (below) to function, it needs to know what
## constitutes acceptable error. This criterion compares two states that are meant
## to be identical; timesteps will be as large as possible while satisfying it.
var states_approx_equal : Callable = func(d_half : State, full : State) -> bool:
	return d_half.get_pos().equals_approx(full.get_pos(), 1.0) # position within a meter



## Initialize a new Gravitee, with an initial Cartesian state (position and velocity) at
## the given time. Provide the callable that furnishes the gravitor state array.
## Optionally specify the initial long cache size (positive integer).
func _init(pos_0 : DoubleVector3, vel_0 : DoubleVector3, time_0 : float, 
	state_fetch_ : Callable, long_cache_size : int = 256
	) -> void:
	
	state_fetch = state_fetch_
	
	# Work out the initial time quantum
	# Unlike previous prototypes, we don't propagate forward to establish exact
	# state. Rather, we trust to the granularity of the system and simply pretend
	# that the state is the same at the first time quantum.
	var time_quant_0 = int(time_0 / time_quantum)
	
	# Set up the long cache with initial state data
	long_cache = RingBuffer.new(long_cache_size)
	long_cache.set_at(0, State.new(time_quant_0, pos_0, vel_0))
	long_cache_tail = 0


## Get the Cartesian state of this gravitee at the given time (TODO quantum or no?)
## Will return the following:
##	- if the requested time PRECEDES any cached time, returns integer 0
##		("we don't know and can't ever")
##	- if the requested time is BEYOND the last cached time, returns integer 1
##		("we don't know, but might eventually")
##	- if the requested time falls WITHIN the cache, returns [pos doublevec, vel doublevec]
##
## if update_cache is true, the cache head will move:
##	- if the request fell within the cache, the head will move to the quantum preceding
##	- if the request was beyond the cache, the head will move to the cache tail
## (that is, set it to true for simulation time-advance, and false for prediction)
func state_at_time(time : float, update_cache : bool = false):
	
	# 1) Quantize requested time (TODO: whether we subpropagate is still an open question)
	var qt := int(time / time_quantum)
	
	# Slightly unorthodox control flow: preceding_cache_index is the long cachepoint
	# closest to and before the requested time. If there's no such point, the function
	# will return before the value is used.
	var preceding_cache_index : int
	
	# 2a) Special check: see if the time is in the first cache slot
	if long_cache_tail > 0 and (qt >= long_cache.get_at(0).qtime and qt < long_cache.get_at(1).qtime):
		preceding_cache_index = 0
	
	# 2b) Check if time is BEFORE the long cache
	elif qt < long_cache.get_at(0).qtime:
		# Precedes cache; "can't ever know"
		return 0
	
	# 2c) Check if time is AFTER the long cache
	elif qt >= long_cache.get_at(long_cache_tail).qtime:
		# Follows cache; "we may eventually know but don't yet"
		
		if long_cache_tail == (long_cache.length() - 1) and update_cache:
			# If it's an updating request and the cache is out of space, we have
			# to flush the cache, or we'll get stuck.
			long_cache.shift_left(long_cache.length() - 1)
			long_cache_tail = 0
		return 1
	
	else:
		# Requested time falls within the long cache
		
		# 3) Perform binary search on the cache to find the closest cached state
		var bsearch_left : int = 0
		var bsearch_right := long_cache_tail
		while(bsearch_left < bsearch_right):
			@warning_ignore("integer_division") # Dear me, Godot, dear me.
			var mid = int((bsearch_right - bsearch_left) / 2) + bsearch_left + 1
			if qt >= long_cache.get_at(mid).qtime:
				bsearch_left = mid
			else:
				bsearch_right = mid - 1
		preceding_cache_index = bsearch_left
	
	# 4) If we've reached this point, preceding_cache_index is validly set.
	#    smart_propagate forward from it until we hit the desired time.
	var state : State = long_cache.get_at(preceding_cache_index)
	while(state.qtime < qt):
		state = _smart_propagate(state, qt)
		# TODO safety valve?
	
	# 5) State now contains the state at qt.
	# 	 if this is an updating operation, we need to move the cache head and
	#	 overwrite it.
	if update_cache:
		long_cache.shift_left(preceding_cache_index)
		long_cache_tail -= preceding_cache_index
		long_cache.set_at(0, state)
	
	# 6) Reformat and return
	return [state.get_pos(), state.get_vel()]


# TODO doc
# TODO: coarseness metric
# TODO: don't forget gravitor sweepline idea (it'd be higher up)
func advance_cache() -> void:
	if long_cache_tail < (long_cache.length() - 1):
		var tail_state = long_cache.get_at(long_cache_tail)
		
		var next_state = _smart_propagate(tail_state, 9223372036854775800) # TODO Maxint
		
		if long_cache_tail <= 0 or (not long_cache.get_at(long_cache_tail).get_pos().equals_approx(long_cache.get_at(long_cache_tail - 1).get_pos(), 1_000_000_000.0)):
			# Not enough items OR coarseness criterion satisfied: add the state to the cache.
			long_cache_tail += 1
		# Otherwise coarseness criterion failed, and no need to add: replace the tail.
		long_cache.set_at(long_cache_tail, next_state)



# ========== SMART PROPAGATOR ==========

# The guts of the gravitee system center around advancing the simulation by the maximum
# viable timestep. This function does so: it advances the given state by one timestep that
# is as large as possible. The resulting state is guaranteed to be before or at the target
# time provided. 
func _smart_propagate(state : State, target_time : int) -> State:
	
	# 1) Check edge cases
	var t : int = state.qtime
	if t >= target_time:
		return state # fail silently

	# 2) Establish a valid timestep that's as fast as possible while
	#	 not overrunning the target time
	var timestep : int = max(1, t & (~(t - 1))) # TODO: maximal jump at 0?
	while t + timestep > target_time:
		@warning_ignore("integer_division")
		timestep = int(timestep / 2)

	# 3) Halve the timestep until a propagation by it is equal to two
	#	 propagations by its halves, plus or minus some error
	var full_prop = quant_PEFRL(state, timestep)
	while true:

		@warning_ignore("integer_division")
		var half_step = int(timestep / 2)
		if half_step == 0:
			break			# We can't get any more fine; settle for what we have

		var half_prop = quant_PEFRL(state, half_step)
		var double_half_prop = quant_PEFRL(half_prop, half_step)

		if states_approx_equal.call(double_half_prop, full_prop):
			break			# A full step is equal to two half steps; no need to get finer

		# Otherwise halve the timestep and loop.
		timestep = half_step
		full_prop = half_prop

	return full_prop



# ========== SYMPLECTIC INTEGRATOR ==========

# Position-Extended-Forest-Ruth-Like, nominally 340x more accurate than Forest-Ruth, at the cost
# of one more force sample.
#
# Omelyan, Igor & Mryglod, Ihor & Reinhard, Folk. (2002). "Optimized Forest-Ruth- and Suzuki-like algorithms for integration of 
# motion in many-body systems". Computer Physics Communications. 146. 188. 10.1016/S0010-4655(02)00451-4. 
func quant_PEFRL(state : State, qdt : int) -> State:
	
	# Get Gravitor state at time
	# TODO time consideration: 'before' or 'after'? Or is it OK as-is?
	# TODO or even time-slice (that'd be abysmal performance-wise!)
	var gravitors = state_fetch.call(float(state.qtime) * time_quantum)
	
	var get_acceleration = func _gravity_get(pos : DoubleVector3) -> DoubleVector3:
		var acc = DoubleVector3.ZERO() # TODO nomenclt.
		for gravitor in gravitors.values():
			var rel_pos := pos.sub(gravitor[0]) # 0 : gravitor position
			var rel_pos_dot := rel_pos.dot(rel_pos)
			var grav_mag : float = gravitor[2] / rel_pos_dot # 2: gravitor mu
			var acc_normal = rel_pos.div(-sqrt(rel_pos_dot))
			acc = acc.add(acc_normal.mul(grav_mag))
		return acc # TODO mass term...?
	
	
	# Run PEFRL core
	const xi = 0.1786178958448091
	const lambda = -0.2123418310626054
	const chi = -0.06626458266981849
	
	var pos : DoubleVector3 = state.get_pos() # yay! ameliorated the cloning!
	var vel : DoubleVector3 = state.get_vel()
	var dt := float(qdt) * time_quantum
	
	# Begin PEFRL steps
	pos = pos.add(vel.mul(xi * dt))
	
	var acc = get_acceleration.call(pos) # "Update forces" pass
	vel = vel.add(acc.mul(dt * (0.5 - lambda)))
	pos = pos.add(vel.mul(dt * chi))
	
	acc = get_acceleration.call(pos)
	vel = vel.add(acc.mul(dt * lambda))
	pos = pos.add(vel.mul(dt * (1.0 - 2.0 * (chi + xi))))
	
	acc = get_acceleration.call(pos)
	vel = vel.add(acc.mul(dt * lambda))
	pos = pos.add(vel.mul(dt * chi))
	
	acc = get_acceleration.call(pos)
	vel = vel.add(acc.mul(dt * (0.5 - lambda)))
	pos = pos.add(vel.mul(dt * xi))
	
	return State.new(state.qtime + qdt, pos, vel)



# ========== INTERNAL STATE CLASS ==========

## State class used internally (stored in the long cache, etc.)
## to alleviate memory footprint and clarify names.
class State extends RefCounted:
	
	# Simulation time quantum of this state. Directly accessible.
	var qtime : int
	
	# Position and Velocity data. Read-only, access via getters below.
	# Experimentation suggests that the memory footprint of six floats in one
	# object is half of two DoubleVec objects. Fair enough, so we unroll them:
	var _pos_x : float
	var _pos_y : float
	var _pos_z : float
	var _vel_x : float
	var _vel_y : float
	var _vel_z : float
	
	## Don't set state members. If we need to change them, just make a new state:
	func _init(qtime_ : int, pos_ : DoubleVector3, vel_ : DoubleVector3):
		qtime = qtime_
		_pos_x = pos_.x
		_pos_y = pos_.y
		_pos_z = pos_.z
		_vel_x = vel_.x
		_vel_y = vel_.y
		_vel_z = vel_.z
	
	## Position getter; Doublevec is brand-new
	func get_pos() -> DoubleVector3:
		return DoubleVector3.new(_pos_x, _pos_y, _pos_z)
	
	## Velocity getter; Doubelvec is brand-new
	func get_vel() -> DoubleVector3:
		return DoubleVector3.new(_vel_x, _vel_y, _vel_z)

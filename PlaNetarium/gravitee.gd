extends RefCounted
class_name Gravitee

## Body subject to the influence of gravity sources (a satellite).
##
## TODO: document
## TODO: linking into plaNetarium: 'primary' is set by an SOI check, which doesn't
##		 fall back to the system root and SHOULD.
## TODO: state-at-time query returns a '0' on invalid -- should it?
## TODO: refactor primary SOI detect/force pass etc.



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


## TODO EXPERIMENTAL: name of the Gravitor relative to whose frame of reference
## relative position is computed. Must be a valid key to a return from state_fetch.
var reference_gravitor_name : StringName

## TODO EXPERIMENTAL DOC
func change_reference_gravitor(new_gravitor_name : StringName):
	reference_gravitor_name = new_gravitor_name
	# TODO: Regenerate cache relative positions.
	# TODO: do this by simply resetting -- it's akin to a thruster burn, it MUST
	# be cheap!

# In order to simplify maneuvering (that is, projection of future state under
# arbitrary velocity changes), gravitees can form a doubly-linked list.
# If any gravitee in the list updates, its successors will become 'invalid'
# and have to wait until a valid parent propagates information as far as their
# start time.

## (Maneuver feature) Whether or not this gravitee's state, which depends on
## 'ancestor' gravitees' state, is up to date.
var valid := true

## (Maneuver feature) Weak reference to potential ancestor gravitee.
var predecessor_ref : WeakRef = null

## (Maneuver feature) Weak reference to potential descendent gravitee.
var successor_ref : WeakRef = null

# (Maneuver internal) We need to store start time to make this work.
var _time_0 : float


## TODO: experimental. Obtain the admissible error for a given primary.
## TODO should be a property of the gravitor, like the acceptable jump
func admissible_error_of(primary : Gravitor) -> float:
	return 100.0 # TODO


## Initialize a new Gravitee, with an initial Cartesian state (position and velocity) at
## the given time. Provide the callable that furnishes the gravitor state array.
## Optionally specify the initial long cache size (positive integer).
func _init(pos_0 : DoubleVector3, vel_0 : DoubleVector3, time_0 : float, 
	state_fetch_ : Callable, reference_gravitor_name_ : StringName, long_cache_size : int = 256
	) -> void:
	
	state_fetch = state_fetch_
	reference_gravitor_name = reference_gravitor_name_
	
	# Set up the long cache
	long_cache = RingBuffer.new(long_cache_size)
	long_cache_tail = 0
	
	# Invoke the resetter to set initial state
	reset(pos_0, vel_0, time_0)


## Reset the Gravitee to a new initial Cartesian state and time. Essentially the
## same thing as making a new Gravitee, but doesn't add memory burdens and invalidate
## references.
func reset(pos_0 : DoubleVector3, vel_0 : DoubleVector3, time_0 : float):
	
	# Work out the initial time quantum
	# Unlike previous prototypes, we don't propagate forward to establish exact
	# state. Rather, we trust to the granularity of the system and simply pretend
	# that the state is the same at the first time quantum.
	var qtime_0 = int(time_0 / time_quantum)
	
	# Perform a check to get our primary gravitor
	# TODO: this is duplicate code of the pass in PEFRL below!
	# (with all caveats thereto appertaining)
	var primary : Gravitor = null
	var min_rel := INF
	var initial_gravitor_state = state_fetch.call(float(qtime_0) * time_quantum)
	for gravitor_state in initial_gravitor_state.values():
		var rel_pos : DoubleVector3 = gravitor_state.get_pos().sub(pos_0)
		var rel_pos_dot := rel_pos.dot(rel_pos)
		if rel_pos_dot < gravitor_state.gravitor.soi_radius_squared and rel_pos_dot < min_rel:
			min_rel = rel_pos_dot
			primary = gravitor_state.gravitor
	
	# Reset the long cache
	long_cache.shift_left(long_cache_tail)
	long_cache.set_at(0, State.new(qtime_0, pos_0, vel_0, primary, sqrt(min_rel), pos_0.sub(initial_gravitor_state[reference_gravitor_name].get_pos()), 0))
	long_cache_tail = 0
	
	# === MANEUVER STUFF ===
	
	# Store the start time
	_time_0 = time_0
	
	# Invalidate children, if we have any:
	# TODO: stop if we encounter an already invalid child?
	if(successor_ref):
		var successor = successor_ref.get_ref()
		while(successor):
			successor.valid = false
			if(successor.successor_ref):
				successor = successor.successor_ref.get_ref()
			else:
				break





## Get the Cartesian state of this Gravitee at the given time (TODO quantum or no?)
## Will return the following:
##	- if the requested time PRECEDES any cached time, or the gravitee
##	  is marked INVALID, returns integer 0
##		("unknown due to external circumstances; ignore me")
##	- if the requested time is BEYOND the last cached time, returns integer 1
##		("unknown due to unpropagated cache; call advance_cache and ask again")
##	- if the requested time falls WITHIN the cache, returns a State object
##
## if update_cache is true, the cache head will move:
##	- if the request fell within the cache, the head will move to the quantum preceding
##	- if the request was beyond the cache, the head will move to the cache tail
## (that is, set it to true for simulation time-advance, and false for prediction)
func state_at_time(time : float, update_cache : bool = false):
	
	# If the gravitee is marked invalid, return immediately
	# ("we don't know and don't know if we will ever know; not our problem")
	if not valid:
		return 0
	
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
		# Precedes cache; "we can't ever know."
		return 0
	
	# 2c) Check if time is AFTER the long cache
	elif qt >= long_cache.get_at(long_cache_tail).qtime:
		# Follows cache; "we will eventually know but don't yet"
		
		if long_cache_tail == (long_cache.length() - 1) and update_cache:
			# If it's an updating request and the cache is out of space, we have
			# to flush the cache, or we'll get stuck.
			long_cache.shift_left(long_cache_tail)
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
	
	# TODO EXPERIMENTAL: Apsides are associated with cache points, so
	# propagating from a cachepoint to a cachepoint transfers apsishood.
	var apsis_flags = (state.flags & FLAG_APOAPSIS) | (state.flags & FLAG_PERIAPSIS)
	
	while(state.qtime < qt):
		state = _smart_propagate(state, qt)
		# TODO safety valve?
	
	# 5) State now contains the state at qt.
	# 	 if this is an updating operation, we need to move the cache head and
	#	 overwrite it.
	if update_cache:
		
		# TODO EXPERIMENTAL Ensure the cache retains apsis information:
		state.flags |= apsis_flags
		long_cache.shift_left(preceding_cache_index)
		long_cache_tail -= preceding_cache_index
		long_cache.set_at(0, state)
	
	return state


## Attempt to advance the orbit cache, by propagating forward from the tail and
## storing only those points that are sufficiently coarse (see below).
## Will return true if the cache is full, false otherwise.
func advance_cache() -> bool:
	if valid:
		# Gravitee is valid; propagate cache as normal.
		
		if long_cache_tail < (long_cache.length() - 1):
			var tail_state = long_cache.get_at(long_cache_tail)
			
			var next_state = _smart_propagate(tail_state, 9223372036854775800) # TODO Maxint
			
			if long_cache_tail <= 0:
				# Not enough items; add the next state.
				long_cache_tail += 1
				
			# TODO EXPERIMENTAL: Apsis detection
			elif bool(tail_state.flags & FLAG_MOVING_AWAY) != bool(next_state.flags & FLAG_MOVING_AWAY):
				# Apsis; always register it in the cache
				long_cache_tail += 1
				
				# Set relevant flag in the *tail* state (TODO: this futzes with some assumptions about
				# cache signalling, no...?)
				tail_state.flags |= (FLAG_APOAPSIS if (tail_state.flags & FLAG_MOVING_AWAY) else FLAG_PERIAPSIS)
				long_cache.set_at(long_cache_tail, tail_state)
			else:
				# Test coarseness
				# TODO: finalize/stabilize coarseness metric
				
				# Compute the acceptable jump, which is based on the orbital period AROUND the primary.
				# TODO: so we approximate it, by guesstimating an 'average orbital period of a satellite'
				# which is a fixed gravitor proprerty; if it works, set it in the gravitor initializer.
				
				var synth_semim = tail_state.primary.soi_radius / 2.0
				var estim_period = TAU * sqrt((synth_semim * synth_semim * synth_semim) / tail_state.primary.mu)
				
				estim_period = min(estim_period, 365.0 * 24.0 * 60.0 * 60.0)
				var SLICES_PER_PERIOD = 128.0
				
				@warning_ignore("narrowing_conversion")
				var admissible_jump =  (estim_period / SLICES_PER_PERIOD) / (time_quantum) # I *think* this is OK? seconds / (seconds/quantum) = quanta?
				
				#if long_cache_tail <= 0 or (not tail_state.get_pos().equals_approx(long_cache.get_at(long_cache_tail - 1).get_pos(), 1_000_000_000.0)):
				if (abs(tail_state.qtime - long_cache.get_at(long_cache_tail - 1).qtime) > admissible_jump):
					# Coarseness criterion satisfied: add the state to the cache.
					long_cache_tail += 1
			
			# Set state at tail, whether we advanced it or not.
			long_cache.set_at(long_cache_tail, next_state)
			
			return false # More work to be done
		else:
			return true # No more work to be done
		
	else:
		# Gravitee is invalid; check to see if it can be validated.
		
		# Check the parent to see if it's advanced to our start time
		assert(predecessor_ref, "Trying to advance an invalid Gravitee with no parent -- should not happen!")
		var predecessor = predecessor_ref.get_ref() # Ref assumed valid
		var predecessor_state = predecessor.state_at_time(_time_0)
		
		# TODO: there's an edge case to consider. If the state-at-time
		# query precedes the parent (say, for instance, if we boost past a maneuver
		# node, then try dragging it around) the maneuver will never validate.
		
		if is_instance_of(predecessor_state, Gravitee.State):
			# Predecessor has reached us; we are now valid and can begin advancing.
			valid = true
			reset(predecessor_state.get_pos(), predecessor_state.get_vel(), _time_0)
			pass # TODO force application
			
			return false # More work to be done
		else:
			return true # No more work to be done



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
	var timestep : int = max(1, t & (~(t - 1)))
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

		# Establish whether a full prop and two half props result in sufficiently similar state
		var admissible_error = min(admissible_error_of(double_half_prop.primary), admissible_error_of(full_prop.primary))
		if double_half_prop.get_pos().equals_approx(full_prop.get_pos(), admissible_error):
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
	
	# TODO: INSERT THIS AS PART OF ONE OF THE FORCE PASSES.
	# TODO: fallback to system root (primary never null)
	# There's a pattern implied by how both the primary and the distance are stored
	# in state object...
	var primary : Gravitor = null
	var min_rel := INF
	for gravitor_state in gravitors.values():
		var rel_pos : DoubleVector3 = gravitor_state.get_pos().sub(state.get_pos())
		var rel_pos_dot := rel_pos.dot(rel_pos)
		if rel_pos_dot < gravitor_state.gravitor.soi_radius_squared and rel_pos_dot < min_rel:
			min_rel = rel_pos_dot
			primary = gravitor_state.gravitor
	
	# TODO: other forces, externalization, etc.
	var get_acceleration = func _gravity_get(pos : DoubleVector3) -> DoubleVector3:
		var f = DoubleVector3.ZERO()
		for gravitor_state in gravitors.values():
			var rel_pos : DoubleVector3 = gravitor_state.get_pos().sub(pos)
			var rel_pos_dot := rel_pos.dot(rel_pos)
			f = f.add(rel_pos.mul(gravitor_state.gravitor.mu / (rel_pos_dot * sqrt(rel_pos_dot))))
		
		# TODO temp test accel
		#f = f.add(state.get_vel().mul(0.0000001))
		
		return f # TODO mass term...?
	
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
	
	#return State.new(state.qtime + qdt, pos, vel, primary, pos.sub(gravitors[reference_gravitor_name].get_pos()))
	
	# TODO considerations -- it's accurate-looking, more so than the 
	# other stuff, which has jaggies.
	var temp_next_g = state_fetch.call(float(state.qtime + qdt) * time_quantum)
	var next_rel = pos.sub(temp_next_g[reference_gravitor_name].get_pos())
	var moving_away = next_rel.dot(next_rel) > min_rel
	return State.new(state.qtime + qdt, pos, vel, primary, sqrt(min_rel), next_rel, (FLAG_MOVING_AWAY if moving_away else 0))



# ========== STATE CLASS ==========

# To save on memory footprint, we define bitflags outside the state class.
const FLAG_MOVING_AWAY : int = 1 << 0
const FLAG_PERIAPSIS : int = 1 << 1
const FLAG_APOAPSIS : int = 1 << 2
# TODO flags for atmospheric entry/exit, planetary impact, etc, etc.


## State class used internally (stored in the long cache, etc.)
## to alleviate memory footprint and clarify names.
class State extends RefCounted:
	
	# Simulation time quantum of this state. Directly accessible.
	var qtime : int
	
	# Gravitor exerting the strongest gravity on the Gravitee at this time.
	var primary : Gravitor
	
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
	func _init(qtime_ : int, pos_ : DoubleVector3, vel_ : DoubleVector3, primary_ : Gravitor, dist_to_primary_ : float, rel_pos_ : DoubleVector3, flags_ : int):
		qtime = qtime_
		primary = primary_
		_pos_x = pos_.x
		_pos_y = pos_.y
		_pos_z = pos_.z
		_vel_x = vel_.x
		_vel_y = vel_.y
		_vel_z = vel_.z
		_rel_pos_x = rel_pos_.x
		_rel_pos_y = rel_pos_.y
		_rel_pos_z = rel_pos_.z
		dist_to_primary = dist_to_primary_
		flags = flags_
	
	## Position getter; Doublevec is brand-new
	func get_pos() -> DoubleVector3:
		return DoubleVector3.new(_pos_x, _pos_y, _pos_z)
	
	## Velocity getter; Doubelvec is brand-new
	func get_vel() -> DoubleVector3:
		return DoubleVector3.new(_vel_x, _vel_y, _vel_z)
	
	
	# TODO EXPERIMENTAL: RELATIVE POSITION TO REFERENCE BODY
	var _rel_pos_x : float
	var _rel_pos_y : float
	var _rel_pos_z : float
	
	## TODO EXPERIMENTAL: RELATIVE POSITION TO REFERENCE BODY
	func get_rel_pos() -> DoubleVector3:
		return DoubleVector3.new(_rel_pos_x, _rel_pos_y, _rel_pos_z)
	
	
	## TODO EXPERIMENTAL: APSIS DETECTION
	var dist_to_primary : float
	
	## TODO EXPERIMENTAL: APSIS DETECTION
	## Bitflags for this state. See definitions in Gravitee.
	var flags : int

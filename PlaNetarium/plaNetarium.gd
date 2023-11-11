extends RefCounted
class_name PlaNetarium

## Simulated gravity system comprising large bodies moving along Kelperian
## tracks, emitting gravity that affects small, freefalling bodies.
##
## This file presents an opaque interface for its constituent elements
## in anticipation of a refactoring into a faster C++ extension (or similar).
## To that end, DON'T keep references to PlaNetarium-internal objects; rather,
## use their StringNames and the functions provided here.
##
## TODO: document.
## Document an example loop, with running do_background_work.


## In order to keep the caches patent, simulation is discrete. 
## TODO: setting etc.
## TODO: remove? leave to the gravitees alone?
# var time_quantum := 1.0e-2


# ========== READING FROM THE SIMULATION ==========

## Reading from the simulation is done by time-based query, which returns
## the Cartesian state for all bodies in the system, as one
## of these.
class State extends RefCounted:
	
	## Simulation time of the state, in seconds. 
	var time : float
	
	
	## Returns the position Vector3 of the named body. Will return the fallback
	## value given if the body doesn't exist or doesn't have a state at the 
	## requested time (if the time precedes or succeeds its data, say).
	func get_pos_of(name : StringName, fallback = null):
		# Check large bodies
		var large_body = _large_states.get(name, null)
		if large_body:
			return large_body.get_pos().vec3() # Gravitor.GlobalState
		var small_body = _small_states.get(name, null)
		if small_body:
			return small_body.get_pos().vec3() # Gravitee.State (TODO)
		return fallback
	
	
	## Returns the velocity Vector3 of the named body, or null, as in get_pos_of.
	func get_vel_of(name : StringName, fallback = null):
		return fallback # TODO
	
	
	## Returns the orbital parent of a large body, or the primary attractor
	## of a small body. Ditto fallback.
	func get_primary_of(name : StringName, fallback = null):
		return fallback
	
	
	# Internal stuff; don't touch from without.
	var _large_states : Dictionary # name -> Gravitor.GlobalState
	var _small_states : Dictionary # name -> Gravitee.State



## Non-updating time-query function, used to foresee what the future will hold.
func peek_at_time(time : float) -> State:
	var state = _new_state_with_large_bodies(time)
	
	# TODO TODO TODO small bodies
	# TODO optionally peek down maneuvers...?
	
	return state

# TODO: per-item peeking, right? Would be useful!


## Updating time-query function, used to advance the simulation. If any small body in the
## simulation responds to its query by saying that it hasn't reached the requested point but will,
## the function will return null. Hence, if null is received, the user waits, running do_background_work,
## until the simulation propagates to the desired point, whereupon a valid State will be returned
func move_to_time(time : float) -> State:
	var state = _new_state_with_large_bodies(time)
	
	# TODO POSSIBLE BUG: I *think* we're safe? If some gravitees are valid, and some are not
	# the valid ones will update their caches and move the heads. They'll then receive a
	# query for the same *time*. This shouldn't be a problem but might be!
	# IN FACT: we could *FREEZE* the gravitees that are 'up to date', perhaps?
	
	# Iterate over the small bodies' main courses
	for small_name in _small_bodies:
		var gravitee_state = _small_bodies[small_name].main_course.state_at_time(time, true)
		if is_instance_of(gravitee_state, TYPE_INT):
			if gravitee_state == 1:
				# waits.
				return null
			else:
				# precedes; does not report but does not prevent
				pass
		else:
			# valid; add to output
			state._small_states[small_name] = gravitee_state
	
	return state


# Auxiliary for the above, since large bodies don't care about propagation and can
# be sampled backwards and forwards
func _new_state_with_large_bodies(time : float) -> State:
	# TODO QUANTIZE?
	var state = State.new()
	state.time = time
	state._large_states = cached_gravitor_query(time)
	return state



# ========== WRITING TO THE SIMULATION ==========

## Initializer requires a name and a gravitational parameter (G * M) for the 
## root attractor of the system (as it's a fallback for various things)
func _init(root_name : StringName, root_mu : float):
	_root_name = root_name
	_large_bodies[_root_name] = Gravitor.new(root_name, DoubleVector3.ZERO(), DoubleVector3.ZERO(), root_mu)


## Add a large body (emits gravity, moves in Keplerian orbit).
## Parameters:
##	name: a unique name for the new body.
##	parent: the name of the parent body of the new body. Must exist.
##	properties: Dictionary with the following items:
##		{
##			mu [float]: Standard Gravitational Parameter of the body (G * M)
##		}
##	orbit: Dictionary with the following items:
##		{
##			MANDATORY: EITHER
##			periapsis [float]: periapsidal distance to parent
##			apoapsis [float] : apoapsidal distance to parent
##			OR
##			semimajor_axis [float] : The 'fatter radius' of the ellipse
##			eccentricity [float]   : 0 is circle, >1 is hyperbola
##
##			OPTIONAL (all default to zero)
##			arg_periapsis [float]  : the angle from the ascending node to the periapsis
##			inclination [float]    : angle between parent and child orbital planes
##			ascending_long [float] : angle from reference direction to ascending node
##			time_since_peri [float]: time elapsed between body at periapsis and orbit's reference time zero
##		}
func add_large_body(name : StringName, parent_name : StringName, parameters : Dictionary, orbit : Dictionary):
	assert(not name in _large_bodies, "Body names must be unique!")
	assert(not name in _small_bodies, "Body names must be unique!")
	assert(parent_name in _large_bodies, "Parent not found!")
	
	assert("mu" in parameters, "Must specify mu parameter")
	var child_mu = parameters["mu"]
	var parent : Gravitor = _large_bodies[parent_name]
	
	var arg_periapsis : float = orbit.get("arg_periapsis", 0.0)
	var inclination : float = orbit.get("inclination", 0.0)
	var ascending_long : float = orbit.get("ascending_long", 0.0)
	var time_since_peri : float = orbit.get("time_since_peri", 0.0)
	
	var initial_state # TODO: we're going to obsolete the old Kepple someday!
	var semimajor_axis
	if("periapsis" in orbit and "apoapsis" in orbit):
		# From apsides
		
		semimajor_axis = (orbit["periapsis"] + orbit["apoapsis"]) / 2.0
		initial_state = UniversalKepler.initial_conditions_from_apsides(
			parent.mu, orbit["periapsis"], orbit["apoapsis"], arg_periapsis, 
			inclination, ascending_long, time_since_peri
		)
		
	elif("semimajor_axis" in orbit and "eccentricity" in orbit):
		# From axis/eccentricity
		
		semimajor_axis = orbit["semimajor_axis"]
		initial_state = UniversalKepler.initial_conditions_from_kepler(
			parent.mu, orbit["semimajor_axis"], orbit["eccentricity"], arg_periapsis, 
			inclination, ascending_long, time_since_peri
		)
		
	else:
		assert(false, "Must specify either apo/periapsidal pair or axis/eccentricity pair!")
	
	var new_child := Gravitor.new(name, initial_state[0], initial_state[1], child_mu)
	# Set the new gravitor's auxiliaries (TODO: in init above...?)
	new_child.period = TAU * sqrt((semimajor_axis * semimajor_axis * semimajor_axis) / (parent.mu + child_mu))
	new_child.soi_radius = 0.9431 * semimajor_axis * pow(child_mu / parent.mu, 2.0/5.0)
	new_child.soi_radius_squared = new_child.soi_radius * new_child.soi_radius
	
	# Add the new gravitor to the gravitor tree
	parent.children.append(new_child)
	
	# Add the new gravitor to the large body list
	_large_bodies[name] = new_child


# TODO: small body creators, controllable vs uncontrollable (one 'tee or many)
## TODO: temporary small-body adder for maintain func test.
## TODO note: time-ref concerns; Double-precision not to be exposed!
func temp_add_small_body(name : StringName, pos_0 : DoubleVector3, vel_0 : DoubleVector3, time_0 : float):
	assert(not name in _large_bodies, "Body names must be unique!")
	assert(not name in _small_bodies, "Body names must be unique!")
	
	var temp_course = Gravitee.new(pos_0, vel_0, time_0, cached_gravitor_query)
	var new_body = SmallBody.new()
	new_body.main_course = temp_course
	
	_small_bodies[name] = new_body
	return temp_course # TODO only needful 'cause we haven't set up connectors yet for the orbitline


# TODO: small body force modification.


# ========== MANEUVERING ==========
# Some small bodies can generate chains of putative future courses. Managing these
# is mostly up to the user, but automatic propagation/invalidation, etc. is our responsibility.

## Adds an empty maneuver to the specified small body at the specified time. Maneuvers
## are always added to the last maneuver, or the base course if no maneuvers exist.
## Will return an opaque identifier for said maneuver (futureproofing).
func add_maneuver_to(name : StringName, time : float):
	var small_body : SmallBody = _small_bodies.get(name, null)
	assert(small_body, "Can only add a maneuver to a small body!")
	
	var new_maneuver := Maneuver.new()
	new_maneuver.start_time = time
	new_maneuver.gravitee = Gravitee.new(DoubleVector3.ZERO(), DoubleVector3.ZERO(), time, cached_gravitor_query)
	small_body.maneuvers.append(new_maneuver)


## Updates the given maneuver. Provide a maneuver reference returned by add_maneuver_to above.
func update_maneuver_of(name : StringName, maneuver : Variant): # TODO force rep.
	var small_body : SmallBody = _small_bodies.get(name, null)
	assert(small_body, "Can only change a maneuver of a small body!")
	
	# Find the maneuver in the maneuver list (simpler than linked-list, at minor cost)
	var index = small_body.maneuvers.find(maneuver)
	assert(index >= 0, "Couldn't find maneuver!")
	
	# Update the force data of the maneuver
	# and possibly its start time too
	# TODO
	
	# Invalidate the maneuver and all its successors
	# TODO: emit maneuver-invalidation signal
	for i in range(index, len(small_body.maneuvers)):
		small_body.maneuvers[i].valid = false


## Deletes the given maneuver. Provide a maneuver reference returned by add_maneuver_to above.
func delete_maneuver_of(name : StringName, maneuver : Variant):
	var small_body : SmallBody = _small_bodies.get(name, null)
	assert(small_body, "Can only delete a maneuver from a small body!")
	
	# Find the maneuver in the maneuver list (simpler than linked-list, at minor cost)
	var index = small_body.maneuvers.find(maneuver)
	assert(index >= 0, "Couldn't find maneuver!")
	
	# Invalidate all successors
	for i in range(index, len(small_body.maneuvers)):
		small_body.maneuvers[i].valid = false
	
	# Delete self
	small_body.maneuvers.remove_at(index)



# ========== RUNNING THE SIMULATION ==========

## Invoke with a time budget in milliseconds. The simulation will do its background
## cache-advancing, etcetera, within said budget, and return what it didn't use.
func do_background_work(time_budget_usec : int) -> int:
	var last_time = Time.get_ticks_usec()
	
	# TODO gravitor sweepline algorithm
	for i in 2048: # TODO fallback
		
		for small_body in _small_bodies.values():
			# Update the main course
			small_body.main_course.advance_cache() # at least once TODO: make it return false if no work and stop early!
			
			# Update the maneuvers
			for j in range(len(small_body.maneuvers)):
				var maneuver : Maneuver = small_body.maneuvers[j]
				if maneuver.valid:
					# Valid maneuver; propagate its cache as normal.
					maneuver.gravitee.advance_cache()
				else:
					# Invalid maneuver:
					# Perform a state-at-time query on their parent (or the main course)
					var parent_gravitee = small_body.main_course if j == 0 else small_body.maneuvers[j-1]
					var parent_state = parent_gravitee.state_at_time(maneuver.start_time)
					if is_instance_of(parent_state, Gravitee.State):
						# Parent has successfully reached maneuver head; we can validate and
						# begin computing the maneuver.
						maneuver.valid = true
						maneuver.gravitee.reset(parent_state.get_pos(), parent_state.get_vel(), maneuver.start_time)
						pass # TODO force application
					
		
		var cur_time = Time.get_ticks_usec()
		
		time_budget_usec -= (cur_time - last_time)
		if time_budget_usec <= 0:
			break
		
		last_time = cur_time
	
	return max(0, time_budget_usec)



# ========== INNARDS ==========

# The internal set of all large bodies managed by the simulation.
# Name -> Gravitor
var _large_bodies := {}

# Name of the root large body.
var _root_name : StringName

# The internal set of all small bodies managed by the simulation.
# Name -> SmallBody (internal class below)
var _small_bodies := {}

# Internal data class for small bodies, which may possess multiple Gravitee maneuvers.
class SmallBody extends RefCounted:
	var main_course : Gravitee
	var maneuvers := []

# Internal data class for the Maneuver list attached to some SmallBodies.
class Maneuver extends RefCounted:
	var gravitee : Gravitee
	var start_time : float
	var valid : bool = false
	# TODO: force representation






# TODO Temporary caching scheme (copied from test code)
# TODO QUANTIZE
var _last_queried_time := -1.0
var _cached_gravitors : Dictionary
var _cache_misses : int = 0
var _cache_hits : int = 0
func cached_gravitor_query(time : float) -> Dictionary:
	if not (time == _last_queried_time):
		# Cache miss
		_last_queried_time = time
		_cached_gravitors = _large_bodies[_root_name].all_states_at_time(time)
		_cache_misses += 1
	else:
		_cache_hits += 1
	return _cached_gravitors

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


# ========== READING FROM THE SIMULATION ==========

## Access static properties of a body by name. Returns null if not found.
func get_property_of(name : StringName, property : StringName):
	var body = _gravitors.get(name)
	if body:
		return body.get(property)
	body = _gravitees.get(name)
	if body:
		return body.get(property)
	return null


## Reading state from the simulation is done by time-based query, which returns
## the Cartesian state for all bodies in the system, as one
## of these.
class State extends RefCounted:
	
	## Simulation time of the state, in seconds. 
	var time : float
	
	
	## Returns the position Vector3 of the named body. Will return the fallback
	## value given if the body doesn't exist or doesn't have a state at the 
	## requested time (if the time precedes or succeeds its data, say).
	func get_pos_of(name : StringName, fallback = null):
		var gravitor_state = _gravitor_states.get(name, null)
		if gravitor_state:
			return gravitor_state.get_pos().vec3() # Gravitor.GlobalState
		var gravitee_state = _gravitee_states.get(name, null)
		if gravitee_state:
			return gravitee_state.get_pos().vec3() # Gravitee.State
		return fallback
	
	
	## Returns the velocity Vector3 of the named body, or null, as in get_pos_of.
	func get_vel_of(name : StringName, fallback = null):
		var gravitor_state = _gravitor_states.get(name, null)
		if gravitor_state:
			return gravitor_state.get_vel().vec3() # Gravitor.GlobalState
		var gravitee_state = _gravitee_states.get(name, null)
		if gravitee_state:
			return gravitee_state.get_vel().vec3() # Gravitee.State
		return fallback
	
	
	## Returns the name of the orbital parent of a large body, or the primary attractor
	## of a small body. Ditto fallback; will return null on the root attractor.
	func get_primary_of(name : StringName, fallback = null):
		var gravitor_state = _gravitor_states.get(name, null)
		if gravitor_state:
			return gravitor_state.gravitor.parent_name
		var gravitee_state = _gravitee_states.get(name, null)
		if gravitee_state:
			return gravitee_state.primary.name
		return fallback
	
	
	# Internal stuff; don't touch from without.
	var _gravitor_states : Dictionary # name -> Gravitor.GlobalState
	var _gravitee_states : Dictionary # name -> Gravitee.State



## Non-updating time-query function, used to foresee what the future will hold.
func peek_at_time(time : float) -> State:
	var state = _new_state_with_gravitors(time)
	
	# TODO TODO TODO small bodies
	
	return state

# TODO: per-item peeking, right? Would be useful!


## Updating time-query function, used to advance the simulation. If any small body in the
## simulation responds to its query by saying that it hasn't reached the requested point but will,
## the function will return null. Hence, if null is received, the user waits, running do_background_work,
## until the simulation propagates to the desired point, whereupon a valid State will be returned
func move_to_time(time : float) -> State:
	var state = _new_state_with_gravitors(time)
	
	# TODO POSSIBLE BUG: I *think* we're safe? If some gravitees are valid, and some are not
	# the valid ones will update their caches and move the heads. They'll then receive a
	# query for the same *time*. This shouldn't be a problem but might be!
	# IN FACT: we could *FREEZE* the gravitees that are 'up to date', perhaps?
	
	# Iterate over the small bodies' main courses
	for gravitee_name in _gravitees:
		var gravitee_state = _gravitees[gravitee_name].state_at_time(time, true)
		if is_instance_of(gravitee_state, TYPE_INT):
			if gravitee_state == 1:
				# waits.
				return null
			else:
				# precedes; does not report but does not prevent
				pass
		else:
			# valid; add to output
			state._gravitee_states[gravitee_name] = gravitee_state
	
	return state


# Auxiliary for the above, since large bodies don't care about propagation and can
# be sampled backwards and forwards
func _new_state_with_gravitors(time : float) -> State:
	# TODO QUANTIZE?
	var state := State.new()
	state.time = time
	state._gravitor_states = cached_gravitor_query(time)
	return state



# ========== WRITING TO THE SIMULATION ==========

## Initializer requires a name and a gravitational parameter (G * M) for the 
## root attractor of the system (as it's a fallback for various things)
func _init(root_name : StringName, root_mu : float):
	_root_name = root_name
	var new_root_gravitor = Gravitor.new()
	new_root_gravitor.name = root_name
	new_root_gravitor.pos_0 = DoubleVector3.ZERO()
	new_root_gravitor.vel_0 = DoubleVector3.ZERO()
	new_root_gravitor.mu = root_mu
	new_root_gravitor.parent_name = &""
	new_root_gravitor.parent = null
	# TODO set meaningful otherstate
	_gravitors[_root_name] = new_root_gravitor


## Add a large body that emits gravity and moves in a Keplerian orbit.
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
func add_gravitor(name : StringName, parent_name : StringName, parameters : Dictionary, orbit : Dictionary) -> void:
	assert(not name in _gravitors, "Body names must be unique!")
	assert(not name in _gravitees, "Body names must be unique!")
	
	assert("mu" in parameters, "Must specify mu parameter")
	var child_mu = parameters["mu"]
	
	var parent : Gravitor = _gravitors.get(parent_name)
	assert(parent, "Parent not found!")
	
	var new_child := Gravitor.new()
	new_child.name = name
	new_child.mu = child_mu
	new_child.parent_name = parent_name
	new_child.parent = parent
	
	new_child.arg_periapsis = orbit.get("arg_periapsis", 0.0)
	new_child.inclination = orbit.get("inclination", 0.0)
	new_child.ascending_long = orbit.get("ascending_long", 0.0)
	new_child.time_since_peri = orbit.get("time_since_peri", 0.0)
	
	# Fetch essential orbit parametrization
	if("periapsis" in orbit and "apoapsis" in orbit):
		# From apsides
		
		new_child.periapsis = orbit["periapsis"]
		new_child.apoapsis = orbit["apoapsis"]
		new_child.semimajor_axis = (new_child.periapsis + new_child.apoapsis) / 2.0
		new_child.eccentricity = 1.0 - (new_child.periapsis / new_child.semimajor_axis)
		
	elif("semimajor_axis" in orbit and "eccentricity" in orbit):
		# From axis/eccentricity
		
		new_child.semimajor_axis = orbit["semimajor_axis"]
		new_child.eccentricity = orbit["eccentricity"]
		new_child.periapsis = new_child.semimajor_axis / (1.0 - new_child.eccentricity)
		new_child.apoapsis = new_child.semimajor_axis / (1.0 + new_child.eccentricity)
		
	else:
		assert(false, "Must specify either apo/periapsidal pair or axis/eccentricity pair!")
	
	# Compute initial state from orbital parameters
	var initial_state = UniversalKepler.initial_conditions_from_kepler(
		parent.mu, new_child.semimajor_axis, new_child.eccentricity, new_child.arg_periapsis, 
		new_child.inclination, new_child.ascending_long, new_child.time_since_peri
	)
	new_child.pos_0 = initial_state[0]
	new_child.vel_0 = initial_state[1]
	
	# Set the new gravitor's remaining celestial properties
	new_child.period = TAU * sqrt((new_child.semimajor_axis * new_child.semimajor_axis * new_child.semimajor_axis) / (parent.mu + child_mu))
	new_child.soi_radius = 0.9431 * new_child.semimajor_axis * pow(child_mu / parent.mu, 2.0/5.0)
	new_child.soi_radius_squared = new_child.soi_radius * new_child.soi_radius
	
	# Add the new gravitor to the gravitor tree
	parent.children.append(new_child)
	
	# Add the new gravitor to the large body list
	_gravitors[name] = new_child


# TODO: small body creators, controllable vs uncontrollable (one 'tee or many)
## TODO: temporary small-body adder for maintain func test.
## TODO note: time-ref concerns
func add_gravitee(name : StringName, pos_0 : Vector3, vel_0 : Vector3, time_0 : float) -> void:
	assert(not name in _gravitors, "Body names must be unique!")
	assert(not name in _gravitees, "Body names must be unique!")
	
	var gravitee = Gravitee.new(DoubleVector3.from_vec3(pos_0), DoubleVector3.from_vec3(vel_0), time_0, cached_gravitor_query)
	_gravitees[name] = gravitee

# TODO: small body force modification.

# TODO: small body safe deletion
func remove_gravitee(name : StringName) -> void:
	assert(name in _gravitees, "Gravitee not found!")
	
	var gravitee : Gravitee = _gravitees[name]
	
	# Dechain the gravitee from its linked list
	# (Weakrefs are themselves ref-counted, so we just pass them on)
	if gravitee.predecessor_ref:
		gravitee.predecessor_ref.get_ref().successor_ref = gravitee.successor_ref
	if gravitee.successor_ref:
		gravitee.successor_ref.get_ref().predecessor_ref = gravitee.predecessor_ref
	
	# TODO: wipe it out of the sweepline, whenever we get around to that
	
	_gravitees.erase(name)



# ========== RUNNING THE SIMULATION ==========

## Invoke with a time budget in milliseconds. The simulation will do its background
## cache-advancing, etcetera, within said budget, and return what it didn't use.
func do_background_work(time_budget_usec : int) -> int:
	var last_time = Time.get_ticks_usec()
	
	# TODO sweepline algorithm
	for i in 256: # TODO fallback
		
		var all_done := true
		for gravitee in _gravitees.values():
			var is_done = gravitee.advance_cache() # at least once
			all_done = all_done and is_done
		
		var cur_time = Time.get_ticks_usec()
		
		time_budget_usec -= (cur_time - last_time)
		if time_budget_usec <= 0 or all_done:
			break
		
		last_time = cur_time
	
	return max(0, time_budget_usec)



# ========== ORBIT DRAWING ==========
# Orbit Drawing is one of those things we really don't have a solution for that's
# both modular and efficient (yet). So we break our paradigm a bit, for now.
# TODO TODO TODO TODO TODO: improve this!!!

# TODO:  remove! set up signals above
func connect_orbit_line(name : StringName, line : OrbitPolyline) -> void:
	var gravitee = _gravitees.get(name)
	assert(gravitee, "Cannot find body to connect to!")
	
	line.setup(gravitee.long_cache.length())
	gravitee.long_cache.added_item.connect(line.add_point)
	gravitee.long_cache.changed_item.connect(line.change_point)
	gravitee.long_cache.invalidate.connect(line.invalidate)





# ========== INNARDS ==========

# The internal set of all large bodies managed by the simulation.
# Name -> Gravitor
var _gravitors := {}

# Name of the root large body.
var _root_name : StringName

# The internal set of all small bodies managed by the simulation.
# Name -> Gravitee
var _gravitees := {}


# TODO Temporary caching scheme (copied from test code)
var _cache_misses : int = 0
var _cache_hits : int = 0
var _temp_cache := FIFOCache.new(30) # TODO automatic initial sizing

func cached_gravitor_query(time : float) -> Dictionary:
	var cache_query = _temp_cache.find(time)
	if cache_query:
		# Cache hit
		_cache_hits += 1
	
		return cache_query
	else:
		# Cache miss
		_cache_misses += 1
		
		var _new_all_gravitors = {}
		for gravitor in _gravitors.values():
			_new_all_gravitors[gravitor.name] = gravitor.state_at_time(time)
		
		_temp_cache.add(time, _new_all_gravitors)
		return _new_all_gravitors

func get_cache_ratio():
	return float(_cache_hits) / float(_cache_misses)

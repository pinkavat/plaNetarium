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


## In order to keep the caches patent, simulation is discrete. 
## TODO: setting etc.
var time_quantum := 1.0e-2


## The simulation uses an internal double-precision vector type to simplify
## computations (DoubleVector3). We don't want to expose the burden of its
## interface to a user, as Godot doesn't allow overriding operators. Hence,
## returned state is in single-precision Vector3s, and to maximize accuracy we
## scale the vectors down to the desired reduced size before shrinking them.
var space_scale := 1.0e-10


# ========== READING FROM THE SIMULATION ==========

## Reading from the simulation is done by time-based query, which returns
## the Cartesian state for all bodies in the system, as one
## of these.
class State extends RefCounted:
	
	## Simulation time of the state, in seconds. 
	var time : float
	
	
	## Simulation time of the state, in time quanta (see above).
	var qtime : int
	
	
	## Returns the position Vector3 of the named body. Will return the fallback
	## value given if the body doesn't exist or doesn't have a state at the 
	## requested time (if the time precedes or succeeds its data, say).
	func get_pos_of(name : StringName, fallback = null):
		return fallback # TODO WHAT DO IF NOT AT STATE???????????
	
	
	## Returns the velocity Vector3 of the named body, or null, as in get_pos_of.
	func get_vel_of(name : StringName, fallback = null):
		return fallback # TODO
	
	
	## Returns the orbital parent of a large body, or the primary attractor
	## of a small body. Ditto fallback.
	func get_primary_of(name : StringName, fallback = null):
		return fallback
	
	
	# Internal stuff; don't touch from without.
	var _large_states : Dictionary
	var _small_states : Dictionary



## Non-updating time-query function, used to foresee what the future will hold.
func peek_at_time(time : float) -> State:
	return null # TODO


## Updating time-query function, used to advance the simulation.
func move_to_time(time : float) -> State:
	return null # TODO

# TODO: cache advance


# ========== WRITING TO THE SIMULATION ==========

## Initializer requires a name and a gravitational parameter (G * M) for the 
## root attractor of the system (as it's a fallback for various things)
func _init(root_name : StringName, root_mu : float):
	_root = root_name
	_large_bodies[_root] = Gravitor.new(root_name, DoubleVector3.ZERO(), DoubleVector3.ZERO(), root_mu)


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
	assert(not name in _large_bodies, "Large body names must be unique!")
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
# TODO: small body force modification.


# ========== INNARDS ==========

# The internal set of all large bodies managed by the simulation.
# Name -> Gravitor
var _large_bodies := {}

# Name of the root large body.
var _root : StringName

class_name Gravitor
extends RefCounted

## Body moving on a Keplerian track, generating gravity (a planet, etc.).
##
## TODO: document
## Tree Node

## Unique name for this gravitor
var name : StringName


# === CELESTIAL PROPERTIES ===

## Standard Gravitational Parameter (G * M) of this body.
var mu : float

var periapsis : float = 0.0
var apoapsis : float = 0.0
var period : float = 1.0
var semimajor_axis : float = 0.0
var eccentricity : float = 0.0
var arg_periapsis : float = 0.0
var inclination : float = 0.0
var ascending_long : float = 0.0
var time_since_peri : float = 0.0

# The initial values are fallback safeties for the root primary (TODO resolve)
var soi_radius : float = 7.4e12 # TODO: unsafe. Used in 'approx satellite period calc'; for root, this should be fixed high value.
var soi_radius_squared : float = INF # TODO ditto, though this is used only in primary membership calc.


# === CONVENIENCE PROPERTIES ===
# (things that are expedient to compute as part of the integrator pass)

## Propagator will report putative lithobrake if course passes within square root distance of this value.
var collision_radius_squared : float = 1.0

# atmosphere here


# === HIERARCHY ===

## Parent gravitor, null for the root body.
var parent : Gravitor

## Parent name, used only for external property queries by the view.
var parent_name : StringName = &"" # Root value

## Array of Gravitor children of this body.
var children = []

# Last queried global state cache (TODO sophisticated caching on PER GRAVITOR BASIS...?)
var last_query_time : float = -INF
var last_query_state : GlobalState


# === UNIVERSAL-VARIABLE MODEL STATE ===

## Local position of body at reference time.
var pos_0 : DoubleVector3

## Local velocity of body at reference time.
var vel_0 : DoubleVector3

# Previous universal anomaly; cached for increased speed
var _prev_psi := 0.0



func _init(
	name_,
	mu_,
	parent_,
	semimajor_axis_ := 0.0,
	eccentricity_ := 0.0,
	arg_periapsis_ := 0.0,
	inclination_ := 0.0,
	ascending_long_ := 0.0,
	time_since_peri_ := 0.0,
) -> void:
	name = name_
	mu = mu_
	parent = parent_
	semimajor_axis = semimajor_axis_
	eccentricity = eccentricity_
	arg_periapsis = arg_periapsis_
	inclination = inclination_
	ascending_long = ascending_long_
	time_since_peri = time_since_peri_
	
	periapsis = semimajor_axis / (1.0 - eccentricity)
	apoapsis = semimajor_axis / (1.0 + eccentricity)
	
	if parent:
		parent_name = parent.name
		period = TAU * sqrt((semimajor_axis * semimajor_axis * semimajor_axis) / (parent.mu + mu))
		soi_radius = 0.9431 * semimajor_axis * pow(mu / parent.mu, 2.0/5.0)
		soi_radius_squared = soi_radius * soi_radius
		
		# Universal Kepler parameter setup
		var initial_state = UniversalKepler.initial_conditions_from_kepler(
			parent.mu, semimajor_axis, eccentricity, arg_periapsis, 
			inclination, ascending_long, time_since_peri
		)
		pos_0 = initial_state[0]
		vel_0 = initial_state[1]
	else:
		# Parentless root
		pos_0 = DoubleVector3.ZERO()
		vel_0 = DoubleVector3.ZERO()
		
		# TODO: good SOI for root?



## TODO: temporary scaffolding for simpler Kepler solver.
## NOTE: THIS IS PREDICATED ON ELLIPSOID ORBITS ONLY. Safe assumption, really, but
## MUST BE DOCUMENTED!!!!!!!!!!!!!!!!!!!!!!!!!!!
## EXPERIMENTALLY WE HAVE A DISCREPANCY Vs. UNIVERSAL OF 3 KM or so Position. Hmmmmm.
func _temp_kepple(time : float):
	
	# TODO: bowse out; all celestial vars go to initializer, which takes over
	# universal keplers' initial-cond-from-time stuff:
	var average_sweep_rate := TAU / period
	
	var mean_anomaly := average_sweep_rate * (time - time_since_peri)
	
	# TODO: cache initial eccentric anom. same way we cached psi
	
	# Bring on the Newton-Raphson hammer of successive approximation!
	var eccentric_anomaly := PI if eccentricity >= 0.8 else mean_anomaly
	while true: # TODO fallback; TODO count iterations needed; compare to Universal Kep.
				# TODO Stackoverf. suggests fix a max at 5 or so...?
		
		var delta_eccentric :=   \
			(eccentric_anomaly - eccentricity * sin(eccentric_anomaly) - mean_anomaly) /   \
			(1.0 - eccentricity * cos(eccentric_anomaly))
		
		eccentric_anomaly -= delta_eccentric
		
		if is_equal_approx(delta_eccentric, 0.0): # TODO larger epsilon?
			break
	
	# Bypass true anomaly entirely and go straight into orbit-plane 2D coordinates...
	# Courtesy of https://space.stackexchange.com/questions/8911/determining-orbital-position-at-a-future-point-in-time
	var p := semimajor_axis * (cos(eccentric_anomaly) - eccentricity)
	var q := -semimajor_axis * sin(eccentric_anomaly) * sqrt(1.0 - eccentricity * eccentricity)
	
	# ...which we then rotate into 3D space, using the remaining Kepler elements:
	var position = _temp_orbitplane_to_global(p, q)
	
	# Ditto velocity:
	var p_v := -semimajor_axis * sin(eccentric_anomaly) * average_sweep_rate / (1 - eccentricity * cos(eccentric_anomaly))
	var q_v := -semimajor_axis * cos(eccentric_anomaly) * sqrt(1 - eccentricity * eccentricity) * average_sweep_rate / (1 - eccentricity * cos(eccentric_anomaly))
	
	var velocity = _temp_orbitplane_to_global(p_v, q_v)
	
	return [position, velocity]
	# TODO return


# TODO doc
func _temp_orbitplane_to_global(p : float, q : float) -> DoubleVector3:
	# NOTE: this transformation differs from our notes -- y and z are flipped, and q is negated.
	# Reason being the notes were from (I think) a LHS, and Godot is RHS.
	var x := p * cos(arg_periapsis) - q * sin(arg_periapsis)
	var z := p * sin(arg_periapsis) + q * cos(arg_periapsis)
	var y := z * sin(inclination)
	z *= cos(inclination)
	var x_temp := x
	x = x_temp * cos(ascending_long) - z * sin(ascending_long)
	z = x_temp * sin(ascending_long) + z * cos(ascending_long)
	return DoubleVector3.new(x, y, z)




## Get the global state of this gravitor at the given time.
## TODO: interesting caching soln's here?
func state_at_time(time : float) -> GlobalState:
	if parent:
		# Not the root
		
		if time == last_query_time:
			# Cache hit
			return last_query_state
			
		else:
			# Cache miss
			last_query_time = time
			
			# Get local state with a Kepler step
			var local_state := UniversalKepler.query(pos_0, vel_0, 0.0, time, parent.mu, _prev_psi)
			_prev_psi = local_state[2]
			
			#var local_state = _temp_kepple(time)
			
			
			# Get parent's global state recursively
			var parent_state := parent.state_at_time(time)
			
			# Add to get our global state
			last_query_state = GlobalState.new(
				self, 
				local_state[0].add(parent_state.get_pos()),
				local_state[1].add(parent_state.get_vel())
			)
			
			return last_query_state
	else:
		# Root Gravitor
		return GlobalState.new(self, DoubleVector3.ZERO(), DoubleVector3.ZERO())



# ========== STATE CLASS ==========

## State class returned by the tree query, for the same reasons as Gravitee's State:
## to cheapen storage concerns and clarify naming.
class GlobalState extends RefCounted:
	
	# Backreference to the Gravitor whose state this is
	var gravitor : Gravitor
	
	# Position and velocity vectors, in global space, unrolled (see Gravitee's state)
	var _pos_x : float
	var _pos_y : float
	var _pos_z : float
	var _vel_x : float
	var _vel_y : float
	var _vel_z : float
	
	## Don't set state members. If we need to change them, just make a new state:
	func _init(gravitor_ : Gravitor, pos_ : DoubleVector3, vel_ : DoubleVector3):
		gravitor = gravitor_
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



# ========== LEGACY ROOT-TO-LEAF TRAVERSE ==========
# TODO: remove

## Gravitor tree query: returns a Dictionary name->GlobalState (see below) for every
## gravitor in the tree at the specified time. 
## SHOULD ONLY BE INVOKED ON THE ROOT GRAVITOR.
#func all_states_at_time(time : float) -> Dictionary:
#
#	var output := {}
#	_tree_state_query_kernel(time, output, DoubleVector3.ZERO(), DoubleVector3.ZERO())
#
#	# Add ourself, the root:
#	output[name] = GlobalState.new(self, DoubleVector3.ZERO(), DoubleVector3.ZERO())
#
#	return output
#
#
## Recursive kernel for the above. Appends to given output array.
#func _tree_state_query_kernel(time : float, output : Dictionary, pos : DoubleVector3, vel : DoubleVector3) -> void:
#
#	# For every child:
#	for child in children:
#		# Establish the child's local state, using the Kepler query on our own gravity param
#		var local_state := UniversalKepler.query(child.pos_0, child.vel_0, 0.0, time, mu, child._prev_psi)
#		child._prev_psi = local_state[2]
#
#		var global_pos : DoubleVector3 = local_state[0].add(pos)
#		var global_vel : DoubleVector3 = local_state[1].add(vel)
#
#		# Add this to the accumulated state to get the child's global state
#		var global_state := GlobalState.new(child, global_pos, global_vel)
#
#		# Append the global state to the output
#		output[child.name] = global_state
#
#		# Recurse
#		child._tree_state_query_kernel(time, output, global_pos, global_vel)

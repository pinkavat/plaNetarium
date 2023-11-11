class_name Gravitor
extends RefCounted

## Body moving on a Keplerian track, generating gravity (a planet, etc.).
##
## TODO: document
## Tree Node

## Unique name for this gravitor
var name : StringName


## Standard Gravitational Parameter (G * M) of this body.
var mu : float

## Local position of body at reference time.
var pos_0 : DoubleVector3

## Local velocity of body at reference time.
var vel_0 : DoubleVector3

## Parent backreference, used only for 'get primary' query
var parent : Gravitor = null

## Array of Gravitor children of this body.
var children = []


# ========== USEFUL PROPERTIES ==========

# The values are fallback safeties for the root primary.
var soi_radius : float = 7.4e12 # TODO: unsafe. Used in 'approx satellite period calc'; for root, this should be fixed high value.
var soi_radius_squared : float = INF # TODO ditto, though this is used only in primary membership calc.
var period : float = 10.0


# Previous universal anomaly; cached for increased speed
var prev_psi := 0.0

## TODO destroy!
## Factory function: creates and adds a new Gravitor to the Gravitor tree from
## the given orbital parameters. Returns the new child for reference.
func add_child_from_elements(
	name_ : StringName,				# Unique name for the Gravitor
	mu_ : float,					# Gravitational Parameter of new child

	semimajor_axis_ : float = 1.0,	# The 'fatter radius' of the ellipse
	eccentricity_ : float = 0.0,	# 0 is circle, >1 is hyperbola
	arg_periapsis_ : float = 0.0,	# the angle from the ascending node to the periapsis

	inclination_ : float = 0.0,		# angle from coplanarity to orbitee
	ascending_long_ : float = 0.0,	# angle from reference direction to ascending node

	time_since_peri_ : float = 0.0,	# Can't be arsed to parametrize by an anomaly
									# this is time elapsed between body at periapsis
									# and orbit's reference time zero)
) -> Gravitor:

	# Establish the Gravitor's Keplerian orbit, using our own mu
	var initial_state := UniversalKepler.initial_conditions_from_kepler(
				mu, semimajor_axis_, eccentricity_, arg_periapsis_, 
				inclination_, ascending_long_, time_since_peri_
			)

	# Make child and add it to our children
	var child := Gravitor.new(name_, initial_state[0], initial_state[1], mu_, self)
	child.period = TAU * sqrt((semimajor_axis_ * semimajor_axis_ * semimajor_axis_) / (mu + mu_))
	child.soi_radius = 0.9431 * semimajor_axis_ * pow(mu_ / mu, 2.0/5.0)
	child.soi_radius_squared = child.soi_radius * child.soi_radius
	children.append(child)

	return child

## TODO destroy!
## Factory function: creates and adds a new Gravitor to the Gravitor tree from
## the given apsides (a simplification of the above).
func add_child_from_apsides(
	name_ : StringName,					# Unique name for the Gravitor
	mu_ : float,						# Gravitational Parameter of new child

	periapsis_distance_ : float = 1.0,	# Distance to periapsis from orbitee
	apoapsis_distance_: float = 2.0,	# Distance to apoapsis from orbitee
	arg_periapsis_ : float = 0.0,		# the angle from the ascending node to the periapsis

	inclination_ : float = 0.0,			# angle from coplanarity to orbitee
	ascending_long_ : float = 0.0,		# angle from reference direction to ascending node
	time_since_peri_ : float = 0.0,		# See above
) -> Gravitor:

	# Establish the Gravitor's Keplerian orbit, using our own mu
	var initial_state := UniversalKepler.initial_conditions_from_apsides(
				mu, periapsis_distance_, apoapsis_distance_, arg_periapsis_, 
				inclination_, ascending_long_, time_since_peri_
			)

	# Make child and add it to our children
	var child := Gravitor.new(name_, initial_state[0], initial_state[1], mu_, self)
	var semimajor_axis_ = (periapsis_distance_ + apoapsis_distance_) / 2.0
	child.period = TAU * sqrt((semimajor_axis_ * semimajor_axis_ * semimajor_axis_) / (mu + mu_))
	child.soi_radius = 0.9431 * semimajor_axis_ * pow(mu_ / mu, 2.0/5.0)
	child.soi_radius_squared = child.soi_radius * child.soi_radius
	children.append(child)

	return child

## TODO destroy!
## Static factory function: creates an immobile root primary Gravitor.
static func make_root_gravitor(name_ : StringName, mu_ : float) -> Gravitor:
	return Gravitor.new(name_, DoubleVector3.ZERO(), DoubleVector3.ZERO(), mu_, null)


## Initialize a Gravitor with the given initial state (Cart2Cart, TODO improve).
## Not really meaningfully useable outside of invocation from the static factories above.
## TODO: in fact don't use it at all, since it doesn't set some of the 'useful properties'!
func _init(name_ : StringName, pos_0_ : DoubleVector3, vel_0_ : DoubleVector3, mu_ : float, parent_ : Gravitor) -> void:
	name = name_
	pos_0 = pos_0_
	vel_0 = vel_0_
	mu = mu_
	parent = parent_


## Gravitor tree query: returns a Dictionary name->GlobalState (see below) for every
## gravitor in the tree at the specified time. 
## SHOULD ONLY BE INVOKED ON THE ROOT GRAVITOR.
func all_states_at_time(time : float) -> Dictionary:
	
	var output := {}
	_tree_state_query_kernel(time, output, DoubleVector3.ZERO(), DoubleVector3.ZERO())
	
	# Add ourself, the root:
	output[name] = GlobalState.new(self, DoubleVector3.ZERO(), DoubleVector3.ZERO())
	
	return output


# Recursive kernel for the above. Appends to given output array.
func _tree_state_query_kernel(time : float, output : Dictionary, pos : DoubleVector3, vel : DoubleVector3) -> void:
	
	# For every child:
	for child in children:
		# Establish the child's local state, using the Kepler query on our own gravity param
		var local_state := UniversalKepler.query(child.pos_0, child.vel_0, 0.0, time, mu, child.prev_psi)
		child.prev_psi = local_state[2]
		
		var global_pos : DoubleVector3 = local_state[0].add(pos)
		var global_vel : DoubleVector3 = local_state[1].add(vel)
		
		# Add this to the accumulated state to get the child's global state
		var global_state := GlobalState.new(child, global_pos, global_vel)
		
		# Append the global state to the output
		output[child.name] = global_state
		
		# Recurse
		child._tree_state_query_kernel(time, output, global_pos, global_vel)


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

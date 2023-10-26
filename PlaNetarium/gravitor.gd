class_name Gravitor
extends RefCounted

## Body moving on a Keplerian track, generating gravity (a planet, etc.).
##
## TODO: document
## Tree Node

## Unique name for this gravitor (used to extract the gravitor from the system state)
var name : String # TODO: this ain't a great solution.


## Standard Gravitational Parameter (G * M) of this body.
var mu : float


## Local position of body at reference time.
var pos_0 : DoubleVector3

## Local velocity of body at reference time.
var vel_0 : DoubleVector3


## Array of Gravitor children of this body.
var children = []


# Previous universal anomaly; cached for increased speed
var prev_psi := 0.0


## Factory function: creates and adds a new Gravitor to the Gravitor tree from
## the given orbital parameters. Returns the new child for reference.
func add_child_from_elements(
	name_ : String,					# Unique name for the Gravitor
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
	var child := Gravitor.new(name_, initial_state[0], initial_state[1], mu_)
	children.append(child)
	
	return child


## Factory function: creates and adds a new Gravitor to the Gravitor tree from
## the given apsides (a simplification of the above).
func add_child_from_apsides(
	name_ : String,						# Unique name for the Gravitor
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
	var child := Gravitor.new(name_, initial_state[0], initial_state[1], mu_)
	children.append(child)
	
	return child


## Static factory function: creates an immobile root primary Gravitor.
static func make_root_gravitor(name_ : String, mu_ : float) -> Gravitor:
	return Gravitor.new(name_, DoubleVector3.ZERO(), DoubleVector3.ZERO(), mu_)


## Initialize a Gravitor with the given initial state (Cart2Cart, TODO improve).
## Not really meaningfully useable outside of invocation from the static factories above.
func _init(name_ : String, pos_0_ : DoubleVector3, vel_0_ : DoubleVector3, mu_ : float) -> void:
	name = name_
	pos_0 = pos_0_
	vel_0 = vel_0_
	mu = mu_


## Gravitor tree query: returns a Dictionary name->[pos, vel, mu] 'tuples' for every
## gravitor in the tree at the specified time. 
## SHOULD ONLY BE INVOKED ON THE ROOT GRAVITOR.
func all_states_at_time(time : float) -> Dictionary:
	var output := {}
	_tree_state_query_kernel(time, output, DoubleVector3.ZERO(), DoubleVector3.ZERO())
	
	# Add ourself, the root:
	output[name] = [DoubleVector3.ZERO(), DoubleVector3.ZERO(), mu]
	
	return output


# Recursive kernel for the above. Appends to given output array.
func _tree_state_query_kernel(time : float, output : Dictionary, pos : DoubleVector3, vel : DoubleVector3) -> void:
	
	# For every child:
	for child in children:
		# Establish the child's local state, using the Kepler query on our own gravity param
		var local_state := UniversalKepler.query(child.pos_0, child.vel_0, 0.0, time, mu, child.prev_psi)
		child.prev_psi = local_state[2]
		
		# Add this to the accumulated state to get the child's global state
		var global_state := [local_state[0].add(pos), local_state[1].add(vel), child.mu]
		
		# Append the global state to the output
		output[child.name] = global_state
		
		# Recurse
		child._tree_state_query_kernel(time, output, global_state[0], global_state[1])

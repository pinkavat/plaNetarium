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

## Parent gravitor, null for the root body.
var parent : Gravitor

## Parent name, used only for external property queries by the view.
var parent_name : StringName = &""

## Array of Gravitor children of this body.
var children = []

# Previous universal anomaly; cached for increased speed
var _prev_psi := 0.0

# Last queried global state cache (TODO sophisticated caching on PER GRAVITOR BASIS...?)
var last_query_time : float = -INF
var last_query_state : GlobalState


# ========== CELESTIAL PROPERTIES ==========

# The initial values are fallback safeties for the root primary (TODO resolve)
var soi_radius : float = 7.4e12 # TODO: unsafe. Used in 'approx satellite period calc'; for root, this should be fixed high value.
var soi_radius_squared : float = INF # TODO ditto, though this is used only in primary membership calc.

var periapsis : float = 0.0
var apoapsis : float = 0.0
var period : float = 1.0
var semimajor_axis : float = 0.0
var eccentricity : float = 0.0
var arg_periapsis : float = 0.0
var inclination : float = 0.0
var ascending_long : float = 0.0



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

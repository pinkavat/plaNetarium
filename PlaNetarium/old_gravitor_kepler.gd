class_name UniversalKepler # Namespace squatting, pending upgrade
extends RefCounted

## Static helpers for position/velocity based kepler formulations
## for Gravitors.
##
## TODO: Essentially outmoded; kepler should be simpler thing based
## directly on orbital elements.
##
## Copy of the old Patched Conics Universal Kepler Utility
## tweaked for double-precision
##
##	Implements W.H. Goodyear's 1966 Universal Kepler formulation 
##	(https://ntrs.nasa.gov/citations/19660027556)


## TODO: consider more graceful fallback handling.
const FALLBACK_MAX_ITERATIONS = 3000


## Returns an array [pos, vel, psi] at given time since time_0
## Pos and vel are the Cartesian State Vectors
## Psi is the found universal anomaly: it is efficient to feed this back into
## the psi parameter as a guess to the next query, if the next query is 
## temporally close, say.
## Dimensionless: units depend on each other; specifically
## the choice of mu (gravity parameter)
static func query(
		pos_0 : DoubleVector3,	# Position of body at time_0
		vel_0 : DoubleVector3,	# Velocity of body at time_0
		time_0 : float,		# Reference time
		time : float,		# Query time: returned pos and vel are at this time
		mu : float,			# Orbitee Kepler Gravitational Parameter (G * M)
		psi := 0.0			# Optional initial guess for Universal Anomaly
							# (Converges just fine without one)
	) -> Array:
	
	# 1) Pre-iteration calculations
	var tau := time - time_0
	
	if(tau == 0.0):
		return [pos_0, vel_0, psi]
	
	var r_0 := sqrt(pos_0.dot(pos_0))
	var sigma_0 := pos_0.dot(vel_0)
	var alpha := vel_0.dot(vel_0) - 2.0 * mu / r_0;
	
	# Establish iteration-space boundaries
	var psi_min : float
	var psi_max : float
	var delta_tau_min : float
	var delta_tau_max : float
	if tau < 0.0:
		psi_min = -INF
		psi_max = 0.0
		delta_tau_min = -INF
		delta_tau_max = -tau
	else:
		psi_min = 0.0
		psi_max = INF
		delta_tau_min = -tau
		delta_tau_max = INF
	
	# Tune universal anomaly estimate to be in bounds
	if (psi > psi_max or psi < psi_min):
		psi = tau / r_0;
	if (psi > psi_max or psi < psi_min):
		psi = tau;
	
	
	
	# 2) Newton's method iteration
	var iter_count : int = 0
	var s_1 : float
	var s_2 : float
	var r : float
	var g : float
	var delta_tau : float
	while true:					# No do-while, Godot?
		iter_count += 1
		if iter_count > FALLBACK_MAX_ITERATIONS:
			print("ERROR: UNIVERSAL KEPLER FAILED TO CONVERGE!")
			# TODO: throw something?
			break
		
		# 2a) Stumpff series computations
		var lambda := alpha * psi * psi
		var lambda_p := lambda
		
		var lambda_mod_count : int = 0
		while abs(lambda) > 1.0:
			lambda = lambda / 4.0
			lambda_mod_count += 1
		
		# Stumpff madness
		var c_5x3 := (1.0 + (1.0 + (1.0 + (1.0 + (1.0 + (1.0 + (1.0 + lambda/342.0) * lambda/272.0)
				* lambda/210.0) * lambda/156.0) * lambda/110.0) * lambda/72.0) * lambda/42.0) / 40.0
		var c_4 := (1.0 + (1.0 + (1.0 + (1.0 + (1.0 + (1.0 + (1.0 + lambda/306.0) * lambda/240.0)
				* lambda/182.0) * lambda/132.0) * lambda/90.0) * lambda/56.0) * lambda/30.0) / 24.0
		var c_3 := (0.5 + lambda * c_5x3) / 3.0
		var c_2 := 0.5 + lambda * c_4
		var c_1 := 1.0 + lambda * c_3
		var c_0 := 1.0 + lambda * c_2
		
		
		if lambda_mod_count > 0:
			# if demod needful, effect it.
			while lambda_mod_count > 0:
				lambda_mod_count -= 1
				c_1 = c_1 * c_0
				c_0 = 2.0 * c_0 * c_0 - 1.0
			
			c_2 = (c_0 - 1.0) / lambda_p
			c_3 = (c_1 - 1.0) / lambda_p
			# TODO: missing c_4 and c_5x3 from original algo because
			# the values aren't used for our purposes.
		
		var s_3 := psi * psi * psi * c_3
		s_2 = psi * psi * c_2
		s_1 = psi * c_1
		
		
		# 2b) Test-fit to Kepler Equation
		
		g = r_0 * s_1 + sigma_0 * s_2
		delta_tau = (g + mu * s_3) - tau
		r = abs(r_0 * c_0 + (sigma_0 * s_1 + mu * s_2))
		
		# If we're satisfied, stop loop and compute coordinates.
		if is_zero_approx(delta_tau):
			break
		
		# Otherwise, move the bounds...
		if delta_tau < 0:
			delta_tau_min = delta_tau
			psi_min = psi
		else:
			delta_tau_max = delta_tau
			psi_max = psi
		
		
		#...and apply one step of Newton's method:
		psi = psi - delta_tau / r
		
		
		# 2c) Check to see if psi is in bounds, trying ever-more desperate
		#     corrective measures if not
		if psi > psi_min and psi < psi_max:
			continue
		#	Desperation measure 0
		if abs(delta_tau_min) < abs(delta_tau_max):
			psi = psi_min * (1.0 - (4.0 * delta_tau_min) / tau)
		elif abs(delta_tau_min) > abs(delta_tau_max):
			psi = psi_max * (1.0 - (4.0 * delta_tau_max) / tau)
		
		if psi > psi_min and psi < psi_max:
			continue
		# Desperation measure 1
		if tau > 0:
			psi = psi_min + psi_min
		elif tau < 0:
			psi = psi_max + psi_max
		
		if psi > psi_min and psi < psi_max:
			continue
		# Desperation measure 2
		psi = psi_min - (psi_max - psi_min) * (delta_tau * (delta_tau_max - delta_tau_min))
		
		if psi > psi_min and psi < psi_max:
			continue
		# Desperation measure 3
		psi = psi_min + (psi_max - psi_min) * 0.5
		
		if psi > psi_min and psi < psi_max:
			continue
		# We can't find a better psi; stop and compute coordinates.
		break
	
	
	# 3) Convergence or failure: convert result values to coordinates
	var fm1 := -mu * s_2 / r_0
	var fd := -mu * s_1 / r_0 / r
	var gdm1 := -mu * s_2 / r
	
	var pos_new := pos_0.add(pos_0.mul(fm1).add(vel_0.mul(g)))
	var vel_new := vel_0.add(pos_0.mul(fd).add(vel_0.mul(gdm1)))
	
	return [pos_new, vel_new, psi]



# Reference vectors used
# TODO: we were going to make it local! MAKE IT LOCAL! MAKE IT LOCAL!
const _REFERENCE_AXIS = Vector3(1, 0, 0)
const _REFERENCE_NORMAL = Vector3(0, 1, 0)	# TODO change this to 0, 1, 0 for non-2D flattening

# TODO: mass is never used...?

## Constructor func for initial position and velocity, from orbital elements
## (Copy of patched conics' StableOrbiter.gd)
static func initial_conditions_from_kepler(
		orbitee_mu : float,				# Standard Gravitational Parameter of orbited body
		
		semimajor_axis : float = 1.0,	# The 'fatter radius' of the ellipse
		eccentricity : float = 0.0,		# 0 is circle, >1 is hyperbola
		arg_periapsis : float = 0.0,	# the angle from the ascending node to the periapsis
		
		inclination : float = 0.0,		# angle from coplanarity to orbitee
		ascending_long : float = 0.0,	# angle from reference direction to ascending node
		
		time_since_peri : float = 0.0,	# Can't be arsed to parametrize by an anomaly
										# this is time elapsed between body at periapsis
										# and orbit's reference time zero
	) -> Array:
	# Compute periapsidal position from given parameters
		
	# Begin by sticking the periapsis distance along reference axis
	var periapsis_length := semimajor_axis * (1.0 - eccentricity)
	var periapsis := periapsis_length * _REFERENCE_AXIS
		
	# Rotate it around the reference plane normal by the ascending longitude
	periapsis = periapsis.rotated(_REFERENCE_NORMAL, ascending_long)
		
	# Then rotate the reference normal by the inclination around *that*...
	var inclined_normal := _REFERENCE_NORMAL.rotated(periapsis.normalized(), inclination)
		
	# Then finally rotate the periapsis around the inclined normal by the 
	# argument of periapsis.
	periapsis = periapsis.rotated(inclined_normal, arg_periapsis)
		
	# Compute velocity from periapsis
	var velocity := sqrt(orbitee_mu * ((2.0 / periapsis_length) - (1.0 / semimajor_axis)))
	var velocity_vector := velocity * (periapsis.rotated(inclined_normal, PI / 2.0)).normalized()
		
		
	# Finally add the time since periapsis, using our handy existing utility
	var new_state : Array = query(
		DoubleVector3.from_vec3(periapsis), DoubleVector3.from_vec3(velocity_vector), 0.0, time_since_peri, orbitee_mu
	)
		
	return new_state


## Constructor func for initial position and velocity, from apsidal distances
static func initial_conditions_from_apsides(
		orbitee_mu : float,					# Standard Gravitational Parameter of orbited body
		
		periapsis_distance : float = 1.0,	# Distance to periapsis from orbitee
		apoapsis_distance: float = 2.0,		# Distance to apoapsis from orbitee
		arg_periapsis : float = 0.0,		# the angle from the ascending node to the periapsis
		
		inclination : float = 0.0,		# angle from coplanarity to orbitee
		ascending_long : float = 0.0,	# angle from reference direction to ascending node
		time_since_peri : float = 0.0,	# See make_orbit_from_kepler above
	) -> Array:
	
	var semimajor_axis := (periapsis_distance + apoapsis_distance) / 2.0
	var eccentricity := (apoapsis_distance / semimajor_axis) - 1.0
	
	return initial_conditions_from_kepler(orbitee_mu, semimajor_axis, eccentricity, arg_periapsis,
		inclination, ascending_long, time_since_peri)


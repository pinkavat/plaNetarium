extends RefCounted
class_name ApsisWatcher
# TODO: make NODE to resolve ownership questions?

## Utility for monitoring the long cache of a Gravitee, detecting 
## orbital apsides.

## Emitted when any apsis changes
signal apsides_changed

var _gravitee : Gravitee

var periapsides := {}
var apoapsides := {}
var collisions := {}


func _init(gravitee_ : Gravitee):
	_gravitee = gravitee_
	
	# Link signals into the gravitee's long cache
	var cache = gravitee_.long_cache
	cache.added_item.connect(_added_item)
	#cache.changed_item.connect(_changed_item)
	#cache.shifted_left.connect(_shifted_left)
	cache.invalidate.connect(_invalidate)

# NOTE: LURKING PROBLEM HERE. the cache can CHANGE its head item, instead of 
# adding/invalidating, so a periapsis will become a different object before it's
# invalidated. Hmmmmmm.


# Signal callback from the long cache; trigger on item change or add
func _added_item(_index : int, item : Gravitee.State):
	
	# Periapsis check
	_added_helper(item, Gravitee.FLAG_PERIAPSIS, periapsides)
	
	# Apoapsis check
	_added_helper(item, Gravitee.FLAG_APOAPSIS, apoapsides)
	
	# Collision check
	_added_helper(item, Gravitee.FLAG_LITHOBRAKE, collisions)


func _invalidate(_index : int, item : Gravitee.State):
	
	# Periapsis check
	_invalidated_helper(item, Gravitee.FLAG_PERIAPSIS, periapsides)
	
	# Apoapsis check
	_invalidated_helper(item, Gravitee.FLAG_APOAPSIS, apoapsides)
	
	# Collision check
	_invalidated_helper(item, Gravitee.FLAG_LITHOBRAKE, collisions)


func _added_helper(item : Gravitee.State, flag : int, dict : Dictionary):
	if item.flags & flag:
		var prim_items = dict.get(item.primary.name, null)
		if prim_items:
			# Entry exists for this primary
			prim_items.append(item)
			# TODO maintain sorted order? Emit signal?
		else:
			# Entry doesn't exist for this primary
			dict[item.primary.name] = [item]


func _invalidated_helper(item : Gravitee.State, flag : int, dict : Dictionary):
		if item.flags & flag:
			# Clean out the items associated with this primary
			var prim_items = dict.get(item.primary.name, null)
			if prim_items:
				dict[item.primary.name] = prim_items.filter(func(x) : return x.qtime > item.qtime)

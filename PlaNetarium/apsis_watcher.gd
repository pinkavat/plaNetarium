extends RefCounted
class_name ApsisWatcher
# TODO: make NODE to resolve ownership questions?

## Utility for monitoring the long cache of a Gravitee, detecting 
## orbital apsides.

## Emitted when any apsis changes
signal apsides_changed

var _gravitee : Gravitee

var periapsides := {}


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
	if item.flags & Gravitee.FLAG_PERIAPSIS:
		var prim_peris = periapsides.get(item.primary.name, null)
		if prim_peris:
			# Entry exists for this primary
			prim_peris.append(item)
			# TODO maintain sorted order? Emit signal?
		else:
			# Entry doesn't exist for this primary
			periapsides[item.primary.name] = [item]
	
	# TODO apo -- make helper


func _invalidate(_index : int, item : Gravitee.State):
	
	# Periapsis check
	if item.flags & Gravitee.FLAG_PERIAPSIS:
		# Clean out the periapsides associated with this primary
		var prim_peris = periapsides.get(item.primary.name, null)
		if prim_peris:
			periapsides[item.primary.name] = prim_peris.filter(func(x) : return x.qtime > item.qtime)
	
	# TODO apo -- make helper

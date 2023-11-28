extends RefCounted
class_name FIFOCache

## Primitive First-In-First-Out key-access cache.
##
## Is this worth the script it's written in? Only time will tell... and
## it's good practice to find out where such a thing could be attached were it
## in a more powerful language and with greater optimization.

## Number of items in the cache
var length := 0

## Number of positions in the cache (not a backing array size, just the FIFO policy
## control)
var max_length := 0

# The actual cache. Stores associations between cached items and _Item objects
# (below) storing their place in the FIFO order.
var _cache := {}

# Linked-list pointers are the KEY VARIANTS, NOT the _Item
# objects, so that we can delete them from the Dictionary.
var oldest_head_key = null
var newest_tail_key = null


func _init(max_length_ : int):
	max_length = max_length_


## Adds the given item to the cache, evicting the oldest item if the cache is at
## maximum length. Fails silently if the key is already taken (TODO ?)
func add(key, value):
	if not key in _cache:
		# Add the new item
		var backing_item = _Item.new()
		backing_item.value = value
		_cache[key] = backing_item
		
		# Make the new item the cache tail
		if newest_tail_key:
			_cache[newest_tail_key].next_key = key
		else:
			oldest_head_key = key
		newest_tail_key = key
		
		# If the cache is full, evict the oldest item
		if length >= max_length:
			var second_oldest_key = _cache[oldest_head_key].next_key
			_cache.erase(oldest_head_key)
			oldest_head_key = second_oldest_key
		else:
			length += 1


## Finds the requested item in the cache, returning null if not found.
func find(key):
	var item = _cache.get(key, null)
	return item.value if item else null


# Pseudo-linked-list internal node of the cache, storing FIFO order.
class _Item:
	
	# The item in question
	var value
	
	# The key variant of the next youngest item
	var next_key = null

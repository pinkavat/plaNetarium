class_name RingBuffer
extends RefCounted

## Basic ring buffer supporting indexed access, resizing, and shifting.
##
## TODO: implement resize op


# The actual underlying element array.
var _backing

# Index of the ring buffer's nilth element in the backing array
var _head


## Creates a new ring buffer of the given number of elements.
func _init(size : int):
	_backing = []
	_backing.resize(size)
	_head = 0


## Get the length of the ring buffer.
func length() -> int:
	return len(_backing) # A pity that GDscript doesn't allow overriding len


## Element accessor: returns the element at the given index, or null if index is out of bounds
func get_at(index : int) -> Variant:
	if index < 0 or index >= len(_backing):
		return null
	return _backing[(_head + index) % len(_backing)]


## Element mutator: sets the element at the given index, returning true if successful;
## OOB index will return false.
func set_at(index : int, value : Variant) -> bool:
	if index < 0 or index >= len(_backing):
		return false
	_backing[(_head + index) % len(_backing)] = value
	return true


## Shift buffer left: appears to shift all elements in the buffer left by n.
## (the point of a ring buffer, of course, is that no elements are actually moved)
func shift_left(n : int) -> void:
	_head = (_head + n) % len(_backing)


## Shift buffer right: appears to shift all elements in the buffer right by n.
func shift_right(n : int) -> void:
	_head = (_head - (n % len(_backing)) + len(_backing)) % len(_backing)


## Changes the length of the ring buffer. If increased, new values are uninitialized.
func resize(new_length : int) -> void:
	assert(false, "Unimplemented function") # TODO: implement
	if new_length < len(_backing):
		# Decrease
		pass # TODO nontrivial cutting and copying
	else:
		# Increase
		pass # TODO nontrivial cutting and copying

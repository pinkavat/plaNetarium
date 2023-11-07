class_name DoubleVector3
extends RefCounted

## Three doubles crudely glued together.
##
## The simplest way to do interplanetary physics in our model is to use
## doubles instead of floats; however, switching Godot's native vectors
## to doubles requires engine recompilation, and holds for all vectors,
## even if we don't need the extra space.
##
## Hence this barebones class, which is an efficiency/useability tradeoff
## and ought not to be employed outside PlaNetarium core.

var x : float
var y : float
var z : float


func _init(x_ : float, y_ : float, z_ : float):
	x = x_
	y = y_
	z = z_


## Makes a DoubleVector3 from a Vector3
## (Can't overload constructors? Huh!).
static func from_vec3(vec : Vector3) -> DoubleVector3:
	return DoubleVector3.new(vec.x, vec.y, vec.z)

## Zero-constant.
static func ZERO() -> DoubleVector3:
	return DoubleVector3.new(0, 0, 0)

## Cloning (hmmm...).
#func clone() -> DoubleVector3:
#	return DoubleVector3.new(x, y, z)


## Equality check, using engine equality.
func equals(other : DoubleVector3) -> bool:
	return is_equal_approx(x, other.x) and is_equal_approx(y, other.y) and is_equal_approx(z, other.z)


## Equality check, with manually specified error.
func equals_approx(other : DoubleVector3, error : float) -> bool:
	return (abs(x - other.x) <= error) and (abs(y - other.y) <= error) and (abs(z - other.z) <= error)


## Returns a new DoubleVector3 as componentwise self + other.
func add(other : DoubleVector3) -> DoubleVector3:
	return DoubleVector3.new(x + other.x, y + other.y, z + other.z)


## Returns a new DoubleVector3 as componentwise self - other.
func sub(other : DoubleVector3) -> DoubleVector3:
	return DoubleVector3.new(x - other.x, y - other.y, z - other.z)


## Returns a new DoubleVector3, self scalar multiply by value.
func mul(scalar : float) -> DoubleVector3:
	return DoubleVector3.new(x * scalar, y * scalar, z * scalar)


## Returns a new DoubleVector3, self scalar divided by value.
func div(scalar : float) -> DoubleVector3:
	return DoubleVector3.new(x / scalar, y / scalar, z / scalar)


## Returns the dot product of self and other.
func dot(other : DoubleVector3) -> float:
	return x * other.x + y * other.y + z * other.z


## Returns an engine Vector3 with these values (precision lost, of course).
func vec3() -> Vector3:
	return Vector3(x, y, z)


## String representation.
func _to_string() -> String:
	return '<' + str(x) + ', ' + str(y) + ', ' + str(z) + '>'

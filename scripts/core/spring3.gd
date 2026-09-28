class_name Spring3
extends RefCounted
## Damped spring for Vector3 values (procedural animation).

var value := Vector3.ZERO
var velocity := Vector3.ZERO
var target := Vector3.ZERO
var stiffness := 120.0
var damping := 14.0


func _init(k := 120.0, d := 14.0) -> void:
	stiffness = k
	damping = d


func step(dt: float) -> Vector3:
	# semi-implicit euler with sub-stepping for stability at high stiffness
	var n := maxi(1, ceili(dt / 0.004))
	var h := dt / n
	for i in n:
		var acc := (target - value) * stiffness - velocity * damping
		velocity += acc * h
		value += velocity * h
	return value


func impulse(v: Vector3) -> void:
	velocity += v

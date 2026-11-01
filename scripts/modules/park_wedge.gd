@tool
class_name ParkWedge
extends ParkModule
## Cuña curva de hormigón: una losa suelta con la superficie cóncava, a ras de suelo por
## delante (u = 0) y con un canto alto y vivo por detrás (u = length). El canto es
## grindable. Es un quarter pipe pequeño y sin deck.

const SEGMENTS := 10

@export var width := 2.2:
	set(v):
		width = v
		queue_rebuild()
@export var length := 2.0:
	set(v):
		length = v
		queue_rebuild()
## Altura del canto. Cuanto más alta respecto al largo, más vertical acaba la curva.
@export var height := 0.9:
	set(v):
		height = v
		queue_rebuild()
@export var color := Color(0.67, 0.66, 0.63):
	set(v):
		color = v
		queue_rebuild()


## Radio del círculo que pasa por (0, 0) y (length, height) con tangente horizontal en 0.
func _radius() -> float:
	return (length * length + height * height) / (2.0 * height)


func _height(u: float) -> float:
	var r := _radius()
	return r - sqrt(maxf(r * r - u * u, 0.0001))


func _build() -> void:
	var hw := width * 0.5
	var side := color.darkened(0.22)
	for i in SEGMENTS:
		var u0 := length * float(i) / SEGMENTS
		var u1 := length * float(i + 1) / SEGMENTS
		var y0 := _height(u0)
		var y1 := _height(u1)
		var mid := (u0 + u1) * 0.5
		# Superficie cóncava: la normal sale hacia arriba.
		_quad_out(Vector3(u0, y0, -hw), Vector3(u1, y1, -hw), Vector3(u1, y1, hw), Vector3(u0, y0, hw),
			Vector3(mid, -5.0, 0.0), color)
		for sv in [-1.0, 1.0]:
			var z: float = hw * sv
			_quad_out(Vector3(u0, 0.0, z), Vector3(u1, 0.0, z), Vector3(u1, y1, z), Vector3(u0, y0, z),
				Vector3(mid, y0 * 0.5, 0.0), side)
	# Cara trasera vertical, bajo el canto.
	_quad_out(Vector3(length, 0.0, -hw), Vector3(length, 0.0, hw), Vector3(length, height, hw),
		Vector3(length, height, -hw), Vector3(length * 0.5, height * 0.5, 0.0), color.darkened(0.12))


func register(park: Object) -> void:
	# Mismo suelo que un quarter pipe sin deck (el círculo acaba justo en el canto).
	park.shapes.append({"type": "qp", "o": _origin(), "dir": _dir(), "w": width, "h": height,
		"r": _radius(), "ulip": length, "len": length, "y0": global_position.y, "nomesh": true})
	park.rails.append({"a": _world(length, width * 0.5 - 0.15, height + 0.02),
		"b": _world(length, -(width * 0.5 - 0.15), height + 0.02), "kind": "coping", "nomesh": true})

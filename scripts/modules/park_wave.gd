@tool
class_name ParkWave
extends ParkModule
## Ola de hormigón (VAG-3): varias crestas suaves seguidas, plana en los extremos y con
## una placa negra en cada punta. Se rueda en los dos sentidos; no es grindable.
## La altura es la de la cresta sobre el suelo; los valles tocan el suelo.

const SEGMENTS_PER_CREST := 8
## Elevación visual para que la malla no parpadee contra el suelo (la física no la usa).
const LIFT := 0.02
const PLATE_LENGTH := 0.2
const C_PLATE := Color(0.08, 0.08, 0.1)

@export var length := 10.0:
	set(v):
		length = v
		queue_rebuild()
@export var width := 2.5:
	set(v):
		width = v
		queue_rebuild()
@export var crest_height := 0.35:
	set(v):
		crest_height = v
		queue_rebuild()
@export_range(1, 8) var crests := 3:
	set(v):
		crests = v
		queue_rebuild()
## Altura de la primera cresta respecto a las demás (1 = todas iguales).
@export_range(0.1, 1.0) var first_scale := 1.0:
	set(v):
		first_scale = v
		queue_rebuild()
## Tramo plano al principio y al final.
@export var flat_end := 0.5:
	set(v):
		flat_end = v
		queue_rebuild()
@export var color := Color(0.64, 0.63, 0.62):
	set(v):
		color = v
		queue_rebuild()


## Altura de la ola en u (0 en los tramos planos).
func _height(u: float) -> float:
	var lw := length - 2.0 * flat_end
	var t := u - flat_end
	if lw <= 0.0 or t <= 0.0 or t >= lw:
		return 0.0
	var ch := crest_height * (first_scale if t < lw / crests else 1.0)
	return ch * 0.5 * (1.0 - cos(TAU * crests * t / lw))


func _build() -> void:
	var plate := minf(PLATE_LENGTH, flat_end)
	var lw := length - 2.0 * flat_end
	var us: Array[float] = [0.0, plate, flat_end]
	var n := maxi(crests, 1) * SEGMENTS_PER_CREST
	for i in range(1, n + 1):
		us.append(flat_end + lw * float(i) / float(n))
	us.append(length - plate)
	us.append(length)
	var hw := width * 0.5
	var side := color.darkened(0.25)
	for i in us.size() - 1:
		var u0 := us[i]
		var u1 := us[i + 1]
		if u1 - u0 < 0.001:
			continue
		var y0 := _height(u0) + LIFT
		var y1 := _height(u1) + LIFT
		var mid := (u0 + u1) * 0.5
		var col := C_PLATE if (mid < plate or mid > length - plate) else color
		var a := Vector3(u0, y0, -hw)
		var b := Vector3(u1, y1, -hw)
		var c := Vector3(u1, y1, hw)
		var d := Vector3(u0, y0, hw)
		_quad_out(a, b, c, d, Vector3(mid, -5.0, 0.0), col)
		for sv in [-1.0, 1.0]:
			var z: float = hw * sv
			_quad_out(Vector3(u0, 0.0, z), Vector3(u1, 0.0, z), Vector3(u1, y1, z), Vector3(u0, y0, z),
				Vector3(mid, y0 * 0.5, 0.0), side)


func register(park: Object) -> void:
	park.shapes.append({"type": "wave", "o": _origin(), "dir": _dir(), "w": width, "len": length,
		"h": crest_height, "n": crests, "flat": flat_end, "first": first_scale, "y0": global_position.y, "nomesh": true})

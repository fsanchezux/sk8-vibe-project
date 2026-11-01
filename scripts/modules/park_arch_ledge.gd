@tool
class_name ParkArchLedge
extends ParkModule
## Ledge inclinado sobre un arco: una barra ancha y plana que sube desde el suelo (u = 0)
## hasta high_end (u = length), apoyada en un arco semicircular. La cara superior es
## grindable en los dos sentidos. El arco es decorativo y no bloquea el paso.

const ARCH_SEGMENTS := 12

@export var length := 3.5:
	set(v):
		length = v
		queue_rebuild()
@export var width := 0.25:
	set(v):
		width = v
		queue_rebuild()
## Grosor de la barra.
@export var thickness := 0.12:
	set(v):
		thickness = v
		queue_rebuild()
@export var low_end := 0.06:
	set(v):
		low_end = v
		queue_rebuild()
@export var high_end := 0.7:
	set(v):
		high_end = v
		queue_rebuild()
## Dónde está el arco a lo largo de la barra (0 = extremo bajo, 1 = extremo alto).
@export_range(0.1, 0.9) var arch_pos := 0.62:
	set(v):
		arch_pos = v
		queue_rebuild()
@export var color := Color(0.26, 0.37, 0.5):
	set(v):
		color = v
		queue_rebuild()


## Altura de la cara superior de la barra en u.
func _top(u: float) -> float:
	return lerpf(low_end, high_end, u / length)


func _build() -> void:
	var hw := width * 0.5
	var side := color.darkened(0.2)
	var end_col := color.darkened(0.35)
	# Barra: caja inclinada (8 esquinas)
	var t0 := _top(0.0)
	var t1 := _top(length)
	var p := {
		"a0": Vector3(0.0, t0, -hw), "a1": Vector3(0.0, t0, hw),
		"b0": Vector3(length, t1, -hw), "b1": Vector3(length, t1, hw),
		"c0": Vector3(0.0, t0 - thickness, -hw), "c1": Vector3(0.0, t0 - thickness, hw),
		"d0": Vector3(length, t1 - thickness, -hw), "d1": Vector3(length, t1 - thickness, hw),
	}
	var mid := Vector3(length * 0.5, (t0 + t1) * 0.5 - thickness * 0.5, 0.0)
	_quad_out(p["a0"], p["b0"], p["b1"], p["a1"], mid, color)
	_quad_out(p["c0"], p["d0"], p["d1"], p["c1"], mid, side)
	_quad_out(p["a0"], p["b0"], p["d0"], p["c0"], mid, side)
	_quad_out(p["a1"], p["b1"], p["d1"], p["c1"], mid, side)
	_quad_out(p["a0"], p["a1"], p["c1"], p["c0"], mid, end_col)
	_quad_out(p["b0"], p["b1"], p["d1"], p["d0"], mid, end_col)
	# Arco semicircular bajo la barra, tangente a su cara inferior.
	var uc := length * arch_pos
	var r_out := maxf(_top(uc) - thickness, 0.05)
	var r_in := r_out * 0.62
	var center := Vector3(uc, 0.0, 0.0)
	for i in ARCH_SEGMENTS:
		var a0 := PI * float(i) / ARCH_SEGMENTS
		var a1 := PI * float(i + 1) / ARCH_SEGMENTS
		var o0 := Vector2(cos(a0), sin(a0))
		var o1 := Vector2(cos(a1), sin(a1))
		var out0 := Vector3(uc + o0.x * r_out, o0.y * r_out, 0.0)
		var out1 := Vector3(uc + o1.x * r_out, o1.y * r_out, 0.0)
		var in0 := Vector3(uc + o0.x * r_in, o0.y * r_in, 0.0)
		var in1 := Vector3(uc + o1.x * r_in, o1.y * r_in, 0.0)
		var za := Vector3(0.0, 0.0, -hw)
		var zb := Vector3(0.0, 0.0, hw)
		# Cara exterior (normal hacia fuera del centro)
		_quad_out(out0 + za, out1 + za, out1 + zb, out0 + zb, center, color)
		# Cara interior (normal hacia el centro): se pasa un punto del otro lado
		var ic := (in0 + in1) * 0.5
		_quad_out(in0 + za, in1 + za, in1 + zb, in0 + zb, ic * 2.0 - center, side)
		# Caras laterales del arco
		for sv in [-1.0, 1.0]:
			var z := Vector3(0.0, 0.0, hw * sv)
			_quad_out(in0 + z, in1 + z, out1 + z, out0 + z, (in0 + out1) * 0.5 - z, side)


func register(park: Object) -> void:
	park.rails.append({"a": _world(0.0, 0.0, low_end), "b": _world(length, 0.0, high_end),
		"kind": "ledge", "nomesh": true})

class_name Skatepark
extends Node3D
## Skatepark basado en el street course de Tampa (FSA-166, referencia de Adrien
## Guigues en ArtStation): quarter pipes en los extremos, banco largo con plataforma,
## funbox central con ledge, plataforma con escalera y barandillas, ledge largo,
## manual pad, flat rail y kicker. Al aire libre y en estilo low-poly minimalista
## (caras planas, paleta cálida de atardecer); el entorno está en Scenery.
##
## Toda la geometría son primitivas analíticas (caja, quarter pipe, banco, escalera).
## La misma definición da la altura del suelo para la física del skater (sample)
## y genera la malla, así lo que se ve es exactamente lo que se pisa.

const HALF_X := 28.0
const HALF_Z := 17.0
## Techo para la cámara (el park está al aire libre).
const WALL_H := 12.0
## Altura "infinita" fuera del park: el murete perimetral funciona como pared.
const OUT_H := 50.0
const NONE := Vector3(-1.0, 0.0, 0.0)

# Paleta de atardecer (low-poly)
const C_CONCRETE := Color(0.72, 0.66, 0.6)
const C_CONCRETE_DARK := Color(0.55, 0.5, 0.52)
const C_WOOD := Color(0.88, 0.6, 0.42)
const C_WOOD_SIDE := Color(0.58, 0.36, 0.36)
const C_SLATE := Color(0.38, 0.4, 0.58)
const C_MAUVE := Color(0.56, 0.38, 0.48)
const C_OCHRE := Color(0.92, 0.66, 0.3)
const C_CORAL := Color(0.86, 0.32, 0.28)
const C_METAL := Color(0.72, 0.7, 0.76)
const C_STEP := Color(0.68, 0.58, 0.56)
const C_NAVY := Color(0.22, 0.2, 0.32)

const PAINTED := preload("res://shaders/painted.gdshader")

var shapes: Array[Dictionary] = []
## Zonas grindables: {a: Vector3, b: Vector3, kind: "rail" | "ledge" | "coping"}.
## a y b son la línea sobre la que se apoya la tabla.
var rails: Array[Dictionary] = []
var spawn_pos := Vector3(-8.0, 0.0, -1.0)
var spawn_yaw := -PI * 0.5

var _st: SurfaceTool


func _ready() -> void:
	_define_layout()
	_build_meshes()


# ---------------------------------------------------------------- consulta

## Altura del suelo y su gradiente en (x, z): Vector3(h, dh/dx, dh/dz).
func sample(x: float, z: float) -> Vector3:
	if absf(x) > HALF_X or absf(z) > HALF_Z:
		return Vector3(OUT_H, 0.0, 0.0)
	var best := Vector3.ZERO
	for s in shapes:
		var r := _sample_shape(s, x, z)
		if r.x > best.x:
			best = r
	return best


func height_at(x: float, z: float) -> float:
	return sample(x, z).x


func _sample_shape(s: Dictionary, x: float, z: float) -> Vector3:
	var type: String = s["type"]
	if type == "box":
		var mn: Vector2 = s["min"]
		var mx: Vector2 = s["max"]
		if x >= mn.x and x <= mx.x and z >= mn.y and z <= mx.y:
			return Vector3(s["h"], 0.0, 0.0)
		return NONE
	var o: Vector2 = s["o"]
	var d: Vector2 = s["dir"]
	var dx := x - o.x
	var dz := z - o.y
	var u := dx * d.x + dz * d.y
	var v := -dx * d.y + dz * d.x
	var w: float = s["w"]
	var length: float = s["len"]
	if u < 0.0 or u > length or absf(v) > w * 0.5:
		return NONE
	var h := 0.0
	var du := 0.0
	match type:
		"qp":
			var r: float = s["r"]
			var ulip: float = s["ulip"]
			if u < ulip:
				var q := sqrt(maxf(r * r - u * u, 0.0001))
				h = r - q
				du = u / q
			else:
				h = s["h"]
		"bank":
			var bl: float = s["l"]
			var bh: float = s["h"]
			if u < bl:
				h = bh * u / bl
				du = bh / bl
			else:
				h = bh
		"stairs":
			var n: int = s["n"]
			var sl: float = s["l"] / float(n)
			var sh: float = s["h"]
			h = minf(floorf(u / sl) + 1.0, float(n)) * sh / float(n)
	return Vector3(h, du * d.x, du * d.y)


# ---------------------------------------------------------------- distribución

func _define_layout() -> void:
	# Quarter pipe grande en el lado oeste (con deck y coping).
	_qp(Vector2(-23.4, 0.0), Vector2(-1, 0), 28.0, 2.2, 1.6, C_SLATE)
	# Quarter pipe mediano en el lado este.
	_qp(Vector2(24.4, -3.0), Vector2(1, 0), 20.0, 1.6, 1.5, C_MAUVE)
	# Banco largo en el lado norte, con plataforma arriba.
	_bank(Vector2(2.0, -10.0), Vector2(0, -1), 32.0, 1.5, 3.5, 3.5, C_WOOD_SIDE)

	# Funbox central: pirámide con bancos a los cuatro lados y ledge encima.
	_box(Vector2(-4.0, -3.0), Vector2(4.0, 1.0), 0.9, C_WOOD, C_WOOD_SIDE)
	_bank(Vector2(0.0, 3.2), Vector2(0, -1), 8.0, 0.9, 2.2, 0.0, C_WOOD_SIDE)
	_bank(Vector2(0.0, -5.2), Vector2(0, 1), 8.0, 0.9, 2.2, 0.0, C_WOOD_SIDE)
	_bank(Vector2(6.2, -1.0), Vector2(-1, 0), 4.0, 0.9, 2.2, 0.0, C_WOOD_SIDE)
	_bank(Vector2(-6.2, -1.0), Vector2(1, 0), 4.0, 0.9, 2.2, 0.0, C_WOOD_SIDE)
	_ledge_box(Vector2(-3.0, -1.3), Vector2(3.0, -0.7), 1.3, C_CONCRETE_DARK)

	# Plataforma sur con escalera de 5 peldaños, dos barandillas y rampa de subida.
	_box(Vector2(-6.0, 11.0), Vector2(10.0, 17.0), 1.2, C_CONCRETE, C_CONCRETE_DARK, true)
	_stairs(Vector2(3.0, 8.5), Vector2(0, 1), 4.0, 1.2, 2.5, 5)
	for x in [1.4, 4.6]:
		_rail(Vector3(x, 1.84, 11.3), Vector3(x, 0.36, 8.2), "rail")
	_bank(Vector2(-3.5, 8.0), Vector2(0, 1), 5.0, 1.2, 3.0, 0.0, C_CONCRETE_DARK)
	_rail(Vector3(5.2, 1.2, 11.0), Vector3(10.0, 1.2, 11.0), "ledge")

	# Ledge largo (hubba plano) en el lado oeste.
	_ledge_box(Vector2(-18.0, 8.75), Vector2(-10.0, 9.25), 0.45, C_CONCRETE_DARK)
	# Manual pad.
	_ledge_box(Vector2(8.0, 2.0), Vector2(14.0, 5.0), 0.35, C_SLATE, C_CONCRETE)
	# Flat rail.
	_rail(Vector3(-13.0, 0.42, 4.0), Vector3(-5.0, 0.42, 4.0), "rail")
	# Kicker hacia el quarter grande.
	_bank(Vector2(-12.0, -6.0), Vector2(-1, 0), 3.0, 0.6, 1.3, 0.0, C_CORAL)
	# Banco a caja con ledge en el lado este.
	_bank(Vector2(14.0, 10.0), Vector2(1, 0), 4.0, 0.8, 2.0, 0.0, C_CONCRETE_DARK)
	_ledge_box(Vector2(16.0, 8.0), Vector2(20.0, 12.0), 0.8, C_MAUVE, C_CONCRETE, true)


func _qp(origin: Vector2, dir: Vector2, width: float, height: float, deck: float, side: Color) -> void:
	var a := deg_to_rad(75.0)
	var r := height / (1.0 - cos(a))
	var ulip := r * sin(a)
	var d := dir.normalized()
	shapes.append({"type": "qp", "o": origin, "dir": d, "w": width, "h": height,
		"r": r, "ulip": ulip, "len": ulip + deck, "side": side})
	var p := Vector2(-d.y, d.x)
	var lip := origin + d * ulip
	var c1 := lip + p * (width * 0.5 - 0.2)
	var c2 := lip - p * (width * 0.5 - 0.2)
	_rail(Vector3(c1.x, height + 0.02, c1.y), Vector3(c2.x, height + 0.02, c2.y), "coping")


func _bank(origin: Vector2, dir: Vector2, width: float, height: float, length: float, deck: float, side: Color) -> void:
	shapes.append({"type": "bank", "o": origin, "dir": dir.normalized(), "w": width, "h": height,
		"l": length, "len": length + deck, "side": side})


func _stairs(origin: Vector2, dir: Vector2, width: float, height: float, length: float, steps: int) -> void:
	shapes.append({"type": "stairs", "o": origin, "dir": dir.normalized(), "w": width, "h": height,
		"l": length, "len": length, "n": steps})


func _box(mn: Vector2, mx: Vector2, h: float, top: Color, side: Color, trim := false) -> void:
	shapes.append({"type": "box", "min": mn, "max": mx, "h": h, "top": top, "side": side, "trim": trim})


## Caja con el canto superior metálico, grindable por sus lados largos
## (o por los cuatro si all_sides).
func _ledge_box(mn: Vector2, mx: Vector2, h: float, side: Color, top := C_CONCRETE, all_sides := false) -> void:
	_box(mn, mx, h, top, side, true)
	var long_x := (mx.x - mn.x) >= (mx.y - mn.y)
	if long_x or all_sides:
		_rail(Vector3(mn.x, h, mn.y), Vector3(mx.x, h, mn.y), "ledge")
		_rail(Vector3(mn.x, h, mx.y), Vector3(mx.x, h, mx.y), "ledge")
	if not long_x or all_sides:
		_rail(Vector3(mn.x, h, mn.y), Vector3(mn.x, h, mx.y), "ledge")
		_rail(Vector3(mx.x, h, mn.y), Vector3(mx.x, h, mx.y), "ledge")


## Obstáculo sólido sin malla propia (mobiliario que dibuja StreetProps).
func add_solid(mn: Vector2, mx: Vector2, h: float) -> void:
	shapes.append({"type": "box", "min": mn, "max": mx, "h": h, "hidden": true})


func _rail(a: Vector3, b: Vector3, kind: String) -> void:
	rails.append({"a": a, "b": b, "kind": kind})


# ---------------------------------------------------------------- mallas

func _build_meshes() -> void:
	_begin()
	for s in shapes:
		match String(s["type"]):
			"box":
				_mesh_box(s)
			"qp":
				_mesh_qp(s)
			"bank":
				_mesh_bank(s)
			"stairs":
				_mesh_stairs(s)
	for r in rails:
		_mesh_rail(r)
	# Suelo de hormigón por losas (cada losa con un tono ligeramente distinto)
	var slab := 4.0
	var x := -HALF_X
	while x < HALF_X - 0.01:
		var z := -HALF_Z
		while z < HALF_Z - 0.01:
			var x1 := minf(x + slab, HALF_X)
			var z1 := minf(z + slab, HALF_Z)
			var tone := 0.96 + _hash2(x, z) * 0.06
			_quad(Vector3(x, 0.0, z), Vector3(x1, 0.0, z), Vector3(x1, 0.0, z1), Vector3(x, 0.0, z1), Vector3.UP, C_CONCRETE * tone)
			z += slab
		x += slab
	_perimeter()
	# Valla de madera sobre la plataforma norte
	for i in range(0, 17):
		var fx := -14.0 + i * 2.0
		_cuboid(Vector3(fx - 0.05, 1.5, -16.75), Vector3(fx + 0.05, 2.4, -16.65), C_WOOD_SIDE)
	_cuboid(Vector3(-14.0, 2.25, -16.78), Vector3(18.0, 2.35, -16.62), C_WOOD)
	_cuboid(Vector3(-14.0, 1.85, -16.78), Vector3(18.0, 1.92, -16.62), C_WOOD)
	_finish("Park")


## Murete de hormigón alrededor del park (es el límite físico).
func _perimeter() -> void:
	var h := 0.7
	var t := 0.35
	_cuboid(Vector3(-HALF_X - t, 0.0, -HALF_Z - t), Vector3(HALF_X + t, h, -HALF_Z), C_CONCRETE_DARK)
	_cuboid(Vector3(-HALF_X - t, 0.0, HALF_Z), Vector3(HALF_X + t, h, HALF_Z + t), C_CONCRETE_DARK)
	_cuboid(Vector3(-HALF_X - t, 0.0, -HALF_Z), Vector3(-HALF_X, h, HALF_Z), C_CONCRETE_DARK)
	_cuboid(Vector3(HALF_X, 0.0, -HALF_Z), Vector3(HALF_X + t, h, HALF_Z), C_CONCRETE_DARK)


func _begin() -> void:
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


func _finish(node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _st.commit()
	mi.material_override = lowpoly_material()
	mi.layers = 1 | 2 # capa 2: recibe grafitis (StreetProps)
	add_child(mi)
	return mi


static var _painted: ShaderMaterial


## Material común: color por vértice con textura de pintura a mano (painted.gdshader).
static func lowpoly_material() -> ShaderMaterial:
	if _painted == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.noise = noise
		tex.generate_mipmaps = true
		_painted = ShaderMaterial.new()
		_painted.shader = PAINTED
		_painted.set_shader_parameter("brush", tex)
	return _painted


## Triángulo de caras planas; corrige el orden para que la cara mire hacia n.
## Cada cara lleva un tono ligeramente distinto (el encanto del low-poly).
func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var cen := (a + b + c) / 3.0
	var cc := col * (0.97 + _hash2(cen.x + cen.y * 3.1, cen.z - cen.y * 1.7) * 0.06)
	cc.a = 1.0
	for p in [a, b, c]:
		_st.set_color(cc)
		_st.set_normal(n)
		_st.add_vertex(p)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(a, b, c, n, col)
	_tri(a, c, d, n, col)


static func _hash2(x: float, y: float) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)


func _cuboid(mn: Vector3, mx: Vector3, col: Color) -> void:
	var x0 := mn.x
	var x1 := mx.x
	var y0 := mn.y
	var y1 := mx.y
	var z0 := mn.z
	var z1 := mx.z
	_quad(Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.UP, col)
	_quad(Vector3(x0, y0, z0), Vector3(x1, y0, z0), Vector3(x1, y1, z0), Vector3(x0, y1, z0), Vector3.FORWARD, col)
	_quad(Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3.BACK, col)
	_quad(Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3.LEFT, col)
	_quad(Vector3(x1, y0, z0), Vector3(x1, y0, z1), Vector3(x1, y1, z1), Vector3(x1, y1, z0), Vector3.RIGHT, col)


## Barra prismática de 6 caras (rails, coping, postes).
func _bar(a: Vector3, b: Vector3, radius: float, col: Color, sides := 6) -> void:
	var axis := (b - a).normalized()
	var ref := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var x := axis.cross(ref).normalized()
	var y := axis.cross(x).normalized()
	for i in sides:
		var a0 := TAU * (i + 0.5) / sides
		var a1 := TAU * (i + 1.5) / sides
		var o0 := (x * cos(a0) + y * sin(a0)) * radius
		var o1 := (x * cos(a1) + y * sin(a1)) * radius
		var n := (o0 + o1).normalized()
		_quad(a + o0, b + o0, b + o1, a + o1, n, col)


func _wall_band(a: Vector3, b: Vector3, y0: float, y1: float, n: Vector3, col: Color) -> void:
	_quad(Vector3(a.x, y0, a.z), Vector3(b.x, y0, b.z), Vector3(b.x, y1, b.z), Vector3(a.x, y1, a.z), n, col)


## Punto en el sistema local (u a lo largo de dir, v lateral) de una primitiva orientada.
func _lp(s: Dictionary, u: float, v: float, y: float) -> Vector3:
	var o: Vector2 = s["o"]
	var d: Vector2 = s["dir"]
	return Vector3(o.x + u * d.x - v * d.y, y, o.y + u * d.y + v * d.x)


func _ld(s: Dictionary, u: float, v: float, y: float) -> Vector3:
	var d: Vector2 = s["dir"]
	return Vector3(u * d.x - v * d.y, y, u * d.y + v * d.x).normalized()


func _mesh_box(s: Dictionary) -> void:
	var mn: Vector2 = s["min"]
	var mx: Vector2 = s["max"]
	var h: float = s["h"]
	var top: Color = s["top"]
	var side: Color = s["side"]
	_quad(Vector3(mn.x, h, mn.y), Vector3(mx.x, h, mn.y), Vector3(mx.x, h, mx.y), Vector3(mn.x, h, mx.y), Vector3.UP, top)
	var corners := [Vector3(mn.x, 0, mn.y), Vector3(mx.x, 0, mn.y), Vector3(mx.x, 0, mx.y), Vector3(mn.x, 0, mx.y)]
	var normals := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	var trim_h := minf(0.06, h * 0.3) if bool(s["trim"]) else 0.0
	for i in 4:
		var a: Vector3 = corners[i]
		var b: Vector3 = corners[(i + 1) % 4]
		var n: Vector3 = normals[i]
		_wall_band(a, b, 0.0, h - trim_h, n, side)
		if trim_h > 0.0:
			_wall_band(a, b, h - trim_h, h, n, C_METAL)


func _mesh_qp(s: Dictionary) -> void:
	var w: float = s["w"]
	var h: float = s["h"]
	var r: float = s["r"]
	var ulip: float = s["ulip"]
	var length: float = s["len"]
	var side: Color = s["side"]
	var hw := w * 0.5
	# Pocas caras para que se vean las facetas de la curva
	var seg := 9
	var us: Array[float] = []
	var hs: Array[float] = []
	for i in seg + 1:
		var u := ulip * float(i) / float(seg)
		us.append(u)
		hs.append(r - sqrt(maxf(r * r - u * u, 0.0001)))
	var right := _ld(s, 0.0, 1.0, 0.0)
	for i in seg:
		var a := _lp(s, us[i], -hw, hs[i])
		var b := _lp(s, us[i + 1], -hw, hs[i + 1])
		var c := _lp(s, us[i + 1], hw, hs[i + 1])
		var d := _lp(s, us[i], hw, hs[i])
		var n := (b - a).cross(d - a).normalized()
		if n.y < 0.0:
			n = -n
		_quad(a, b, c, d, n, C_WOOD)
		for sv in [-1.0, 1.0]:
			var sn: Vector3 = right * sv
			_quad(_lp(s, us[i], hw * sv, 0.0), _lp(s, us[i + 1], hw * sv, 0.0),
				_lp(s, us[i + 1], hw * sv, hs[i + 1]), _lp(s, us[i], hw * sv, hs[i]), sn, side)
	_quad(_lp(s, ulip, -hw, h), _lp(s, length, -hw, h), _lp(s, length, hw, h), _lp(s, ulip, hw, h), Vector3.UP, C_WOOD)
	for sv in [-1.0, 1.0]:
		var sn: Vector3 = right * sv
		_quad(_lp(s, ulip, hw * sv, 0.0), _lp(s, length, hw * sv, 0.0), _lp(s, length, hw * sv, h), _lp(s, ulip, hw * sv, h), sn, side)
	var fwd := _ld(s, 1.0, 0.0, 0.0)
	_quad(_lp(s, length, -hw, 0.0), _lp(s, length, hw, 0.0), _lp(s, length, hw, h), _lp(s, length, -hw, h), fwd, side.darkened(0.15))


func _mesh_bank(s: Dictionary) -> void:
	var w: float = s["w"]
	var h: float = s["h"]
	var bl: float = s["l"]
	var length: float = s["len"]
	var side: Color = s["side"]
	var hw := w * 0.5
	var g := _ld(s, h / bl, 0.0, 0.0) * (h / bl)
	var n := Vector3(-g.x, 1.0, -g.z).normalized()
	var surf := C_CORAL.lightened(0.15) if side == C_CORAL else C_WOOD
	_quad(_lp(s, 0.0, -hw, 0.0), _lp(s, bl, -hw, h), _lp(s, bl, hw, h), _lp(s, 0.0, hw, 0.0), n, surf)
	var right := _ld(s, 0.0, 1.0, 0.0)
	var fwd := _ld(s, 1.0, 0.0, 0.0)
	for sv in [-1.0, 1.0]:
		var sn: Vector3 = right * sv
		var p0 := _lp(s, 0.0, hw * sv, 0.0)
		var p1 := _lp(s, bl, hw * sv, 0.0)
		var p2 := _lp(s, bl, hw * sv, h)
		_tri(p0, p1, p2, sn, side)
		if length > bl:
			_quad(p1, _lp(s, length, hw * sv, 0.0), _lp(s, length, hw * sv, h), p2, sn, side)
	if length > bl:
		_quad(_lp(s, bl, -hw, h), _lp(s, length, -hw, h), _lp(s, length, hw, h), _lp(s, bl, hw, h), Vector3.UP, C_WOOD)
	_quad(_lp(s, length, -hw, 0.0), _lp(s, length, hw, 0.0), _lp(s, length, hw, h), _lp(s, length, -hw, h), fwd, side.darkened(0.15))


func _mesh_stairs(s: Dictionary) -> void:
	var w: float = s["w"]
	var h: float = s["h"]
	var length: float = s["l"]
	var n: int = s["n"]
	var hw := w * 0.5
	var sl := length / float(n)
	var sh := h / float(n)
	var right := _ld(s, 0.0, 1.0, 0.0)
	var fwd := _ld(s, 1.0, 0.0, 0.0)
	for k in n:
		var u0 := k * sl
		var u1 := (k + 1) * sl
		var y0 := k * sh
		var y1 := (k + 1) * sh
		_quad(_lp(s, u0, -hw, y1), _lp(s, u1, -hw, y1), _lp(s, u1, hw, y1), _lp(s, u0, hw, y1), Vector3.UP, C_STEP)
		_quad(_lp(s, u0, -hw, y0), _lp(s, u0, hw, y0), _lp(s, u0, hw, y1), _lp(s, u0, -hw, y1), -fwd, C_CONCRETE_DARK)
		for sv in [-1.0, 1.0]:
			_quad(_lp(s, u0, hw * sv, 0.0), _lp(s, u1, hw * sv, 0.0), _lp(s, u1, hw * sv, y1), _lp(s, u0, hw * sv, y1), right * sv, C_CONCRETE_DARK)


func _mesh_rail(r: Dictionary) -> void:
	var kind: String = r["kind"]
	var a: Vector3 = r["a"]
	var b: Vector3 = r["b"]
	if kind == "ledge":
		return # el canto metálico ya lo dibuja la caja
	if kind == "coping":
		_bar(a + Vector3(0, -0.03, 0), b + Vector3(0, -0.03, 0), 0.045, C_METAL)
		return
	_bar(a + Vector3(0, -0.035, 0), b + Vector3(0, -0.035, 0), 0.04, C_CORAL)
	# Postes hasta el suelo cada ~2.5 m
	var length := a.distance_to(b)
	var count := maxi(2, int(ceil(length / 2.5)) + 1)
	for i in count:
		var t := lerpf(0.06, 0.94, float(i) / float(count - 1))
		var p := a.lerp(b, t)
		var ground := height_at(p.x, p.z)
		_bar(Vector3(p.x, ground, p.z), Vector3(p.x, p.y - 0.07, p.z), 0.035, C_NAVY, 4)

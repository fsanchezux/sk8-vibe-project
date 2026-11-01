class_name Scenery
extends Node3D
## Entorno del skatepark en estilo low-poly (como las referencias de Lonely Mountains,
## los dioramas de bosque, etc.): pradera ocre con relieve suave, bosque de pinos
## oscuros y árboles otoñales, rocas, montañas al fondo y farolas encendidas.
## Todo se genera con una semilla fija y va en una sola malla (una llamada de dibujo).

const C_GRASS := Color(0.8, 0.66, 0.3)
const C_GRASS_DARK := Color(0.56, 0.56, 0.3)
const C_PATH := Color(0.88, 0.62, 0.55)
const C_PINE := Color(0.25, 0.36, 0.38)
const C_PINE_LIGHT := Color(0.32, 0.45, 0.44)
const C_AUTUMN := Color(0.96, 0.55, 0.26)
const C_AUTUMN_RED := Color(0.86, 0.36, 0.25)
const C_TRUNK := Color(0.5, 0.27, 0.24)
const C_ROCK := Color(0.58, 0.48, 0.54)
const C_MOUNTAIN := Color(0.42, 0.44, 0.64)
const C_MOUNTAIN_SNOW := Color(0.95, 0.86, 0.85)
const C_LAMP := Color(0.24, 0.22, 0.3)

const TERRAIN_HALF := 120.0
const TERRAIN_STEP := 6.0

var _st: SurfaceTool
var _rng := RandomNumberGenerator.new()
var _noise := FastNoiseLite.new()


func _ready() -> void:
	_rng.seed = 2026
	_noise.seed = 11
	_noise.frequency = 0.012
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_terrain()
	_forest()
	_rocks()
	_mountains()
	_lamps()
	var mi := MeshInstance3D.new()
	mi.name = "Scenery"
	mi.mesh = _st.commit()
	mi.material_override = Skatepark.lowpoly_material()
	add_child(mi)
	build_bulbs()


## Altura del terreno fuera del park (0 junto al murete, sube suavemente lejos).
func ground_at(x: float, z: float) -> float:
	var dx := maxf(absf(x) - Skatepark.HALF_X - 2.0, 0.0)
	var dz := maxf(absf(z) - Skatepark.HALF_Z - 2.0, 0.0)
	var d := sqrt(dx * dx + dz * dz)
	var k := clampf(d / 25.0, 0.0, 1.0)
	return (_noise.get_noise_2d(x, z) * 6.0 + d * 0.06) * k - 0.02


func _in_park(x: float, z: float, margin: float) -> bool:
	return absf(x) < Skatepark.HALF_X + margin and absf(z) < Skatepark.HALF_Z + margin


# ---------------------------------------------------------------- terreno

func _terrain() -> void:
	var n := int(TERRAIN_HALF * 2.0 / TERRAIN_STEP)
	for i in n:
		for j in n:
			var x0 := -TERRAIN_HALF + i * TERRAIN_STEP
			var z0 := -TERRAIN_HALF + j * TERRAIN_STEP
			var x1 := x0 + TERRAIN_STEP
			var z1 := z0 + TERRAIN_STEP
			if _in_park(x0, z0, -0.5) and _in_park(x1, z1, -0.5):
				continue
			var a := Vector3(x0, ground_at(x0, z0), z0)
			var b := Vector3(x1, ground_at(x1, z0), z0)
			var c := Vector3(x1, ground_at(x1, z1), z1)
			var d := Vector3(x0, ground_at(x0, z1), z1)
			var col := C_GRASS.lerp(C_GRASS_DARK, clampf(_noise.get_noise_2d(x0 * 3.0, z0 * 3.0) + 0.5, 0.0, 1.0))
			_tri_auto(a, b, c, col)
			_tri_auto(a, c, d, col * 0.97)
	# Camino rosado que llega al park por el sur
	var z := Skatepark.HALF_Z + 0.4
	while z < TERRAIN_HALF:
		var wob := sin(z * 0.06) * 6.0
		var z2 := z + 4.0
		var wob2 := sin(z2 * 0.06) * 6.0
		var p0 := Vector3(wob - 1.6, ground_at(wob, z) + 0.05, z)
		var p1 := Vector3(wob + 1.6, ground_at(wob, z) + 0.05, z)
		var p2 := Vector3(wob2 + 1.6, ground_at(wob2, z2) + 0.05, z2)
		var p3 := Vector3(wob2 - 1.6, ground_at(wob2, z2) + 0.05, z2)
		_tri_auto(p0, p1, p2, C_PATH)
		_tri_auto(p0, p2, p3, C_PATH)
		z = z2


# ---------------------------------------------------------------- árboles

func _forest() -> void:
	# Pocos árboles sueltos en una pradera abierta (ambiente tranquilo, no un bosque)
	var placed := 0
	var tries := 0
	while placed < 110 and tries < 6000:
		tries += 1
		var x := _rng.randf_range(-95.0, 95.0)
		var z := _rng.randf_range(-80.0, 80.0)
		if _in_park(x, z, 4.0):
			continue
		if z > Skatepark.HALF_Z and absf(x - sin(z * 0.06) * 6.0) < 4.0:
			continue # deja libre el camino
		# Agrupados en bosquecillos (según el ruido) y con un claro alrededor del park
		var dist := Vector2(maxf(absf(x) - Skatepark.HALF_X, 0.0), maxf(absf(z) - Skatepark.HALF_Z, 0.0)).length()
		if _rng.randf() > clampf(dist / 20.0, 0.1, 1.0) or _noise.get_noise_2d(x * 1.7, z * 1.7) < 0.0:
			continue
		var base := Vector3(x, ground_at(x, z), z)
		var s := _rng.randf_range(0.8, 1.35)
		if _noise.get_noise_2d(x * 0.6, z * 0.6) > 0.05:
			_autumn_tree(base, s)
		else:
			_pine(base, s)
		placed += 1


func _pine(base: Vector3, s: float) -> void:
	var trunk_h := 1.2 * s
	_prism(base, base + Vector3(0, trunk_h, 0), 0.18 * s, 5, C_TRUNK)
	var col := C_PINE.lerp(C_PINE_LIGHT, _rng.randf())
	var y := trunk_h * 0.7
	var radius := 1.6 * s
	for k in 3:
		var h := (2.4 - k * 0.45) * s
		_cone(base + Vector3(0, y, 0), radius, h, 6, col, _rng.randf() * TAU)
		y += h * 0.5
		radius *= 0.72


func _autumn_tree(base: Vector3, s: float) -> void:
	var trunk_h := 1.6 * s
	_prism(base, base + Vector3(0, trunk_h, 0), 0.16 * s, 5, C_TRUNK)
	var col := C_AUTUMN.lerp(C_AUTUMN_RED, _rng.randf() * 0.7)
	# Copa en forma de cono alto (como los árboles naranjas de la referencia)
	_cone(base + Vector3(0, trunk_h * 0.6, 0), 1.25 * s, 4.2 * s, 5, col, _rng.randf() * TAU)


func _rocks() -> void:
	for i in 45:
		var x := _rng.randf_range(-70.0, 70.0)
		var z := _rng.randf_range(-60.0, 60.0)
		if _in_park(x, z, 1.5):
			continue
		var s := _rng.randf_range(0.4, 1.6)
		_rock(Vector3(x, ground_at(x, z) - 0.1 * s, z), s)


func _rock(c: Vector3, s: float) -> void:
	# Octaedro deformado: roca facetada
	var pts := [Vector3(0, 0.9, 0), Vector3(0, -0.2, 0), Vector3(1, 0.2, 0), Vector3(-1, 0.25, 0), Vector3(0, 0.15, 1), Vector3(0, 0.3, -1)]
	var v: Array[Vector3] = []
	for p in pts:
		var q: Vector3 = p
		v.append(c + Vector3(q.x * _rng.randf_range(0.7, 1.3), q.y * _rng.randf_range(0.7, 1.2), q.z * _rng.randf_range(0.7, 1.3)) * s)
	var faces := [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]
	var col := C_ROCK * _rng.randf_range(0.9, 1.08)
	for f in faces:
		_tri_out(v[f[0]], v[f[1]], v[f[2]], c, col)


func _mountains() -> void:
	# Anillo de montañas lejanas; la niebla las funde con el cielo.
	for i in 22:
		var ang := TAU * i / 22.0 + _rng.randf_range(-0.1, 0.1)
		var dist := _rng.randf_range(230.0, 300.0)
		var c := Vector3(cos(ang) * dist, -2.0, sin(ang) * dist)
		var h := _rng.randf_range(30.0, 62.0)
		var r := _rng.randf_range(45.0, 75.0)
		_cone(c, r, h, 5, C_MOUNTAIN * _rng.randf_range(0.9, 1.1), _rng.randf() * TAU)
		if h > 55.0:
			_cone(c + Vector3(0, h * 0.72, 0), r * 0.28, h * 0.28, 5, C_MOUNTAIN_SNOW, _rng.randf() * TAU)


func _lamps() -> void:
	# Farolas alrededor del park (la bombilla brilla con el glow del entorno)
	var spots := [Vector3(-29.5, 0, -10), Vector3(-29.5, 0, 10), Vector3(29.5, 0, -10), Vector3(29.5, 0, 10),
		Vector3(-12, 0, 18.5), Vector3(14, 0, 18.5), Vector3(-12, 0, -18.5), Vector3(14, 0, -18.5)]
	for p in spots:
		var base: Vector3 = p
		base.y = ground_at(base.x, base.z)
		_prism(base, base + Vector3(0, 4.2, 0), 0.08, 5, C_LAMP)
		_prism(base + Vector3(0, 4.15, 0), base + Vector3(0, 4.55, 0), 0.22, 5, C_LAMP)
		_lamp_bulb(base + Vector3(0, 3.95, 0))


var _bulbs: Array[Vector3] = []


func _lamp_bulb(p: Vector3) -> void:
	_bulbs.append(p)


## Bombillas emisivas (malla aparte con material sin sombreado).
func build_bulbs() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in _bulbs:
		var s := 0.2
		var pts := [p + Vector3(0, s, 0), p + Vector3(0, -s, 0), p + Vector3(s, 0, 0), p + Vector3(-s, 0, 0), p + Vector3(0, 0, s), p + Vector3(0, 0, -s)]
		for f in [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]:
			for idx in f:
				st.add_vertex(pts[idx])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.75, 0.45)
	mat.emission_energy_multiplier = 5.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	# Luz cálida de farola sobre el suelo (anochecer)
	for p in _bulbs:
		var light := OmniLight3D.new()
		light.position = p + Vector3(0, -0.15, 0)
		light.light_color = Color(1.0, 0.68, 0.42)
		light.light_energy = 1.8
		light.omni_range = 11.0
		light.omni_attenuation = 1.3
		add_child(light)


# ---------------------------------------------------------------- primitivas

func _cone(base: Vector3, radius: float, height: float, sides: int, col: Color, rot: float) -> void:
	var top := base + Vector3(0, height, 0)
	for i in sides:
		var a0 := rot + TAU * i / sides
		var a1 := rot + TAU * (i + 1) / sides
		var p0 := base + Vector3(cos(a0), 0, sin(a0)) * radius
		var p1 := base + Vector3(cos(a1), 0, sin(a1)) * radius
		_tri_out(p0, p1, top, base + Vector3(0, height * 0.3, 0), col)
		_tri_out(p0, p1, base, base + Vector3(0, height, 0), col * 0.8)


func _prism(a: Vector3, b: Vector3, radius: float, sides: int, col: Color) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var o0 := Vector3(cos(a0), 0, sin(a0)) * radius
		var o1 := Vector3(cos(a1), 0, sin(a1)) * radius
		var cen := (a + b) * 0.5
		_tri_out(a + o0, b + o0, b + o1, cen, col)
		_tri_out(a + o0, b + o1, a + o1, cen, col)


## Triángulo con normal de cara que apunta hacia fuera de `center`.
func _tri_out(a: Vector3, b: Vector3, c: Vector3, center: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		n = -n
	_emit(a, b, c, n, col)


## Triángulo de terreno con normal hacia arriba.
func _tri_auto(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var n := (b - a).cross(c - a).normalized()
	if n.y < 0.0:
		n = -n
	_emit(a, b, c, n, col)


func _emit(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Orden horario visto desde la normal (cara frontal en Godot)
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var cc := col
	cc.a = 1.0
	for p in [a, b, c]:
		_st.set_color(cc)
		_st.set_normal(n)
		_st.add_vertex(p)

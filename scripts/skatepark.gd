class_name Skatepark
extends Node3D
## Recorrido lineal de oeste a este que baja DECK_H en total:
##  - Antes, la carretera de bajada con curvas (DownhillRoad), que llega al roll-in.
##  - Oeste: roll-in de salida y deck alto.
##  - Tres carriles bajando del deck: 1 (norte) gap con launcher y rampa de caída,
##    2 (centro) un set de 15 escalones con hubba a cada lado y barandilla en medio,
##    3 (sur) bank de bajada, kicker y container con un cono encima.
##  - Este: los tres carriles acaban en una lanzadera enorme que te saca del mapa por
##    una abertura del murete (en el centro, antes, dos olas): al salir vuelves al
##    principio cayendo desde el aire, sin perder velocidad (EXIT_X).
## Al aire libre y en estilo low-poly minimalista (caras planas, paleta cálida de
## atardecer); el entorno está en Scenery.
##
## Toda la geometría son primitivas analíticas (caja, quarter pipe, banco, escalera).
## La misma definición da la altura del suelo para la física del skater (sample)
## y genera la malla, así lo que se ve es exactamente lo que se pisa.

const HALF_X := 28.0
const HALF_Z := 17.0
## Techo para la cámara (el park está al aire libre; la carretera llega a ~15 m).
const WALL_H := 30.0
## Altura del deck de salida sobre el fondo del park (un set de 15 escalones de 16 cm).
const DECK_H := 2.4
## Roll-in de entrada al park: altura sobre el deck y largo. Suave: la velocidad ya la
## trae la carretera.
const ROLL_IN_H := 0.9
const ROLL_IN_L := 3.0
## x donde acaba el deck de los carriles 1 y 3 (la escalera empieza en -13).
const LANE_START := -10.0
## Carril 1: césped entre el labio de la lanzadera y la rampa de recepción.
const GAP_LENGTH := 6.0
## Curva de lanzadera de los banks (1 = recto). Las de recepción del gap, más marcada.
const BANK_KICK := 1.3
const GAP_KICK := 1.8
## Carril 2: altura y ancho de las hubbas y altura de la barandilla sobre la línea de
## los escalones.
const HUBBA_H := 1.2
const HUBBA_W := 1.0
const RAIL_H := 1.1
## Carril 3: distancia del final del ledge al contenedor de basura.
const BIN_GAP := 3.5
## Rampa final del centro: largo y altura del canto (que acaba junto a la abertura).
const BIG_RAMP_L := 9.0
const BIG_RAMP_H := 4.0
## Olas del centro, justo antes de la rampa final. Largas para que con esta altura
## las pendientes no pasen de ~40°. La primera, más baja (WAVE_FIRST de la altura).
const WAVE_L := 18.0
const WAVE_H := 2.1
const WAVE_N := 2
const WAVE_FIRST := 2.0 / 3.0
## Carriles (z): 1 al norte, 2 en el centro, 3 al sur.
const LANE_Z := [-11.25, 0.0, 11.25]
const LANE_EDGE := 5.5
## Aberturas del murete este por las que se sale del mapa (media anchura en z): la del
## centro y las de los carriles 1 y 3, cada una con su lanzadera.
const EXIT_HALF_W := 4.5
const SIDE_EXIT_HALF_W := 4.75
## Al pasar de aquí en x se vuelve al principio del recorrido.
const EXIT_X := HALF_X + 1.5
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
const C_GRASS := Color(0.56, 0.6, 0.3)
const C_BUSH := Color(0.36, 0.52, 0.3)
const C_CONTAINER := Color(0.2, 0.38, 0.3)
const C_CONE := Color(1.0, 0.45, 0.15)

const PAINTED := preload("res://shaders/painted.gdshader")

var shapes: Array[Dictionary] = []
## Zonas grindables: {a: Vector3, b: Vector3, kind: "rail" | "ledge" | "coping"}.
## a y b son la línea sobre la que se apoya la tabla.
var rails: Array[Dictionary] = []
## Salida: arriba del roll-in, mirando al este (+x). La carretera la mueve a su inicio.
var spawn_pos := Vector3(-27.2, 0.0, 0.0)
var spawn_yaw := -PI * 0.5
## Carretera de bajada al oeste del park (fuera de HALF_X); su suelo lo da ella.
var road: DownhillRoad
## Física por capas (puente): las formas con "layer" solo existen para quien está a su
## altura o por encima. El skater pone aquí su altura en cada paso; INF = todo.
var probe_y := INF
## Decoración con malla propia (container, cono, matorrales y césped del gap).
var _containers: Array[Dictionary] = []
var _cones: Array[Vector3] = []
var _bushes: Array[Vector3] = []
var _grass: Array[Dictionary] = []
## Módulos colocados a mano en scenes/main.tscn (ver scripts/modules/park_module.gd).
## Hay que asignarlos antes de añadir el park al árbol.
var modules: Array[ParkModule] = []

var _st: SurfaceTool


func _ready() -> void:
	_define_layout()
	_build_meshes()


# ---------------------------------------------------------------- consulta

## Altura del suelo y su gradiente en (x, z): Vector3(h, dh/dx, dh/dz).
func sample(x: float, z: float) -> Vector3:
	var best := Vector3.ZERO
	if absf(x) > HALF_X or absf(z) > HALF_Z:
		if road and road.contains(x, z):
			best = road.ground(x, z)
		elif not in_exit(x, z):
			return Vector3(OUT_H, 0.0, 0.0)
	for s in shapes:
		if _hidden_layer(s):
			continue
		var r := _sample_shape(s, x, z)
		if r.x > best.x:
			best = r
	return best


func height_at(x: float, z: float) -> float:
	return sample(x, z).x


## Altura de un bank en u. k = 1 es recto; k > 1 curva hacia arriba al final como una
## lanzadera (más empinado arriba, suave abajo).
static func bank_height(bh: float, bl: float, k: float, u: float) -> float:
	return bh * pow(clampf(u / bl, 0.0, 1.0), k)


## Tipo de la superficie más alta en (x, z) ("qp", "wave", "bank"...; "" si es suelo).
func kind_at(x: float, z: float) -> String:
	var best := 0.0
	var kind := ""
	for s in shapes:
		if _hidden_layer(s):
			continue
		var r := _sample_shape(s, x, z)
		if r.x > best:
			best = r.x
			kind = s["type"]
	return kind


## Forma de una capa superior (tablero del puente) que no cuenta para quien va por debajo.
func _hidden_layer(s: Dictionary) -> bool:
	return s.has("layer") and probe_y < float(s["layer"]) - 0.3


## Césped de la carretera: frena (ver Skater.GRASS_SPEED).
func is_grass(x: float, z: float) -> bool:
	if absf(x) <= HALF_X or road == null or not road.contains(x, z):
		return false
	return kind_at(x, z) == "" and road.is_grass(x, z)


## Quarters, olas y rampas: ahí el skater hace pump al bajar (ver Skater.PUMP_ACCEL).
func is_pump_zone(x: float, z: float) -> bool:
	var kind := kind_at(x, z)
	return kind == "qp" or kind == "wave" or kind == "bank"


## Lanzaderas finales: subiéndolas no se frena y empujan (ver Skater.BOOST_SPEED).
func is_booster(x: float, z: float) -> bool:
	return x > HALF_X - 0.1 - BIG_RAMP_L and x <= HALF_X and exit_lane(z)


## ¿Está z frente a una de las aberturas del murete este (centro o carriles 1 y 3)?
static func exit_lane(z: float) -> bool:
	var side: float = LANE_Z[2]
	return absf(z) < EXIT_HALF_W or absf(absf(z) - side) < SIDE_EXIT_HALF_W


## Pasillo de salida tras la abertura del murete este (suelo a 0 hasta EXIT_X y algo más).
func in_exit(x: float, z: float) -> bool:
	return x > HALF_X and x < EXIT_X + 6.0 and exit_lane(z)


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
				var k: float = s.get("k", 1.0)
				h = bank_height(bh, bl, k, u)
				du = bh * k * pow(u / bl, k - 1.0) / bl
			else:
				h = bh
		"stairs":
			var n: int = s["n"]
			var sl: float = s["l"] / float(n)
			var sh: float = s["h"]
			h = minf(floorf(u / sl) + 1.0, float(n)) * sh / float(n)
		"slope":
			# Plano inclinado de h0 (u = 0) a h1 (u = len): hubbas.
			var h0: float = s["h0"]
			var h1: float = s["h1"]
			h = lerpf(h0, h1, u / length)
			du = (h1 - h0) / length
		"wave":
			# Crestas de coseno entre dos tramos planos (ParkWave).
			var flat: float = s["flat"]
			var t := u - flat
			var lw := length - 2.0 * flat
			if t > 0.0 and t < lw:
				var k := TAU * float(s["n"]) / lw
				var ch: float = s["h"]
				if t < lw / float(s["n"]):
					ch *= float(s.get("first", 1.0))
				h = ch * 0.5 * (1.0 - cos(k * t))
				du = ch * 0.5 * k * sin(k * t)
	# y0: altura de la base (piezas encima del deck o de un rellano)
	return Vector3(h + float(s.get("y0", 0.0)), du * d.x, du * d.y)


# ---------------------------------------------------------------- distribución

func _define_layout() -> void:
	var z1: float = LANE_Z[0]
	var z3: float = LANE_Z[2]
	var e := LANE_EDGE

	# Oeste: roll-in de salida a lo ancho de todo el park (para elegir carril bajando)
	# y deck alto. La escalera empieza en x = -13; los carriles 1 y 3, en LANE_START,
	# un poco más tarde, para que dé tiempo a colocarse.
	_box(Vector2(-28.0, -17.0), Vector2(-13.0, 17.0), DECK_H, C_CONCRETE, C_CONCRETE_DARK, true)
	_box(Vector2(-13.0, -17.0), Vector2(LANE_START, -e), DECK_H, C_CONCRETE, C_CONCRETE_DARK, true)
	_box(Vector2(-13.0, e), Vector2(LANE_START, 17.0), DECK_H, C_CONCRETE, C_CONCRETE_DARK, true)
	_bank(Vector2(-26.5 + ROLL_IN_L, 0.0), Vector2(-1, 0), 34.0, ROLL_IN_H, ROLL_IN_L, 1.5, C_WOOD_SIDE, DECK_H)

	# Carril 1 (norte): lanzadera larga al borde del deck, hueco de césped a ras de suelo
	# y rampa de recepción donde acaba el césped. Si te quedas corto caes al césped, que
	# da al final de la escalera, y sales por ahí.
	_add_module(_wedge(4.5, 1.0, 8.0), Vector3(LANE_START - 4.5, DECK_H, z1))
	var land_top := LANE_START + GAP_LENGTH
	_grass.append({"min": Vector2(LANE_START, -17.0), "max": Vector2(land_top, -e)})
	# La recepción también es lanzadera (perfil curvo): al hacer el recorrido a la
	# inversa te lanza por encima del césped hacia la lanzadera del deck.
	_bank(Vector2(land_top + 8.5, z1), Vector2(-1, 0), 17.0 - e, 2.0, 8.0, 0.5, C_SLATE, 0.0, GAP_KICK)
	for p in [Vector2(-8.6, -13.0), Vector2(-6.4, -9.5), Vector2(-7.6, -15.2), Vector2(-5.2, -12.0)]:
		_bushes.append(Vector3(p.x, 0.0, p.y))

	# Carril 2 (centro): un set de 15 escalones (DECK_H) con hubba a cada lado y
	# barandilla en medio.
	var stair_w := 2.0 * (e - HUBBA_W)
	_stairs(Vector2(-8.5, 0.0), Vector2(-1, 0), stair_w, DECK_H, 4.5, 15)
	# Altas para que al saltar desde el deck la tabla baje hasta ellas y enganche el grind.
	for sz in [-1.0, 1.0]:
		_hubba(Vector2(-13.0, sz * (e - HUBBA_W * 0.5)), 4.5, DECK_H + HUBBA_H, HUBBA_H)
	_rail(Vector3(-12.8, DECK_H - 0.1 + RAIL_H, 0.0), Vector3(-8.7, 0.16 + RAIL_H, 0.0), "rail")

	# Carril 3 (sur): bank de bajada del deck y ledge sobre arco que hace de lanzadera
	# (se sube rodando o grindando) para saltar un contenedor de basura con un cono
	# encima, a BIN_GAP del final del ledge: hace falta un buen ollie. Tocar el cono es
	# caer; el contenedor se puede pisar.
	_bank(Vector2(LANE_START + 7.0, z3), Vector2(-1, 0), 17.0 - e, DECK_H, 7.0, 0.0, C_WOOD_SIDE)
	var ledge := ParkArchLedge.new()
	ledge.length = 4.0
	ledge.width = 1.6
	ledge.high_end = 0.9
	_add_module(ledge, Vector3(1.0, 0.0, z3))
	var bin_x := 1.0 + ledge.length + BIN_GAP
	_container(Vector2(bin_x, z3 - 1.0), Vector2(bin_x + 1.2, z3 + 1.0), 1.2)
	_cone_on(Vector3(bin_x + 0.6, 1.2, z3))

	# Este: los tres carriles acaban en una lanzadera enorme que llega a su abertura del
	# murete y te lanza fuera del mapa (subirla no frena, ver is_booster).
	for lz in [z1, z3]:
		_add_module(_wedge(BIG_RAMP_L, BIG_RAMP_H, 2.0 * SIDE_EXIT_HALF_W), Vector3(HALF_X - 0.1 - BIG_RAMP_L, 0.0, lz))
	# En el centro, antes de la lanzadera, las olas.
	var wave := ParkWave.new()
	wave.length = WAVE_L
	wave.crest_height = WAVE_H
	wave.crests = WAVE_N
	wave.first_scale = WAVE_FIRST
	wave.width = 2.0 * EXIT_HALF_W
	_add_module(wave, Vector3(HALF_X - 0.1 - BIG_RAMP_L - WAVE_L, 0.0, 0.0))
	_add_module(_wedge(BIG_RAMP_L, BIG_RAMP_H, 2.0 * EXIT_HALF_W), Vector3(HALF_X - 0.1 - BIG_RAMP_L, 0.0, 0.0))

	# Carretera de bajada con curvas al oeste: empieza ahí y llega al roll-in.
	road = DownhillRoad.new()
	_add_module(road, Vector3.ZERO)

	# Módulos colocados a mano en el editor (ParkModule): suman su física y rails.
	for m in modules:
		m.register(self)


func _wedge(length: float, height: float, width: float) -> ParkWedge:
	var w := ParkWedge.new()
	w.length = length
	w.height = height
	w.width = width
	return w


## Añade un módulo del layout como hijo del park y registra su física.
func _add_module(m: ParkModule, pos: Vector3) -> void:
	m.position = pos
	add_child(m)
	m.register(self)


## Hubba: ledge inclinado junto a una escalera, de h0 a h1 a lo largo de +x.
func _hubba(start: Vector2, length: float, h0: float, h1: float) -> void:
	shapes.append({"type": "slope", "o": start, "dir": Vector2(1, 0), "w": HUBBA_W, "len": length,
		"h0": h0, "h1": h1})
	_rail(Vector3(start.x, h0, start.y), Vector3(start.x + length, h1, start.y), "ledge")


func _container(mn: Vector2, mx: Vector2, h: float) -> void:
	shapes.append({"type": "box", "min": mn, "max": mx, "h": h, "nomesh": true})
	_containers.append({"min": mn, "max": mx, "h": h})


## Cono sólido sobre una superficie: chocar con él es como chocar con una pared.
func _cone_on(base: Vector3) -> void:
	shapes.append({"type": "box", "min": Vector2(base.x - 0.2, base.z - 0.2),
		"max": Vector2(base.x + 0.2, base.z + 0.2), "h": base.y + 0.7, "nomesh": true})
	_cones.append(base)


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


func _bank(origin: Vector2, dir: Vector2, width: float, height: float, length: float, deck: float, side: Color, y0 := 0.0, kick := BANK_KICK) -> void:
	shapes.append({"type": "bank", "o": origin, "dir": dir.normalized(), "w": width, "h": height,
		"l": length, "len": length + deck, "side": side, "y0": y0, "k": kick})


func _stairs(origin: Vector2, dir: Vector2, width: float, height: float, length: float, steps: int, y0 := 0.0) -> void:
	shapes.append({"type": "stairs", "o": origin, "dir": dir.normalized(), "w": width, "h": height,
		"l": length, "len": length, "n": steps, "y0": y0})


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
		if s.get("nomesh", false):
			continue # el módulo dibuja su propia malla
		match String(s["type"]):
			"box":
				_mesh_box(s)
			"qp":
				_mesh_qp(s)
			"bank":
				_mesh_bank(s)
			"stairs":
				_mesh_stairs(s)
			"slope":
				_mesh_slope(s)
	for c in _containers:
		_mesh_container(c)
	for c in _cones:
		_mesh_cone(c)
	for b in _bushes:
		_mesh_bush(b)
	for g in _grass:
		var mn: Vector2 = g["min"]
		var mx: Vector2 = g["max"]
		_quad(Vector3(mn.x, 0.01, mn.y), Vector3(mx.x, 0.01, mn.y), Vector3(mx.x, 0.01, mx.y),
			Vector3(mn.x, 0.01, mx.y), Vector3.UP, C_GRASS)
	for r in rails:
		if not r.get("nomesh", false):
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
	_finish("Park")


## Murete de hormigón alrededor del park (es el límite físico). Sigue la altura del
## suelo de dentro (en el deck sobresale lo mismo) y deja la abertura de salida al este.
func _perimeter() -> void:
	var t := 0.35
	var step := 1.0
	var x := -HALF_X - t
	while x < HALF_X + t - 0.01:
		var x1 := minf(x + step, HALF_X + t)
		var xm := clampf((x + x1) * 0.5, -HALF_X + 0.2, HALF_X - 0.2)
		_cuboid(Vector3(x, 0.0, -HALF_Z - t), Vector3(x1, _wall_top(xm, -HALF_Z + 0.2), -HALF_Z), C_CONCRETE_DARK)
		_cuboid(Vector3(x, 0.0, HALF_Z), Vector3(x1, _wall_top(xm, HALF_Z - 0.2), HALF_Z + t), C_CONCRETE_DARK)
		x = x1
	var z := -HALF_Z
	while z < HALF_Z - 0.01:
		var z1 := minf(z + step, HALF_Z)
		var zm := (z + z1) * 0.5
		if road == null or zm < road.open_z0 or zm > road.open_z1:
			_cuboid(Vector3(-HALF_X - t, 0.0, z), Vector3(-HALF_X, _wall_top(-HALF_X + 0.2, zm), z1), C_CONCRETE_DARK)
		if not exit_lane(zm):
			_cuboid(Vector3(HALF_X, 0.0, z), Vector3(HALF_X + t, _wall_top(HALF_X - 0.2, zm), z1), C_CONCRETE_DARK)
		z = z1


func _wall_top(x: float, z: float) -> float:
	return height_at(x, z) + 0.7


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
	return Vector3(o.x + u * d.x - v * d.y, y + float(s.get("y0", 0.0)), o.y + u * d.y + v * d.x)


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
	var k: float = s.get("k", 1.0)
	var hw := w * 0.5
	# skirt: los laterales bajan más allá de la base (rampas sobre la ladera de la carretera)
	var b0 := -float(s.get("skirt", 0.0))
	var surf := C_CORAL.lightened(0.15) if side == C_CORAL else C_WOOD
	var right := _ld(s, 0.0, 1.0, 0.0)
	var fwd := _ld(s, 1.0, 0.0, 0.0)
	# Pocas caras para que se vean las facetas de la curva de lanzadera
	var seg := 1 if is_equal_approx(k, 1.0) else 8
	for i in seg:
		var u0 := bl * float(i) / seg
		var u1 := bl * float(i + 1) / seg
		var y0 := bank_height(h, bl, k, u0)
		var y1 := bank_height(h, bl, k, u1)
		var a := _lp(s, u0, -hw, y0)
		var b := _lp(s, u1, -hw, y1)
		var d := _lp(s, u0, hw, y0)
		var n := (b - a).cross(d - a).normalized()
		if n.y < 0.0:
			n = -n
		_quad(a, b, _lp(s, u1, hw, y1), d, n, surf)
		for sv in [-1.0, 1.0]:
			_quad(_lp(s, u0, hw * sv, b0), _lp(s, u1, hw * sv, b0), _lp(s, u1, hw * sv, y1),
				_lp(s, u0, hw * sv, y0), right * sv, side)
	for sv in [-1.0, 1.0]:
		var sn: Vector3 = right * sv
		var p1 := _lp(s, bl, hw * sv, b0)
		var p2 := _lp(s, bl, hw * sv, h)
		if length > bl:
			_quad(p1, _lp(s, length, hw * sv, b0), _lp(s, length, hw * sv, h), p2, sn, side)
	if length > bl:
		_quad(_lp(s, bl, -hw, h), _lp(s, length, -hw, h), _lp(s, length, hw, h), _lp(s, bl, hw, h), Vector3.UP, C_WOOD)
	_quad(_lp(s, length, -hw, b0), _lp(s, length, hw, b0), _lp(s, length, hw, h), _lp(s, length, -hw, h), fwd, side.darkened(0.15))


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


## Hubba: bloque con la cara de arriba inclinada y paredes hasta el suelo.
func _mesh_slope(s: Dictionary) -> void:
	var w: float = s["w"]
	var length: float = s["len"]
	var h0: float = s["h0"]
	var h1: float = s["h1"]
	var hw := w * 0.5
	var right := _ld(s, 0.0, 1.0, 0.0)
	var fwd := _ld(s, 1.0, 0.0, 0.0)
	var n := (_lp(s, length, -hw, h1) - _lp(s, 0.0, -hw, h0)).cross(right).normalized()
	if n.y < 0.0:
		n = -n
	_quad(_lp(s, 0.0, -hw, h0), _lp(s, length, -hw, h1), _lp(s, length, hw, h1), _lp(s, 0.0, hw, h0), n, C_CONCRETE)
	for sv in [-1.0, 1.0]:
		_quad(_lp(s, 0.0, hw * sv, 0.0), _lp(s, length, hw * sv, 0.0), _lp(s, length, hw * sv, h1),
			_lp(s, 0.0, hw * sv, h0), right * sv, C_CONCRETE_DARK)
		# canto metálico a lo largo de la arista superior
		var mv: float = (hw + 0.01) * sv
		_quad(_lp(s, 0.0, mv, h0 - 0.05), _lp(s, length, mv, h1 - 0.05), _lp(s, length, mv, h1),
			_lp(s, 0.0, mv, h0), right * sv, C_METAL)
	_quad(_lp(s, 0.0, -hw, 0.0), _lp(s, 0.0, hw, 0.0), _lp(s, 0.0, hw, h0), _lp(s, 0.0, -hw, h0), -fwd, C_CONCRETE_DARK)
	_quad(_lp(s, length, -hw, 0.0), _lp(s, length, hw, 0.0), _lp(s, length, hw, h1), _lp(s, length, -hw, h1), fwd, C_CONCRETE_DARK)


## Container de obra: caja verde con nervios verticales en los lados.
func _mesh_container(c: Dictionary) -> void:
	var mn: Vector2 = c["min"]
	var mx: Vector2 = c["max"]
	var h: float = c["h"]
	_cuboid(Vector3(mn.x, 0.0, mn.y), Vector3(mx.x, h, mx.y), C_CONTAINER)
	var rib := C_CONTAINER.darkened(0.25)
	var z := mn.y + 0.3
	while z < mx.y - 0.2:
		_cuboid(Vector3(mn.x - 0.03, 0.05, z), Vector3(mn.x, h - 0.05, z + 0.12), rib)
		_cuboid(Vector3(mx.x, 0.05, z), Vector3(mx.x + 0.03, h - 0.05, z + 0.12), rib)
		z += 0.5
	_cuboid(Vector3(mn.x - 0.04, h - 0.1, mn.y - 0.04), Vector3(mx.x + 0.04, h, mx.y + 0.04), rib)


## Cono de tráfico (6 caras) con banda blanca.
func _mesh_cone(base: Vector3) -> void:
	_cuboid(base + Vector3(-0.22, 0.0, -0.22), base + Vector3(0.22, 0.04, 0.22), C_CONE.darkened(0.2))
	var sides := 6
	# [altura inicial, altura final, color]; el radio se estrecha hacia arriba
	var bands := [[0.04, 0.3, C_CONE], [0.3, 0.42, Color(0.95, 0.93, 0.9)], [0.42, 0.7, C_CONE]]
	for b in bands:
		var y0: float = b[0]
		var y1: float = b[1]
		var r0: float = 0.17 - (y0 - 0.04) * 0.22
		var r1: float = 0.17 - (y1 - 0.04) * 0.22
		var col: Color = b[2]
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var p0 := base + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p1 := base + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p2 := base + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var p3 := base + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var n := Vector3(cos((a0 + a1) * 0.5), 0.3, sin((a0 + a1) * 0.5)).normalized()
			_quad(p0, p1, p2, p3, n, col)


## Matorral low-poly (octaedro aplastado), sin física.
func _mesh_bush(c: Vector3) -> void:
	var r := 0.7 + _hash2(c.x, c.z) * 0.4
	var top := c + Vector3(0, r * 1.1, 0)
	var ring: Array[Vector3] = []
	for i in 5:
		var a := TAU * i / 5.0 + c.x
		ring.append(c + Vector3(cos(a) * r, r * 0.35, sin(a) * r))
	for i in 5:
		var p0 := ring[i]
		var p1 := ring[(i + 1) % 5]
		var mid := (p0 + p1) * 0.5
		_tri(top, p0, p1, ((mid - c).normalized() + Vector3.UP * 0.6).normalized(), C_BUSH)
		_tri(c, p0, p1, ((mid - c).normalized() - Vector3.UP * 0.2).normalized(), C_BUSH.darkened(0.2))


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

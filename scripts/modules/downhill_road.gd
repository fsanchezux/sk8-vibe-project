class_name DownhillRoad
extends ParkModule
## Carretera de bajada con curvas que lleva al roll-in del park (al oeste). Es donde se
## empieza siempre y adonde se vuelve al salir del mapa por la rampa final.
##
## Vista desde arriba: tramos rectos norte-sur unidos por curvas de 180° (serpentina)
## y, al final, una curva de 90° que entra recta al roll-in. Una línea recta de atajos
## (z = SHORT_Z) la cruza de oeste a este:
##  1. y 2. Kicker al salir de un tramo, hueco de césped y rampa de recepción en el
##     tramo siguiente: te saltas la curva.
##  3. Puente: rampa de subida, tablero por encima del tramo siguiente (si vas por la
##     carretera pasas por debajo) y una rampa larga de bajada hasta el roll-in.
## A los lados, césped liso un poco más bajo que el asfalto: se puede rodar por él, pero
## vas a la mitad de velocidad (Skater.GRASS_SPEED).
## Todas las rampas tienen algo de curva de lanzadera al final; los kickers, más.
##
## La física es la misma que la del park: Skatepark.sample() pide la altura a ground()
## fuera del park; las rampas y el puente son formas normales del park (register).

## Radio de las curvas (por el centro de la carretera) y media anchura del asfalto.
const R := 8.0
const RH := 3.0
## Los tramos rectos van de z = -LEG_Z a z = LEG_Z; el primero empieza en START_Z.
const LEG_Z := 12.0
const START_Z := -20.0
const LEGS := 5
## Pendiente de la carretera (3,5 %): da velocidad sin pasarse en las curvas.
const GRADE := 0.035
## Recta final hasta el murete del park (x = -Skatepark.HALF_X), en z = 0.
const FINAL := 6.0
## Línea de los atajos y ancho de sus rampas.
const SHORT_Z := 6.0
const RAMP_W := 4.0
## Curva de lanzadera de los kickers de los atajos (las demás rampas usan BANK_KICK).
const KICKER_KICK := 1.7
## Altura libre bajo el tablero del puente.
const BRIDGE_CLEAR := 2.6
## El césped queda un poco por debajo del asfalto.
const GRASS_DROP := 0.1
## Margen de césped alrededor de la carretera hasta el borde de la zona.
const MARGIN := 3.0

const C_ASPHALT := Color(0.33, 0.31, 0.36)
const C_CURB := Color(0.5, 0.46, 0.5)
const C_LINE := Color(0.95, 0.92, 0.86)
const C_GRASS := Color(0.56, 0.6, 0.3)
const C_GRASS_DARK := Color(0.48, 0.55, 0.3)
const C_CLIFF := Color(0.58, 0.48, 0.54)
const C_BRIDGE := Color(0.72, 0.66, 0.6)
const C_RAIL := Color(0.86, 0.32, 0.28)

## Tramos de la carretera: {type: "line", a, b} o {type: "arc", c, t0, t1}, con s0
## (distancia desde la salida) y len.
var pieces: Array[Dictionary] = []
var total := 0.0
## Zona que ocupa (rectángulo en x/z).
var x_min := 0.0
var z_half := 0.0
## Salida: arriba del primer tramo, mirando al sur (+z).
var start_pos := Vector3.ZERO
var start_yaw := PI
## Abertura del murete oeste del park por la que entra la carretera (y el puente).
var open_z0 := 0.0
var open_z1 := 0.0

var _leg_x: Array[float] = []
var _deck := {}
## Caja de cada tramo (para descartar rápido los lejanos) y última consulta (la física
## pide varias veces el mismo punto en cada paso).
var _boxes: Array[Rect2] = []
var _memo_p := Vector2(INF, INF)
var _memo := {}


func _init() -> void:
	_layout()


## Altura de la carretera en el punto s (baja con GRADE hasta el roll-in).
func height_at_s(s: float) -> float:
	return Skatepark.DECK_H + Skatepark.ROLL_IN_H + GRADE * (total - s)


## ¿Cae (x, z) dentro de la zona de la carretera? Fuera es pared (Skatepark.OUT_H).
func contains(x: float, z: float) -> bool:
	if x < x_min or x > -Skatepark.HALF_X or absf(z) > z_half:
		return false
	# El murete oeste del park, salvo en la abertura
	if x > -Skatepark.HALF_X - 0.35 and absf(z) <= Skatepark.HALF_Z and (z < open_z0 or z > open_z1):
		return false
	return true


## Suelo en (x, z): Vector3(h, dh/dx, dh/dz). El asfalto es plano de lado a lado; el
## césped interpola entre los tramos cercanos y queda GRASS_DROP más bajo.
func ground(x: float, z: float) -> Vector3:
	var c := _closest_all(Vector2(x, z))
	if c["d"] <= RH:
		var t: Vector2 = c["t"]
		return Vector3(height_at_s(c["s"]), -GRADE * t.x, -GRADE * t.y)
	var e := 0.25
	var h: float = c["grass"]
	return Vector3(h, (_grass_h(x + e, z) - h) / e, (_grass_h(x, z + e) - h) / e)


## ¿Cae (x, z) sobre la zona de la carretera (con margen)? Para que el entorno (Scenery)
## no ponga árboles ni rocas dentro. Mismas cuentas que _layout.
static func covers(x: float, z: float, margin: float) -> bool:
	var x0 := -Skatepark.HALF_X - FINAL - R - 2.0 * R * (LEGS - 1) - RH - MARGIN
	return x > x0 - margin and x < -Skatepark.HALF_X + margin and absf(z) < LEG_Z + R + RH + MARGIN + margin


func is_grass(x: float, z: float) -> bool:
	return _closest_all(Vector2(x, z))["d"] > RH


# ---------------------------------------------------------------- trazado

func _layout() -> void:
	# Tramos en x, del primero (oeste) al último (que gira hacia el park)
	var x_last := -Skatepark.HALF_X - FINAL - R
	for k in LEGS:
		_leg_x.append(x_last - 2.0 * R * (LEGS - 1 - k))
	var z := START_Z
	for k in LEGS - 1:
		var x := _leg_x[k]
		var south := k % 2 == 0
		var z_end := LEG_Z if south else -LEG_Z
		_line(Vector2(x, z), Vector2(x, z_end))
		# Curva de 180° hasta el tramo siguiente (por el sur o por el norte)
		var c := Vector2(x + R, z_end)
		if south:
			_arc(c, PI, 0.0)
		else:
			_arc(c, PI, TAU)
		z = z_end
	# Último tramo: baja hacia el sur y gira 90° hacia el este, al park
	var xl := _leg_x[LEGS - 1]
	_line(Vector2(xl, -LEG_Z), Vector2(xl, -R))
	_arc(Vector2(xl + R, -R), PI, PI * 0.5)
	_line(Vector2(xl + R, 0.0), Vector2(-Skatepark.HALF_X, 0.0))

	x_min = _leg_x[0] - RH - MARGIN
	z_half = LEG_Z + R + RH + MARGIN
	start_pos = Vector3(_leg_x[0], 0.0, START_Z + 1.0)
	open_z0 = -RH
	open_z1 = SHORT_Z + RAMP_W * 0.5
	# Tablero del puente: sobre el tramo 3, con BRIDGE_CLEAR de altura libre.
	var x3 := _leg_x[3]
	_deck = {"x0": x3 - RH - 1.0, "x1": x3 + RH + 1.0, "z0": SHORT_Z - RAMP_W * 0.5,
		"z1": SHORT_Z + RAMP_W * 0.5, "h": height_at_s(_cross_s(3)) + BRIDGE_CLEAR}


func _line(a: Vector2, b: Vector2) -> void:
	var l := a.distance_to(b)
	pieces.append({"type": "line", "a": a, "b": b, "s0": total, "len": l})
	_boxes.append(Rect2(a, Vector2.ZERO).expand(b))
	total += l


## Arco de centro c desde el ángulo t0 hasta t1 (punto = c + R·(cos t, sin t)).
func _arc(c: Vector2, t0: float, t1: float) -> void:
	var l := R * absf(t1 - t0)
	pieces.append({"type": "arc", "c": c, "t0": t0, "t1": t1, "s0": total, "len": l})
	_boxes.append(Rect2(c - Vector2(R, R), Vector2(R, R) * 2.0))
	total += l


## Punto de la carretera más cercano a p dentro de un tramo: [distancia, s, tangente
## (sentido de bajada), peso]. El peso (0..1) es cuánto cuenta el tramo para la altura
## del césped: un arco deja de contar fuera de su ángulo y cerca de su centro, donde
## el punto más cercano salta de un lado a otro (si no, el césped tendría escalones).
func _closest(pc: Dictionary, p: Vector2) -> Array:
	var s0: float = pc["s0"]
	var l: float = pc["len"]
	if pc["type"] == "line":
		var a: Vector2 = pc["a"]
		var b: Vector2 = pc["b"]
		var t := (b - a) / l
		var u := clampf((p - a).dot(t), 0.0, l)
		return [p.distance_to(a + t * u), s0 + u, t, 1.0]
	var c: Vector2 = pc["c"]
	var t0: float = pc["t0"]
	var t1: float = pc["t1"]
	var dir := signf(t1 - t0)
	var span := absf(t1 - t0)
	var local := fposmod((atan2(p.y - c.y, p.x - c.x) - t0) * dir, TAU)
	var weight := clampf(p.distance_to(c) / (R * 0.6), 0.0, 1.0)
	weight *= weight
	if local > span:
		var past := minf(local - span, TAU - local)
		weight *= clampf(1.0 - past / 0.5, 0.0, 1.0)
		local = span if local - span < TAU - local else 0.0
	var th := t0 + dir * local
	var q := c + Vector2(cos(th), sin(th)) * R
	var tan := Vector2(-sin(th), cos(th)) * dir
	return [p.distance_to(q), s0 + R * local, tan, weight]


## Tramo más cercano y altura del césped (media ponderada por cercanía de las alturas
## de la carretera, así entre dos tramos el césped hace de ladera).
## Los tramos a más de FAR_FADE dejan de contar poco a poco (y a más de FAR_CULL ni se
## miran): cualquier punto de la zona tiene un tramo a menos de ~25 m.
const FAR_FADE := 22.0
const FAR_CULL := 32.0


func _closest_all(p: Vector2) -> Dictionary:
	if p == _memo_p:
		return _memo
	var best_d := INF
	var best_s := 0.0
	var best_t := Vector2.RIGHT
	var wsum := 0.0
	var hsum := 0.0
	for i in pieces.size():
		var box := _boxes[i]
		var out := Vector2(maxf(maxf(box.position.x - p.x, p.x - box.end.x), 0.0),
			maxf(maxf(box.position.y - p.y, p.y - box.end.y), 0.0))
		if out.length_squared() > FAR_CULL * FAR_CULL:
			continue
		var r := _closest(pieces[i], p)
		var d: float = r[0]
		if d < best_d:
			best_d = d
			best_s = r[1]
			best_t = r[2]
		var e := maxf(d - RH, 0.0) + 0.4
		var w: float = r[3] * (1.0 - smoothstep(FAR_FADE, FAR_CULL, d)) / (e * e)
		wsum += w
		hsum += w * height_at_s(r[1])
	var grass := (hsum / wsum if wsum > 0.0 else height_at_s(best_s)) - GRASS_DROP
	_memo_p = p
	_memo = {"d": best_d, "s": best_s, "t": best_t, "grass": grass}
	return _memo


func _grass_h(x: float, z: float) -> float:
	return _closest_all(Vector2(x, z))["grass"]


## s donde el tramo k cruza la línea de atajos.
func _cross_s(k: int) -> float:
	var x := _leg_x[k]
	var best := 0.0
	var best_d := INF
	for pc in pieces:
		var r := _closest(pc, Vector2(x, SHORT_Z))
		if r[0] < best_d:
			best_d = r[0]
			best = r[1]
	return best


# ---------------------------------------------------------------- física

func register(park: Object) -> void:
	var hw := RAMP_W
	# Atajos 1 y 2: kicker al borde este del tramo y recepción al borde oeste del siguiente.
	for k in 2:
		var h0 := height_at_s(_cross_s(k))
		var h1 := height_at_s(_cross_s(k + 1))
		park.shapes.append({"type": "bank", "o": Vector2(_leg_x[k] + RH, SHORT_Z), "dir": Vector2(1, 0),
			"w": hw, "h": 1.0, "l": 2.5, "len": 2.5, "side": Skatepark.C_WOOD_SIDE, "y0": h0,
			"k": KICKER_KICK, "skirt": 3.0})
		park.shapes.append({"type": "bank", "o": Vector2(_leg_x[k + 1] - RH, SHORT_Z), "dir": Vector2(-1, 0),
			"w": hw, "h": 1.3, "l": 4.0, "len": 4.4, "side": Skatepark.C_WOOD_SIDE, "y0": h1,
			"k": Skatepark.BANK_KICK, "skirt": 3.0})
	# Atajo 3: puente sobre el tramo 3 hasta el roll-in.
	var h2 := height_at_s(_cross_s(2))
	var deck_h: float = _deck["h"]
	var d0: float = _deck["x0"]
	var d1: float = _deck["x1"]
	var top := Skatepark.DECK_H + Skatepark.ROLL_IN_H
	var up0 := _leg_x[2] + RH
	park.shapes.append({"type": "bank", "o": Vector2(up0, SHORT_Z), "dir": Vector2(1, 0),
		"w": hw, "h": deck_h - h2, "l": d0 - up0, "len": d0 - up0, "side": Skatepark.C_WOOD_SIDE,
		"y0": h2, "k": Skatepark.BANK_KICK, "skirt": 3.0})
	park.shapes.append({"type": "bank", "o": Vector2(-Skatepark.HALF_X, SHORT_Z), "dir": Vector2(-1, 0),
		"w": hw, "h": deck_h - top, "l": -Skatepark.HALF_X - d1, "len": -Skatepark.HALF_X - d1,
		"side": Skatepark.C_WOOD_SIDE, "y0": top, "k": Skatepark.BANK_KICK, "skirt": 3.0})
	# Tablero y barandillas: solo existen para quien va por encima ("layer": altura del
	# tablero), así por la carretera se pasa por debajo.
	var z0: float = _deck["z0"]
	var z1: float = _deck["z1"]
	park.shapes.append({"type": "box", "min": Vector2(d0, z0), "max": Vector2(d1, z1), "h": deck_h,
		"layer": deck_h, "nomesh": true})
	for zz in [z0, z1 - 0.15]:
		park.shapes.append({"type": "box", "min": Vector2(d0, zz), "max": Vector2(d1, zz + 0.15),
			"h": deck_h + 0.8, "layer": deck_h, "nomesh": true})
	park.spawn_pos = start_pos
	park.spawn_yaw = start_yaw


# ---------------------------------------------------------------- malla

func _build() -> void:
	_mesh_grass()
	for pc in pieces:
		_mesh_piece(pc)
	_mesh_border()
	_mesh_bridge()


func _mesh_grass() -> void:
	var step := 1.5
	var x := x_min
	while x < -Skatepark.HALF_X - 0.01:
		var x1 := minf(x + step, -Skatepark.HALF_X)
		var z := -z_half
		while z < z_half - 0.01:
			var z1 := minf(z + step, z_half)
			var a := Vector3(x, _grass_h(x, z), z)
			var b := Vector3(x1, _grass_h(x1, z), z)
			var cc := Vector3(x1, _grass_h(x1, z1), z1)
			var d := Vector3(x, _grass_h(x, z1), z1)
			var col := C_GRASS.lerp(C_GRASS_DARK, _hash2(x * 0.3, z * 0.3))
			_tri(a, b, cc, _up_n(a, b, cc), col)
			_tri(a, cc, d, _up_n(a, cc, d), col)
			z = z1
		x = x1


func _up_n(a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var n := (b - a).cross(c - a).normalized()
	return -n if n.y < 0.0 else n


## Punto del centro de la carretera y tangente en u (0..len) de un tramo.
func _at(pc: Dictionary, u: float) -> Array:
	if pc["type"] == "line":
		var a: Vector2 = pc["a"]
		var b: Vector2 = pc["b"]
		var t := (b - a) / float(pc["len"])
		return [a + t * u, t]
	var c: Vector2 = pc["c"]
	var t0: float = pc["t0"]
	var dir := signf(float(pc["t1"]) - t0)
	var th := t0 + dir * u / R
	return [c + Vector2(cos(th), sin(th)) * R, Vector2(-sin(th), cos(th)) * dir]


func _mesh_piece(pc: Dictionary) -> void:
	var l: float = pc["len"]
	var n := maxi(1, int(ceil(l / (2.0 if pc["type"] == "line" else 1.2))))
	var s0: float = pc["s0"]
	for i in n:
		var u0 := l * i / n
		var u1 := l * (i + 1) / n
		var p0: Array = _at(pc, u0)
		var p1: Array = _at(pc, u1)
		var c0: Vector2 = p0[0]
		var c1: Vector2 = p1[0]
		var t0: Vector2 = p0[1]
		var t1: Vector2 = p1[1]
		var n0 := Vector2(-t0.y, t0.x)
		var n1 := Vector2(-t1.y, t1.x)
		var y0 := height_at_s(s0 + u0)
		var y1 := height_at_s(s0 + u1)
		var l0 := _v(c0 + n0 * RH, y0)
		var r0 := _v(c0 - n0 * RH, y0)
		var l1 := _v(c1 + n1 * RH, y1)
		var r1 := _v(c1 - n1 * RH, y1)
		var up := _up_n(l0, l1, r1)
		_quad(l0, l1, r1, r0, up, C_ASPHALT)
		# Bordillo: cara lateral del asfalto hasta por debajo del césped
		for side in [[l0, l1, n0, n1], [r0, r1, -n0, -n1]]:
			var a: Vector3 = side[0]
			var b: Vector3 = side[1]
			var sn: Vector2 = side[2]
			var drop := Vector3(0, -0.4, 0)
			_quad(a, b, b + drop, a + drop, Vector3(sn.x, 0.0, sn.y), C_CURB)
		# Línea discontinua del centro
		if int(floor((s0 + u0) / 1.5)) % 2 == 0:
			var w := 0.08
			var e := Vector3(0, 0.015, 0)
			_quad(_v(c0 + n0 * w, y0) + e, _v(c1 + n1 * w, y1) + e, _v(c1 - n1 * w, y1) + e,
				_v(c0 - n0 * w, y0) + e, up, C_LINE)


func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


## Borde de la zona: talud de roca desde abajo hasta un poco por encima del césped.
func _mesh_border() -> void:
	var step := 2.0
	var xe := -Skatepark.HALF_X
	var x := x_min
	while x < xe - 0.01:
		var x1 := minf(x + step, xe)
		for zs in [-1.0, 1.0]:
			var z: float = zs * z_half
			_cliff(Vector2(x, z), Vector2(x1, z), Vector3(0, 0, zs))
		x = x1
	var z := -z_half
	while z < z_half - 0.01:
		var z1 := minf(z + step, z_half)
		_cliff(Vector2(x_min, z), Vector2(x_min, z1), Vector3.LEFT)
		# Al este, junto al park solo donde no está el murete del park
		if absf(z) >= Skatepark.HALF_Z - 0.01 and absf(z1) >= Skatepark.HALF_Z - 0.01:
			_cliff(Vector2(xe, z), Vector2(xe, z1), Vector3.RIGHT)
		z = z1


func _cliff(a: Vector2, b: Vector2, n: Vector3) -> void:
	var inset := Vector2(-n.x, -n.z) * 0.2
	var ha := _grass_h(a.x + inset.x, a.y + inset.y) + 0.6
	var hb := _grass_h(b.x + inset.x, b.y + inset.y) + 0.6
	_quad(Vector3(a.x, -1.0, a.y), Vector3(b.x, -1.0, b.y), Vector3(b.x, hb, b.y), Vector3(a.x, ha, a.y), n, C_CLIFF)
	var o := Vector3(-n.x, 0, -n.z) * 0.3
	_quad(Vector3(a.x, ha, a.y), Vector3(b.x, hb, b.y), Vector3(b.x, hb, b.y) + o, Vector3(a.x, ha, a.y) + o, Vector3.UP, C_CLIFF.darkened(0.1))
	_quad(Vector3(a.x, ha, a.y) + o, Vector3(b.x, hb, b.y) + o, Vector3(b.x, hb - 0.7, b.y) + o,
		Vector3(a.x, ha - 0.7, a.y) + o, -n, C_CLIFF.darkened(0.2))


## Tablero del puente: losa con barandillas.
func _mesh_bridge() -> void:
	var x0: float = _deck["x0"]
	var x1: float = _deck["x1"]
	var z0: float = _deck["z0"]
	var z1: float = _deck["z1"]
	var h: float = _deck["h"]
	_box3(Vector3(x0, h - 0.45, z0), Vector3(x1, h, z1), C_BRIDGE)
	for zz in [z0, z1 - 0.15]:
		_box3(Vector3(x0, h, zz), Vector3(x1, h + 0.12, zz + 0.15), C_BRIDGE.darkened(0.15))
		_box3(Vector3(x0, h + 0.7, zz), Vector3(x1, h + 0.8, zz + 0.15), C_RAIL)
		var px := x0 + 0.2
		while px < x1:
			_box3(Vector3(px, h + 0.12, zz + 0.04), Vector3(px + 0.07, h + 0.7, zz + 0.11), C_RAIL.darkened(0.3))
			px += 1.2


func _box3(mn: Vector3, mx: Vector3, col: Color) -> void:
	var c := (mn + mx) * 0.5
	var p := [Vector3(mn.x, mn.y, mn.z), Vector3(mx.x, mn.y, mn.z), Vector3(mx.x, mn.y, mx.z), Vector3(mn.x, mn.y, mx.z),
		Vector3(mn.x, mx.y, mn.z), Vector3(mx.x, mx.y, mn.z), Vector3(mx.x, mx.y, mx.z), Vector3(mn.x, mx.y, mx.z)]
	for f in [[4, 5, 6, 7], [0, 1, 2, 3], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [3, 0, 4, 7]]:
		_quad_out(p[f[0]], p[f[1]], p[f[2]], p[f[3]], c, col)

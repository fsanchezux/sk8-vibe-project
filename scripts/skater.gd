class_name Skater
extends Node3D
## Física del skater sobre el skatepark (Skatepark.sample), inspirada en Skate 3:
## - Inercia y carving: la velocidad sigue la tabla; la gravedad acelera o frena
##   según la pendiente, así que se puede bombear en bancos y quarter pipes.
## - Al salir por el coping de un quarter casi vertical el skater sube recto y
##   vuelve a la rampa girando 180° solo.
## - Controles (FSA-164): pulgar derecho = empujar (flick arriba o toque) y trucos;
##   pulgar izquierdo = movimiento lateral; doble toque izquierdo = grab.
## - Grinds en rails, ledges y copings al caer encima (FSA-167).
## - Si aterrizas con el truco sin terminar, agarrando la tabla o cruzado -> bail.

## Truco completado que se suma al combo.
signal trick_done(trick_name: String, points: int)
## Ha tocado suelo limpio: si no encadena otro truco enseguida, el combo se cierra.
signal landed
signal bailed
## Golpe para la cámara (pop, aterrizaje): 0..1.
signal impact(strength: float)

enum State { RIDING, AIR, GRIND, BAIL }

@export_group("Rodar")
@export var push_impulse := 2.6
@export var max_push_speed := 9.0
@export var max_speed := 16.0
@export var push_time := 0.68
@export var rolling_friction := 0.25
@export var air_drag := 0.0035
@export var brake_decel := 4.5
@export_group("Giro")
@export var turn_rate_slow := 3.6
@export var turn_rate_fast := 1.6
@export var pivot_rate := 2.4
@export var spin_rate := 8.0
@export_group("Aire")
@export var gravity := 17.0
## Velocidad vertical del pop con el flick más corto y con el más largo (FSA-169).
@export var pop_min := 4.0
@export var pop_max := 6.0
## Fracción del truco que debe estar completada al tocar suelo para no caerse.
@export var land_tolerance := 0.85
@export var bail_time := 1.8
## Cerca del punto más alto la gravedad baja un poco: el truco se "plancha" arriba.
@export var apex_hang := 0.55
@export_group("Grind")
@export var grind_snap := 0.45
@export var grind_friction := 0.8
@export var grind_min_speed := 2.5

## Escalón más alto que se sube rodando; por encima es una pared.
const MAX_STEP := 0.15

## flip: vueltas sobre el eje largo; shove: medias vueltas sobre el eje vertical;
## time: duración máxima del giro de la tabla (se ajusta a la altura del pop).
const TRICKS := {
	"ollie": {"name": "Ollie", "flip": 0.0, "shove": 0.0, "time": 0.0, "points": 100},
	"kickflip": {"name": "Kickflip", "flip": 1.0, "shove": 0.0, "time": 0.5, "points": 300},
	"heelflip": {"name": "Heelflip", "flip": -1.0, "shove": 0.0, "time": 0.5, "points": 300},
	"bs_shove": {"name": "Pop Shove-it", "flip": 0.0, "shove": 1.0, "time": 0.42, "points": 250},
	"fs_shove": {"name": "FS Pop Shove-it", "flip": 0.0, "shove": -1.0, "time": 0.42, "points": 250},
	"varial_kickflip": {"name": "Varial Kickflip", "flip": 1.0, "shove": 1.0, "time": 0.56, "points": 500},
	"varial_heelflip": {"name": "Varial Heelflip", "flip": -1.0, "shove": -1.0, "time": 0.56, "points": 500},
	"tre_flip": {"name": "360 Flip", "flip": 1.0, "shove": 2.0, "time": 0.64, "points": 800},
	"laser_flip": {"name": "Laser Flip", "flip": -1.0, "shove": -2.0, "time": 0.64, "points": 900},
}

## Grabs: el stick izquierdo al hacer el doble toque elige cuál.
const GRABS := {
	"indy": {"name": "Indy", "points": 300},
	"melon": {"name": "Melon", "points": 300},
	"nosegrab": {"name": "Nosegrab", "points": 350},
	"tailgrab": {"name": "Tailgrab", "points": 350},
	"stalefish": {"name": "Stalefish", "points": 400},
}
## Puntos extra por segundo manteniendo el grab.
const GRAB_HOLD_POINTS := 400

## Grinds: [alineado, cruzado] según el tipo de zona.
const GRINDS := {
	"rail": [["50-50", 250], ["Boardslide", 300]],
	"ledge": [["5-0", 250], ["Noseslide", 300]],
	"coping": [["50-50 Coping", 300], ["Rock 'n' Roll", 350]],
}
## Puntos extra por segundo grindando.
const GRIND_HOLD_POINTS := 300

const SPIN_POINTS := {180: 200, 360: 500, 540: 900, 720: 1400, 900: 2000, 1080: 2800}

var state := State.RIDING
var input_enabled := false
var touch: TouchControls
var flick := FlickDetector.new()
var model: SkaterModel
var park: Skatepark

## Hacia dónde mira la tabla (yaw). Avanzar = (-sin, 0, -cos).
var heading := 0.0
## En suelo: velocidad a lo largo de la tabla.
var speed := 0.0
## En el aire / bail: velocidad 3D.
var vel := Vector3.ZERO
## Yaw que sigue la cámara (se congela en el aire para no marear en los quarters).
var cam_heading := 0.0

var _up := Vector3.UP
var _ground_n := Vector3.UP
## Giro visual extra respecto a heading (reverts, boardslides) que tiende a _offset_target.
var _yaw_offset := 0.0
var _offset_target := 0.0
var _push_phase := -1.0
var _push_applied := false
var _push_queued := false
var _crouch := 0.0
var _lean := 0.0
var _trick: Dictionary = {}
var _trick_t := 0.0
## Duración de cada vuelta extra al mantener el stick (flip y media vuelta de shove).
const EXTRA_FLIP_TIME := 0.24
const EXTRA_SHOVE_TIME := 0.17
## Giro de la tabla: vueltas objetivo y hechas (radianes), sentido y velocidad.
## Mantener el stick en la zona del truco añade vueltas (ver _advance_board).
var _flip_target := 0.0
var _flip_done := 0.0
var _flip_dir := 0.0
var _flip_speed := 0.0
var _shove_target := 0.0
var _shove_done := 0.0
var _shove_dir := 0.0
var _shove_speed := 0.0
var _hold_zone := ""
var _nollie := false
var _catch_time := -1.0
var _rise_k := 0.0
var _caught := false
var _land_comp := 0.0
var _air_t := 0.0
var _bail_t := 0.0
var _spin := 0.0
var _auto_spin := 0.0
var _auto_rate := 0.0
var _vert := false
var _grab_id := ""
var _grab_t := 0.0
var _grind: Dictionary = {}
var _grind_a := Vector3.ZERO
var _grind_dir := Vector3.FORWARD
var _grind_len := 1.0
var _grind_s := 0.0
var _grind_v := 0.0
var _grind_t := 0.0
var _grind_name := ""
var _grind_points := 0
var _grind_cool := 0.0
var _kb_right_last := Vector2.ZERO
var _kb_push_last := false
var _kb_ollie_last := false
var _kb_grab_last := false
var _kb_grab_edge := false
# Para animar los brazos en consonancia con el cuerpo
var _steer := 0.0
var _spin_vel := 0.0
var _anim_t := 0.0


var audio: SkaterAudio

## Caída: cuándo empieza a desvanecerse y cuánto tarda (también al reaparecer).
const BAIL_FADE_START := 0.75
const BAIL_FADE_TIME := 0.45
var _fade := 1.0
## Punto de reset elegido por el jugador (ver mark_spot / go_to_spot).
var _spot_pos := Vector3.ZERO
var _spot_yaw := 0.0
var _safe_pos := Vector3.ZERO
var _safe_yaw := 0.0
var _safe_t := 0.0
var _braking := false
var _brake_k := 0.0
var _prev_tail := Vector3.ZERO
## Fuerza del pop del truco en curso (0..1): más altura vale más puntos.
var _pop_power := 1.0
## Cuánto está agachado por el pump (0..1).
var _pump_k := 0.0
## Transfer: inclinación de la superficie donde va a caer (en el aire, bajando).
var _land_up := Vector3.UP
var _land_k := 0.0
## Este vuelo es la llegada al inicio (no da puntos de "Big Air").
var _arriving := false
## Velocidad al entrar al césped (-1 = no estamos en él).
var _grass_entry := -1.0
var skid_marks: SkidMarks

## Pump en quarters, olas y rampas: aceleración extra bajando (× seno de la pendiente).
const PUMP_ACCEL := 6.0

## Césped de la carretera: frena hasta GRASS_SPEED de la velocidad con que entraste
## (la mitad), con esta deceleración (m/s²).
const GRASS_SPEED := 0.5
const GRASS_DECEL := 8.0
## Al volver al inicio tras salir por una lanzadera: aparece en el aire, ARRIVE_H por
## encima de la salida y aún subiendo un poco, y cae a la carretera como si saliera de
## la rampa.
const ARRIVE_H := 5.0
const ARRIVE_UP := 2.0
## Transfer: con cuánta antelación (s) empieza a inclinarse hacia la rampa donde va a caer.
const TRANSFER_TIME := 0.45

## Rampa final (Skatepark.is_booster): velocidad a la que te empuja y con qué aceleración.
const BOOST_SPEED := 14.0
const BOOST_ACCEL := 18.0

## Fuerza del pop con el teclado manteniendo Mayús (sin Mayús es 1.0).
const KB_SOFT_POWER := 0.3

## Revert: a partir de cuántos grados de desvío al aterrizar se hace revert en vez de caerse.
const REVERT_MIN_DEG := 80.0
## Hasta cuántos grados de desvío se aterriza limpio (entre ambos: bail).
const CLEAN_MAX_DEG := 50.0
const REVERT_POINTS := 150
var _revert_t := -1.0
var _revert_from := 0.0
var _revert_dur := 0.5
var _offset_vel := 0.0
var _prev_truck_f := Vector3.ZERO
var _prev_truck_b := Vector3.ZERO


func _ready() -> void:
	model = SkaterModel.new()
	add_child(model)
	audio = SkaterAudio.new()
	add_child(audio)


## Celebración al caer un truco con combo alto: solo sonido (más brillante con más multiplicador).
func celebrate(level: int) -> void:
	audio.celebrate(level)


func reset_skater(pos := Vector3.ZERO, yaw := 0.0) -> void:
	position = pos
	if park:
		# Por capas: aparece sobre la superficie a su altura (encima o debajo del puente)
		park.probe_y = pos.y + 0.5
		position.y = park.height_at(pos.x, pos.z)
	heading = yaw
	cam_heading = yaw
	_safe_pos = position
	_safe_yaw = yaw
	_braking = false
	_brake_k = 0.0
	speed = 0.0
	vel = Vector3.ZERO
	state = State.RIDING
	_up = Vector3.UP
	_ground_n = Vector3.UP
	_yaw_offset = 0.0
	_offset_target = 0.0
	_push_phase = -1.0
	_push_queued = false
	_crouch = 0.0
	_pump_k = 0.0
	_grass_entry = -1.0
	_lean = 0.0
	_trick = {}
	_grab_id = ""
	_grind = {}
	_grind_cool = 0.0
	_revert_t = -1.0
	flick.reset()
	pad_flick.reset()
	model.reset()
	_update_transform(1.0)
	reset_physics_interpolation()


## Velocidad actual (para la cámara y los efectos de la UI).
func current_speed() -> float:
	match state:
		State.AIR, State.BAIL:
			return vel.length()
		State.GRIND:
			return absf(_grind_v)
	return speed


func is_grabbing() -> bool:
	return _grab_id != ""


## Cuánto "cine" merece este instante (0..1), para la cámara lenta: solo en el aire
## haciendo un truco, y más cerca del punto más alto, cuando se plancha la tabla.
func trick_focus() -> float:
	if state != State.AIR:
		return 0.0
	if _flip_target <= 0.0 and _shove_target <= 0.0 and _grab_id == "" and absf(_spin) < 0.6:
		return 0.0
	var apex := 1.0 - clampf(absf(vel.y) / 3.5, 0.0, 1.0)
	return 0.3 + apex * 0.7


func _physics_process(delta: float) -> void:
	var move := Vector2.ZERO
	if input_enabled:
		move = _read_move()
		_read_right()
		flick.update()
	_grind_cool = maxf(_grind_cool - delta, 0.0)
	# Física por capas: el park ignora lo que está por encima (tablero del puente si
	# pasamos por debajo).
	if park:
		park.probe_y = position.y
	match state:
		State.RIDING:
			_ride(delta, move)
		State.AIR:
			_air(delta, move)
		State.GRIND:
			_grind_process(delta)
		State.BAIL:
			_bail_process(delta)
	var prev_offset := _yaw_offset
	if _revert_t >= 0.0:
		_revert_process(delta)
	else:
		_yaw_offset = lerpf(_yaw_offset, _offset_target, 1.0 - exp(-delta * 9.0))
	_offset_vel = (_yaw_offset - prev_offset) / maxf(delta, 0.001)
	_land_comp = move_toward(_land_comp, 0.0, delta * 3.2)
	if state == State.RIDING or state == State.GRIND:
		cam_heading = heading
	audio.update(speed if state == State.RIDING else 0.0, absf(_grind_v) if state == State.GRIND else 0.0)
	audio.scrape(speed if (state == State.RIDING and _braking) else 0.0)
	if state != State.BAIL:
		_fade = move_toward(_fade, 1.0, delta / BAIL_FADE_TIME)
	model.set_fade(_fade)
	_update_transform(delta)
	_update_model(delta)
	model.earphones.step(delta)


# ---------------------------------------------------------------- suelo

func _forward(h: float) -> Vector3:
	return Vector3(-sin(h), 0.0, -cos(h))


## Dirección de la tabla sobre la superficie con gradiente g = (dh/dx, dh/dz).
func _surface_forward(h: float, g: Vector2) -> Vector3:
	var fh := _forward(h)
	return Vector3(fh.x, g.x * fh.x + g.y * fh.z, fh.z).normalized()


func _ride(delta: float, move: Vector2) -> void:
	var steer := move.x
	_steer = lerpf(_steer, steer, 1.0 - exp(-delta * 10.0))
	var winding := flick.is_winding() or pad_flick.is_winding()
	_crouch = move_toward(_crouch, 1.0 if winding else 0.0, delta * 6.0)
	_consume_grab_edge() # en el suelo el doble toque no hace nada

	var s := park.sample(position.x, position.z)
	var g := Vector2(s.y, s.z)
	_ground_n = Vector3(-g.x, 1.0, -g.y).normalized()
	var f := _surface_forward(heading, g)

	# Pump en quarters, olas y rampas: se agacha al bajar por la transición y se estira al
	# subir, y bajando gana algo de velocidad extra (como al bombear con las piernas).
	var pump := 0.0
	if park.is_pump_zone(position.x, position.z) and f.y < 0.0:
		pump = clampf(-f.y * 2.0, 0.0, 1.0)
		speed += PUMP_ACCEL * -f.y * delta
	_pump_k = move_toward(_pump_k, pump, delta * 5.0)
	_crouch = maxf(_crouch, _pump_k)

	# Empujar (pulgar derecho). No se empuja agachado ni en rampas empinadas.
	if _push_phase >= 0.0:
		_push_phase += delta / push_time
		if not _push_applied and _push_phase >= 0.45:
			_push_applied = true
			if speed < max_push_speed:
				var k := clampf(1.0 - speed / max_push_speed, 0.0, 1.0)
				speed += push_impulse * (0.35 + 0.65 * k)
		if _push_phase >= 1.0:
			_push_phase = -1.0
	if _push_phase < 0.0 and _push_queued:
		_push_queued = false
		if _crouch < 0.3 and absf(f.y) < 0.35 and speed < max_push_speed:
			_push_phase = 0.0
			_push_applied = false

	# Móvil: mantener el dedo en el stick izquierdo (o llevarlo hacia delante) empuja
	# sin parar; también W mantenida y A en el mando.
	# Freno (FSA-206): S en el teclado, X en el mando o llevar el stick izquierdo (táctil o
	# del mando) hacia abajo.
	# Levanta el morro y arrastra el tail (se oye y deja marca).
	_braking = _kb_brake() or (input_enabled and touch != null and touch.left_vector.y > 0.55) 		or (input_enabled and _pad_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y).y > 0.55)
	if input_enabled and touch and not _braking and (touch.left_held() or touch.left_vector.y < -0.5):
		_push_queued = true
	if _braking:
		_push_phase = -1.0
		_push_queued = false
		speed = move_toward(speed, 0.0, brake_decel * delta)
		if skid_marks and speed > 1.0:
			var tail := position - _forward(heading) * 0.36
			tail.y = park.height_at(tail.x, tail.z)
			if _prev_tail != Vector3.ZERO:
				skid_marks.add_mark(_prev_tail, tail, _ground_n, 0.05, clampf(speed / 7.0, 0.2, 0.7))
			_prev_tail = tail
	else:
		_prev_tail = Vector3.ZERO
	_brake_k = move_toward(_brake_k, 1.0 if _braking else 0.0, delta * 6.0)
	_remember_safe_spot(delta)

	# Gravedad a lo largo de la pendiente + rodadura y aire. En la rampa final subir no
	# frena: empuja hasta BOOST_SPEED para lanzarte fuera del mapa.
	if f.y > 0.0 and park.is_booster(position.x, position.z):
		speed = move_toward(speed, maxf(speed, BOOST_SPEED), BOOST_ACCEL * delta)
	else:
		speed -= gravity * f.y * delta
	speed = move_toward(speed, 0.0, (rolling_friction + air_drag * speed * speed) * delta)
	if park.is_grass(position.x, position.z):
		if _grass_entry < 0.0:
			_grass_entry = speed
		speed = move_toward(speed, minf(speed, _grass_entry * GRASS_SPEED), GRASS_DECEL * delta)
	else:
		_grass_entry = -1.0
	speed = clampf(speed, -max_speed, max_speed)

	# Si la tabla se va hacia atrás (se para subiendo una rampa) hace un revert solo.
	if speed < -0.05:
		heading = wrapf(heading + PI, -PI, PI)
		speed = -speed
		_start_revert(_yaw_offset - PI, false)

	# Carving
	var rate := lerpf(turn_rate_slow, turn_rate_fast, clampf(speed / 10.0, 0.0, 1.0))
	if speed < 0.3:
		rate = pivot_rate
	heading -= steer * rate * delta
	var lean_target := -steer * clampf(speed / 5.0, 0.25, 1.0) * 0.42
	_lean = lerpf(_lean, lean_target, 1.0 - exp(-delta * 12.0))

	# Trucos (flicks del pulgar derecho o del stick derecho del mando)
	var id := flick.consume()
	if id == "":
		id = _consume_pad_flick()
	if id == "push":
		_push_queued = true
	elif _is_trick(id):
		_pop(id)
		return

	# Avanzar sobre la superficie
	f = _surface_forward(heading, g)
	var disp := f * speed * delta
	var ns := park.sample(position.x + disp.x, position.z + disp.z)
	var pred := (g + Vector2(ns.y, ns.z)).dot(Vector2(disp.x, disp.z)) * 0.5
	if ns.x - s.x - pred > MAX_STEP:
		_hit_wall(s, disp)
		return
	var expected_y := position.y + disp.y
	var drop := expected_y - ns.x
	if (drop > 0.02 and speed > 1.0) or drop > 0.1:
		# El suelo se aleja más rápido que la caída: despega (coping, canto, escalón...)
		position = Vector3(position.x + disp.x, expected_y, position.z + disp.z)
		_enter_air(f * speed)
		_check_vert()
		return
	position = Vector3(position.x + disp.x, ns.x, position.z + disp.z)


func _hit_wall(s: Vector3, disp: Vector3) -> void:
	# Rozando la pared en ángulo cerrado: deslizar a lo largo de ella.
	var dh := Vector2(disp.x, disp.z)
	if dh.length() > 0.0001:
		for axis in [Vector2(dh.x, 0.0), Vector2(0.0, dh.y)]:
			var a: Vector2 = axis
			if a.length() / dh.length() < 0.8:
				continue # ese eje es el que choca de frente
			var ns := park.sample(position.x + a.x, position.z + a.y)
			if ns.x - s.x > MAX_STEP:
				continue
			var along := atan2(-signf(a.x), -signf(a.y))
			_yaw_offset += wrapf(heading - along, -PI, PI)
			heading = along
			speed *= 0.92
			position = Vector3(position.x + a.x, ns.x, position.z + a.y)
			return
	if speed > 7.0:
		speed *= -0.2
		_start_bail()
		return
	speed = -speed * 0.3
	_push_phase = -1.0


## Revert: la tabla derrapa girando desde el ángulo con que aterrizó hasta quedar
## recta. Recorrido marcado con un poco de sobregiro, frena algo, suena el derrape
## y deja marcas de goma. Si viene de un truco cuenta en el combo.
func _start_revert(from_offset: float, scored: bool) -> void:
	_revert_t = 0.0
	_revert_from = from_offset
	# Cuanto más ángulo le queda por girar, más dura el derrape
	_revert_dur = (0.35 + absf(from_offset) / PI * 0.3) if scored else 0.4
	_yaw_offset = from_offset
	_offset_target = 0.0
	var trucks := _truck_positions()
	_prev_truck_f = trucks[0]
	_prev_truck_b = trucks[1]
	if speed > 1.0 or scored:
		audio.skid(clampf(speed / 8.0, 0.35, 1.0))
	if scored:
		trick_done.emit("Revert", REVERT_POINTS)


func _revert_process(delta: float) -> void:
	_revert_t += delta
	var k := clampf(_revert_t / _revert_dur, 0.0, 1.0)
	# Sale rápido, se frena al final y sobregira un poco antes de asentarse
	var c1 := 1.5
	var e := 1.0 + (c1 + 1.0) * pow(k - 1.0, 3.0) + c1 * pow(k - 1.0, 2.0)
	_yaw_offset = _revert_from * (1.0 - e)
	if state == State.RIDING:
		speed *= exp(-0.5 * delta) # el derrape come algo de velocidad
		if skid_marks and k < 0.85:
			var trucks := _truck_positions()
			var n := _ground_n
			var strength := clampf(speed / 6.0, 0.3, 1.0) * (1.0 - k)
			skid_marks.add_mark(_prev_truck_f, trucks[0], n, 0.07, strength)
			skid_marks.add_mark(_prev_truck_b, trucks[1], n, 0.07, strength)
			_prev_truck_f = trucks[0]
			_prev_truck_b = trucks[1]
	if k >= 1.0:
		_revert_t = -1.0
		_yaw_offset = 0.0


## Posición en el suelo de los dos ejes de la tabla (con el giro visual del revert).
func _truck_positions() -> Array:
	var yaw := heading + _yaw_offset
	var along := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var p := position
	var f := p + along * 0.21
	var b := p - along * 0.21
	f.y = park.height_at(f.x, f.z) if park else p.y
	b.y = park.height_at(b.x, b.z) if park else p.y
	return [f, b]


func _pop(id: String) -> void:
	var s := park.sample(position.x, position.z)
	var f := _surface_forward(heading, Vector2(s.y, s.z))
	_enter_air(f * speed + _ground_n * lerpf(pop_min, pop_max, flick.power))
	_start_trick(id)
	_check_vert()


func _trick_base(id: String) -> String:
	return id.trim_prefix("nollie_")


func _is_trick(id: String) -> bool:
	return id != "" and TRICKS.has(_trick_base(id))


## Empieza un truco con pop (desde el suelo o saliendo de un grind).
## Los ids "nollie_..." son la versión nollie (pop con el pie delantero).
func _start_trick(id: String) -> void:
	_nollie = id.begins_with("nollie_")
	_trick = TRICKS[_trick_base(id)]
	_trick_t = 0.0
	_caught = false
	_catch_time = -1.0
	var flip: float = _trick["flip"]
	var shove: float = _trick["shove"]
	# La tabla gira hacia donde va el stick (FSA-169): kickflip / BS shove con el
	# stick a la izquierda, heelflip / FS shove a la derecha, visto desde la cámara.
	_flip_dir = -signf(flip)
	_shove_dir = -signf(shove)
	_flip_target = absf(flip) * TAU
	_shove_target = absf(shove) * PI
	_flip_done = 0.0
	_shove_done = 0.0
	# El giro de la tabla ocupa toda la subida y acaba justo pasado el punto más alto:
	# recorrido largo y vistoso, y se atrapa "planchada" arriba. (×1.25 compensa la
	# frenada del final de la vuelta.)
	var to_apex := maxf(vel.y, 0.0) / (gravity * lerpf(apex_hang, 1.0, 0.5))
	var base: float = _trick["time"]
	var dur := clampf(to_apex * 1.2, base * 0.75, base) if base > 0.0 else 0.4
	_flip_speed = _flip_target / dur * 1.25
	_shove_speed = _shove_target / dur * 1.25
	# Zona del stick que, mantenida, sigue girando la tabla
	if flip != 0.0:
		_hold_zone = "flip_l" if flip > 0.0 else "flip_r"
	elif shove != 0.0:
		_hold_zone = "side_l" if shove > 0.0 else "side_r"
	else:
		_hold_zone = ""
	_crouch = 0.0
	_pop_power = flick.power
	audio.pop(flick.power)
	impact.emit(0.25 + flick.power * 0.2)


## Gira la tabla hacia sus vueltas objetivo. Si el jugador mantiene el stick en la
## zona del truco, añade otra vuelta (doble, triple kickflip, 360/540 shove-it...)
## mientras quede tiempo de vuelo para acabarla.
func _advance_board(delta: float) -> void:
	if _flip_target <= 0.0 and _shove_target <= 0.0:
		return
	if _caught:
		_catch_time += delta
		return
	var zone := flick.held_zone()
	if zone == "":
		zone = pad_flick.held_zone()
	if zone != "" and zone == _hold_zone:
		# Al final de la vuelta actual, si da tiempo a otra entera. Las vueltas extra
		# van más rápidas (la tabla se "embala"), así caben varias en un buen aire.
		if _flip_target > 0.0:
			var rem := _flip_target - _flip_done
			var fast := maxf(_flip_speed, TAU / EXTRA_FLIP_TIME)
			if rem < TAU * 0.3 and _time_to_ground() > (rem + TAU) / fast * 1.15:
				_flip_target += TAU
				_flip_speed = fast
		else:
			var rem := _shove_target - _shove_done
			var fast := maxf(_shove_speed, PI / EXTRA_SHOVE_TIME)
			if rem < PI * 0.3 and _time_to_ground() > (rem + PI) / fast * 1.15:
				_shove_target += PI
				_shove_speed = fast
	_flip_done = _approach(_flip_done, _flip_target, _flip_speed, TAU, delta)
	_shove_done = _approach(_shove_done, _shove_target, _shove_speed, PI, delta)
	if _flip_done >= _flip_target and _shove_done >= _shove_target:
		_caught = true
		_catch_time = 0.0
		audio.catch_board()


## Avanza hacia el objetivo frenando en el último tramo (la tabla "llega" a los pies).
func _approach(done: float, target: float, spd: float, unit: float, delta: float) -> float:
	var rem := target - done
	if rem <= 0.0:
		return target
	var k := clampf(rem / (unit * 0.4), 0.45, 1.0)
	return minf(done + spd * k * delta, target)


## La tabla no ha terminado de girar (si toca suelo así, te caes).
func _board_unfinished() -> bool:
	return _flip_target - _flip_done > TAU * 0.15 or _shove_target - _shove_done > PI * 0.22


## Tiempo aproximado hasta tocar el suelo.
func _time_to_ground() -> float:
	var h := position.y - park.height_at(position.x, position.z)
	var g := gravity * 0.85
	return (vel.y + sqrt(maxf(vel.y * vel.y + 2.0 * g * maxf(h, 0.0), 0.0))) / g


## Nombre del truco según las vueltas hechas: "Double Kickflip", "360 Shove-it",
## "Nollie Heelflip"...
func _trick_name() -> String:
	var base: String = _trick["name"]
	var flip: float = _trick["flip"]
	var shove: float = _trick["shove"]
	var n := base
	if flip != 0.0:
		var flips := int(roundf(_flip_target / TAU))
		if flips > 1:
			n = _count_prefix(flips) + base
	elif shove != 0.0:
		var halves := int(roundf(_shove_target / PI))
		if halves > 1:
			n = ("" if shove > 0.0 else "FS ") + "%d Shove-it" % (halves * 180)
	if _nollie:
		n = "Nollie" if base == "Ollie" else "Nollie " + n
	return n


func _count_prefix(c: int) -> String:
	match c:
		2:
			return "Double "
		3:
			return "Triple "
		4:
			return "Quad "
	return "%dx " % c


func _trick_points() -> int:
	var flip: float = _trick["flip"]
	var shove: float = _trick["shove"]
	var extra := 0.0
	if flip != 0.0:
		extra = maxf(roundf(_flip_target / TAU) - absf(flip), 0.0)
	elif shove != 0.0:
		extra = maxf(roundf(_shove_target / PI) - absf(shove), 0.0)
	var pts := float(_trick["points"]) * (1.0 + 0.9 * extra)
	if _nollie:
		pts *= 1.25
	# Intensidad (FSA-179): un pop bajo vale un 20 % menos y el más alto un 30 % más.
	pts *= lerpf(0.8, 1.3, _pop_power)
	return int(pts)


func _enter_air(v: Vector3) -> void:
	state = State.AIR
	_arriving = false
	_revert_t = -1.0
	vel = v
	_air_t = 0.0
	_trick = {}
	_trick_t = 0.0
	_flip_target = 0.0
	_shove_target = 0.0
	_flip_done = 0.0
	_shove_done = 0.0
	_nollie = false
	_caught = false
	_catch_time = -1.0
	_spin = 0.0
	_auto_spin = 0.0
	_vert = false
	_grab_id = ""
	_push_phase = -1.0
	_push_queued = false


## Saliendo de una pared casi vertical: subir recto y volver a la rampa con un giro de 180°.
func _check_vert() -> void:
	var n := _ground_n
	if n.y > 0.5 or vel.y < 1.0:
		return
	var nh := Vector3(n.x, 0.0, n.z).normalized()
	vel -= nh * vel.dot(nh)
	vel += nh * 0.5
	_vert = true
	var target := atan2(-nh.x, -nh.z)
	_auto_spin = wrapf(target - heading, -PI, PI)
	var flight := maxf(2.0 * vel.y / gravity, 0.3)
	_auto_rate = absf(_auto_spin) / (flight * 0.75)


# ---------------------------------------------------------------- aire

func _air(delta: float, move: Vector2) -> void:
	_air_t += delta
	_trick_t += delta
	flick.consume() # los flips se hacen al pegar el pop
	pad_flick.consume()
	_update_grab(delta, move)

	# Giro con el pulgar izquierdo (más lento agarrando)
	var spin := -move.x * spin_rate * delta * (0.5 if _grab_id != "" else 1.0)
	heading += spin
	_spin += spin
	if _auto_spin != 0.0:
		var step := signf(_auto_spin) * minf(absf(_auto_spin), _auto_rate * delta)
		heading += step
		_auto_spin -= step
		spin += step
	_spin_vel = lerpf(_spin_vel, spin / maxf(delta, 0.001), 1.0 - exp(-delta * 10.0))
	_lean = lerpf(_lean, 0.0, 1.0 - exp(-delta * 4.0))
	_crouch = move_toward(_crouch, 0.0, delta * 4.0)
	_advance_board(delta)
	_predict_landing()

	# Gravedad algo menor cerca del punto más alto (flotar un instante al planchar).
	var hang := lerpf(apex_hang, 1.0, clampf(absf(vel.y) / 2.2, 0.0, 1.0))
	vel.y -= gravity * hang * delta
	var np := position + vel * delta
	var s0 := park.sample(position.x, position.z)
	var s1 := park.sample(np.x, np.z)
	# ¿Chocamos contra el lateral de algo? (salto de altura, no una rampa continua)
	var pred := (Vector2(s0.y, s0.z) + Vector2(s1.y, s1.z)).dot(Vector2(np.x - position.x, np.z - position.z)) * 0.5
	if s1.x > np.y and s1.x - s0.x - pred > MAX_STEP:
		vel.x *= -0.3
		vel.z *= -0.3
		np.x = position.x
		np.z = position.z
		s1 = s0
	if _grind_cool <= 0.0 and _try_grind(position, np):
		return
	position = np
	if _air_t > 0.05 and position.y <= s1.x:
		position.y = s1.x
		_land(s1)


## Transfer: bajando, sigue la parábola hasta el suelo y, si cae en una rampa (olas,
## quarters, banks), se va inclinando hacia ella para entrar suave. Subiendo no hace
## nada: al salir de una lanzadera el cuerpo se endereza como siempre.
func _predict_landing() -> void:
	_land_k = 0.0
	if vel.y >= 0.0:
		return
	var p := position
	var v := vel
	var dt := 0.03
	var t := 0.0
	while t < TRANSFER_TIME:
		t += dt
		v.y -= gravity * dt
		p += v * dt
		var s := park.sample(p.x, p.z)
		if p.y <= s.x:
			var n := Vector3(-s.y, 1.0, -s.z).normalized()
			if n.y < 0.97:
				_land_up = n
				_land_k = 1.0 - t / TRANSFER_TIME
			return


func _update_grab(delta: float, move: Vector2) -> void:
	var held := _grab_held()
	var pressed := _consume_grab_edge()
	if _grab_id == "":
		if pressed and _air_t > 0.04:
			_grab_id = _pad_grab(move) if _pad_grab_hand != "" else _grab_from_stick(move)
			_grab_t = 0.0
		return
	_grab_t += delta
	# Durante el primer instante se puede elegir el grab moviendo el stick.
	if _grab_t < 0.2 and move.length() > 0.5:
		_grab_id = _pad_grab(move) if _pad_grab_hand != "" else _grab_from_stick(move)
	if not held and _grab_t >= 0.3:
		_release_grab()


func _release_grab() -> void:
	var gdef: Dictionary = GRABS[_grab_id]
	var pts: int = gdef["points"] + int(maxf(_grab_t - 0.3, 0.0) * GRAB_HOLD_POINTS)
	trick_done.emit(gdef["name"], pts)
	_grab_id = ""


func _grab_from_stick(move: Vector2) -> String:
	if move.length() < 0.5:
		return "indy"
	if absf(move.y) > absf(move.x):
		return "nosegrab" if move.y < 0.0 else "tailgrab"
	return "melon" if move.x < 0.0 else "stalefish"


func _land(s: Vector3) -> void:
	var g := Vector2(s.y, s.z)
	var n := Vector3(-g.x, 1.0, -g.y).normalized()
	_ground_n = n
	if _board_unfinished() or _grab_id != "":
		_start_bail()
		return
	var vt := vel - n * vel.dot(n)
	var vh := Vector2(vt.x, vt.z)
	var travel := heading
	if vh.length() > 0.3:
		travel = atan2(-vh.x, -vh.y)
	var diff := wrapf(heading - travel, -PI, PI)
	# Según cuánto le falte al giro: casi recto = limpio; cruzado = bail;
	# de espaldas (con bastante margen) = revert, derrapando hasta quedar recto.
	var off_deg := absf(rad_to_deg(diff))
	if off_deg > CLEAN_MAX_DEG and off_deg < REVERT_MIN_DEG and vh.length() > 2.0:
		_start_bail()
		return
	var reverting := off_deg >= REVERT_MIN_DEG
	# El revert sigue el sentido en que venía girando el cuerpo (inercia), aunque
	# eso suponga dar más vuelta que por el camino corto.
	# Sentido: el del giro hecho en el aire (aunque ya se haya soltado el stick);
	# si no se giró, el de la velocidad de giro que quede (rebotes, verticales).
	var spin_dir := signf(_spin) if absf(_spin) > 0.3 else (signf(_spin_vel) if absf(_spin_vel) > 0.5 else 0.0)
	if reverting:
		if spin_dir > 0.0 and diff > 0.0:
			diff -= TAU
		elif spin_dir < 0.0 and diff < 0.0:
			diff += TAU
	heading = travel
	_yaw_offset = diff
	_offset_target = 0.0
	var f := _surface_forward(heading, g)
	speed = maxf(vt.dot(f), 0.0) * 0.97
	state = State.RIDING
	# Amortiguar: cuanto más fuerte cae (velocidad contra la superficie), más flexiona.
	var hit := clampf(-vel.dot(n) / 9.0, 0.0, 1.0)
	_land_comp = maxf(_land_comp, 0.35 + hit * 0.65)
	audio.land(0.3 + hit * 0.7)
	impact.emit(0.2 + hit * 0.8)
	model.set_trick_rotation(0.0, 0.0)
	_emit_air_tricks(not _arriving)
	_arriving = false
	_trick = {}
	if reverting:
		_start_revert(diff, true)
	landed.emit()


## Suma al combo el flip, el giro y (si aterriza) el bonus de aire.
func _emit_air_tricks(with_air_bonus: bool) -> void:
	var deg := int(roundf(absf(rad_to_deg(_spin)) / 180.0)) * 180
	var spin_name := "%s %d" % ["FS" if _spin > 0.0 else "BS", deg]
	var spin_pts: int = SPIN_POINTS.get(mini(deg, 1080), 2800)
	var flipped: bool = not _trick.is_empty() and _trick["name"] != "Ollie"
	if flipped and deg >= 180:
		# Giro del cuerpo + flip de la tabla a la vez: un solo truco que vale más
		# que las dos partes por separado (p. ej. "BS 180 Kickflip").
		var pts := int((_trick_points() + spin_pts) * 1.3)
		trick_done.emit("%s %s" % [spin_name, _trick_name()], pts)
	else:
		if not _trick.is_empty():
			trick_done.emit(_trick_name(), _trick_points())
		if deg >= 180:
			trick_done.emit(spin_name, spin_pts)
	if with_air_bonus:
		if _vert and _air_t > 0.5:
			trick_done.emit("Air", 150 + int(_air_t * 250.0))
		elif _air_t > 1.0:
			trick_done.emit("Big Air", 300 + int(_air_t * 300.0))
	_spin = 0.0


# ---------------------------------------------------------------- grinds

func _try_grind(p0: Vector3, p1: Vector3) -> bool:
	if vel.y > 1.0:
		return false
	for r in park.rails:
		var kind: String = r["kind"]
		if _vert and kind == "coping":
			continue # en las verticales no se engancha solo al coping
		var a: Vector3 = r["a"]
		var b: Vector3 = r["b"]
		var ab := b - a
		var abh := Vector2(ab.x, ab.z)
		var t := clampf(Vector2(p1.x - a.x, p1.z - a.z).dot(abh) / abh.length_squared(), 0.0, 1.0)
		var length := ab.length()
		if t * length < 0.15 or (1.0 - t) * length < 0.15:
			continue
		var cp := a + ab * t
		if Vector2(p1.x - cp.x, p1.z - cp.z).length() > grind_snap:
			continue
		if p0.y < cp.y - 0.08 or p1.y > cp.y + 0.4:
			continue
		_start_grind(r, a, ab, t * length)
		return true
	return false


func _start_grind(r: Dictionary, a: Vector3, ab: Vector3, s: float) -> void:
	if _board_unfinished():
		_start_bail()
		return
	if _grab_id != "":
		_release_grab()
	_emit_air_tricks(false)
	_trick = {}
	model.set_trick_rotation(0.0, 0.0)

	var dir := ab.normalized()
	var along := vel.dot(dir)
	var sgn := 1.0 if along >= 0.0 else -1.0
	_grind_v = along if absf(along) >= grind_min_speed else sgn * grind_min_speed
	var dh := Vector2(dir.x, dir.z).normalized()
	var aligned := absf(_forward(heading).dot(Vector3(dh.x, 0.0, dh.y))) > 0.6
	var travel := atan2(-dh.x * sgn, -dh.y * sgn)
	var off := wrapf(heading - travel, -PI, PI)
	heading = travel
	_yaw_offset = off
	if aligned:
		_offset_target = 0.0
	else:
		_offset_target = PI * 0.5 * (1.0 if off >= 0.0 else -1.0)
	var names: Array = GRINDS[String(r["kind"])]
	var pick: Array = names[0 if aligned else 1]
	_grind_name = pick[0]
	_grind_points = pick[1]
	_grind = r
	_grind_a = a
	_grind_dir = dir
	_grind_len = ab.length()
	_grind_s = s
	_grind_t = 0.0
	position = a + dir * s
	state = State.GRIND


func _grind_process(delta: float) -> void:
	_grind_t += delta
	_grind_v -= gravity * _grind_dir.y * delta
	_grind_v = move_toward(_grind_v, 0.0, grind_friction * delta)
	if absf(_grind_v) < 0.8:
		_grind_v = 0.8 if _grind_v >= 0.0 else -0.8
	_grind_s += _grind_v * delta
	_crouch = move_toward(_crouch, 0.55, delta * 4.0)
	_lean = sin(_grind_t * 7.0) * 0.06
	_consume_grab_edge()
	var id := flick.consume()
	if id == "":
		id = _consume_pad_flick()
	if _is_trick(id):
		_exit_grind(id)
		return
	if _grind_s < 0.0 or _grind_s > _grind_len:
		_exit_grind("")
		return
	position = _grind_a + _grind_dir * _grind_s


func _exit_grind(pop_id: String) -> void:
	trick_done.emit(_grind_name, _grind_points + int(_grind_t * GRIND_HOLD_POINTS))
	_grind_cool = 0.3
	_offset_target = 0.0
	var up := lerpf(pop_min, pop_max, flick.power) if pop_id != "" else 0.8
	_enter_air(_grind_dir * _grind_v + Vector3.UP * up)
	if pop_id != "":
		_start_trick(pop_id)
	_grind = {}


# ---------------------------------------------------------------- bail

func _start_bail() -> void:
	if state == State.RIDING:
		vel = _forward(heading) * speed
	state = State.BAIL
	_bail_t = 0.0
	_revert_t = -1.0
	_yaw_offset = 0.0
	_trick = {}
	_grab_id = ""
	_grind = {}
	_push_phase = -1.0
	_lean = 0.0
	_offset_target = 0.0
	model.start_bail(Vector2(vel.x, vel.z).length())
	audio.bail()
	impact.emit(0.8)
	bailed.emit()


func _bail_process(delta: float) -> void:
	_bail_t += delta
	var s0 := park.sample(position.x, position.z)
	var on_ground := position.y <= s0.x + 0.01
	if on_ground:
		# Resbala pendiente abajo y se frena por el rozamiento
		vel.x += -s0.y * gravity * 0.4 * delta
		vel.z += -s0.z * gravity * 0.4 * delta
		var h := Vector2(vel.x, vel.z).move_toward(Vector2.ZERO, 7.0 * delta)
		vel.x = h.x
		vel.z = h.y
		vel.y = 0.0
	else:
		vel.y -= gravity * delta
	var np := position + vel * delta
	var s1 := park.sample(np.x, np.z)
	if s1.x - s0.x > MAX_STEP + absf(np.y - position.y):
		np.x = position.x
		np.z = position.z
		vel.x = 0.0
		vel.z = 0.0
		s1 = s0
	if np.y <= s1.x or on_ground:
		np.y = s1.x
	position = np
	_ground_n = Vector3.UP
	# Tras la caída se desvanece (así no se ve atravesar nada) y reaparece en el
	# último sitio seguro por el que rodó, apareciendo poco a poco.
	_fade = 1.0 - clampf((_bail_t - BAIL_FADE_START) / BAIL_FADE_TIME, 0.0, 1.0)
	if _bail_t >= BAIL_FADE_START + BAIL_FADE_TIME:
		_respawn()


func _respawn() -> void:
	reset_skater(_safe_pos, _safe_yaw)
	_fade = 0.0


## Fija el punto de reset en la posición actual (FSA-169). Solo rodando por el suelo,
## salvo con force (al empezar la sesión).
func mark_spot(force := false) -> bool:
	if not force and state != State.RIDING:
		return false
	_spot_pos = position
	_spot_yaw = heading
	return true


## Vuelve al punto de reset (para repetir trucos en un spot o si te quedas atascado).
func go_to_spot() -> void:
	reset_skater(_spot_pos, _spot_yaw)
	_fade = 0.0


## Vuelve al principio del recorrido sin perder velocidad (al salir del mapa por el este):
## llega por el aire y cae sobre la salida, como al salir de una rampa.
func teleport_to(pos: Vector3, yaw: float) -> void:
	var keep := Vector2(vel.x, vel.z).length() if state == State.AIR else current_speed()
	if state == State.BAIL:
		keep = 0.0
	reset_skater(pos, yaw)
	keep = minf(keep, max_speed)
	position.y += ARRIVE_H
	_enter_air(_forward(yaw) * keep + Vector3.UP * ARRIVE_UP)
	_arriving = true
	reset_physics_interpolation()


func spot_position() -> Vector3:
	return _spot_pos


## No se puede volver al spot en mitad de un truco (aire o grind): sería un toque por error.
func can_return_to_spot() -> bool:
	return state != State.AIR and state != State.GRIND


## Guarda la posición como sitio seguro para reaparecer si es suelo llano y despejado.
func _remember_safe_spot(delta: float) -> void:
	_safe_t += delta
	if _safe_t < 0.3:
		return
	_safe_t = 0.0
	var p := position
	var h := park.height_at(p.x, p.z)
	# Lejos de paredes (1,5 m) y casi llano (la carretera tiene un 3,5 % de pendiente)
	for o in [Vector2(0.9, 0), Vector2(-0.9, 0), Vector2(0, 0.9), Vector2(0, -0.9)]:
		var d: Vector2 = o
		if absf(park.height_at(p.x + d.x, p.z + d.y) - h) > 0.04:
			return
		if absf(park.height_at(p.x + d.x * 1.7, p.z + d.y * 1.7) - h) > 1.0:
			return
	_safe_pos = Vector3(p.x, h, p.z)
	_safe_yaw = heading


# ---------------------------------------------------------------- entrada

## Movimiento: pulgar izquierdo, stick izquierdo del mando o A/D. Rodando solo cuenta
## el eje lateral (FSA-164); en el aire el vertical también elige el grab.
## x = lateral, y = arriba/abajo.
func _read_move() -> Vector2:
	var v := Vector2.ZERO
	if touch:
		v = touch.left_vector.limit_length(1.0)
	var pad := _pad_stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
	if pad != Vector2.ZERO:
		v = pad
	var kx := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	var ky := float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	if kx != 0.0:
		v.x = kx
	if state == State.AIR and ky != 0.0:
		v.y = ky
	return v


## Freno: X en el mando o S en el teclado.
func _kb_brake() -> bool:
	return input_enabled and (Input.is_physical_key_pressed(KEY_S) or _pad_button(JOY_BUTTON_X))


func _read_right() -> void:
	# Flechas del teclado = stick derecho (para probar en PC).
	var kb := Vector2(
		float(Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP)))
	kb = kb.normalized()
	# Sin recorrido que medir con teclas, la intensidad es fija: Mayús = pop suave.
	flick.power_cap = KB_SOFT_POWER if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	if kb != Vector2.ZERO or _kb_right_last != Vector2.ZERO:
		flick.feed(kb)
	_kb_right_last = kb
	# W = empujar, Espacio = ollie, K = grab (atajos de teclado)
	var w := Input.is_physical_key_pressed(KEY_W)
	if w and (not _kb_push_last or _push_phase < 0.0):
		_push_queued = true
	_kb_push_last = w
	var sp := Input.is_physical_key_pressed(KEY_SPACE)
	if sp and not _kb_ollie_last:
		flick.queue("ollie")
	_kb_ollie_last = sp
	var k := Input.is_physical_key_pressed(KEY_K)
	if k and not _kb_grab_last:
		_kb_grab_edge = true
		_pad_grab_hand = ""
	_kb_grab_last = k
	_read_pad()


# ---------------------------------------------------------------- mando (controles de Skate 3)
#   Stick izquierdo: girar (en el aire, rotar)   Stick derecho: flick-it (trucos)
#   A: empujar (mantener = seguir empujando)     X: frenar
#   LT: grab con la mano delantera               RT: grab con la mano trasera

var pad_flick := _make_pad_flick()


static func _make_pad_flick() -> FlickDetector:
	var f := FlickDetector.new()
	f.up_pushes = false # en el mando empujar va con A
	return f


var _pad_right_last := Vector2.ZERO
var _pad_a_last := false
var _pad_lt_last := false
var _pad_rt_last := false
var _pad_grab_hand := ""


func _pad_id() -> int:
	var pads := Input.get_connected_joypads()
	return pads[0] if not pads.is_empty() else -1


func _pad_button(b: JoyButton) -> bool:
	var id := _pad_id()
	return id >= 0 and Input.is_joy_button_pressed(id, b)


func _pad_axis(a: JoyAxis) -> float:
	var id := _pad_id()
	return Input.get_joy_axis(id, a) if id >= 0 else 0.0


## Stick con zona muerta radial (y positiva hacia abajo, como el FlickDetector).
func _pad_stick(ax: JoyAxis, ay: JoyAxis) -> Vector2:
	var v := Vector2(_pad_axis(ax), _pad_axis(ay))
	var l := v.length()
	if l < 0.2:
		return Vector2.ZERO
	return v / l * clampf((l - 0.2) / 0.75, 0.0, 1.0)


func _read_pad() -> void:
	if _pad_id() < 0:
		return
	# Stick derecho = flick-it. En el mando empujar va con A, no con el stick.
	var r := _pad_stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
	if r != Vector2.ZERO or _pad_right_last != Vector2.ZERO:
		pad_flick.feed(r)
	_pad_right_last = r
	pad_flick.update()
	var a := _pad_button(JOY_BUTTON_A)
	if a and (not _pad_a_last or _push_phase < 0.0):
		_push_queued = true
	_pad_a_last = a
	var lt := _pad_axis(JOY_AXIS_TRIGGER_LEFT) > 0.5
	var rt := _pad_axis(JOY_AXIS_TRIGGER_RIGHT) > 0.5
	if lt and not _pad_lt_last:
		_pad_grab_hand = "f"
		_kb_grab_edge = true
	elif rt and not _pad_rt_last:
		_pad_grab_hand = "b"
		_kb_grab_edge = true
	_pad_lt_last = lt
	_pad_rt_last = rt


## Truco del stick derecho del mando (o "" si no hay).
func _consume_pad_flick() -> String:
	var id := pad_flick.consume()
	if id == "push":
		return "" # en el mando el stick arriba no empuja
	if id != "":
		flick.power = pad_flick.power
	return id


## Grab con gatillo: LT mano delantera (Melon, Nosegrab), RT mano trasera
## (Indy, Tailgrab, Stalefish). El stick izquierdo elige la variante.
func _pad_grab(move: Vector2) -> String:
	if _pad_grab_hand == "f":
		return "nosegrab" if move.y < -0.5 else "melon"
	if move.y > 0.5:
		return "tailgrab"
	return "stalefish" if move.x < -0.5 else "indy"


func _grab_held() -> bool:
	var pad_held := false
	if _pad_grab_hand == "f":
		pad_held = _pad_lt_last
	elif _pad_grab_hand == "b":
		pad_held = _pad_rt_last
	return _kb_grab_last or pad_held or (touch != null and touch.grab_held)


func _consume_grab_edge() -> bool:
	var e := _kb_grab_edge
	_kb_grab_edge = false
	if touch and touch.consume_grab():
		e = true
		_pad_grab_hand = ""
	return e


# ---------------------------------------------------------------- transformación y modelo

func _update_transform(delta: float) -> void:
	var target_up := _ground_n if state == State.RIDING else Vector3.UP
	var rate := 14.0 if state == State.RIDING else 3.0
	if state == State.AIR and _land_k > 0.0:
		target_up = Vector3.UP.lerp(_land_up, clampf(_land_k * 1.6, 0.0, 1.0)).normalized()
		rate = 9.0
	var k := 1.0 - exp(-delta * rate)
	_up = _up.lerp(target_up, k).normalized()
	var fwd := _forward(heading + _yaw_offset)
	var z := -(fwd - _up * fwd.dot(_up)).normalized()
	var x := _up.cross(z).normalized()
	basis = Basis(x, _up, z)


## Animación del truco, por fases (como en Skate 3):
##  1. Pop: el tail golpea el suelo, la tabla sube de morro y el cuerpo se estira.
##  2. Recogida: rodillas arriba, la tabla sube hacia los pies; en los flips los pies
##     se separan y la tabla gira rápido (empieza fuerte y frena al final).
##  3. Catch: en el punto más alto los pies atrapan la tabla de golpe (pequeño rebote
##     de la tabla y de las rodillas) y se mantiene planchada un instante.
##  4. Antes de tocar suelo las piernas se estiran; al aterrizar se flexionan según el golpe.
func _update_model(delta: float) -> void:
	_anim_t += delta
	if state != State.AIR:
		_spin_vel = lerpf(_spin_vel, 0.0, 1.0 - exp(-delta * 10.0))
	var tuck := 0.0
	var pitch := 0.0
	var lift := 0.0
	var gap := 0.0
	var flip_dir := 0.0
	var board_x := 0.0
	var pop_k := 0.0
	if state == State.AIR:
		var flip := 0.0
		var shove := 0.0
		var popped := not _trick.is_empty()
		var t := _trick_t if popped else _air_t
		if popped:
			# 1. pop: el tail (o el nose en nollie) golpea el suelo y se nivela en ~0.2 s
			var k := clampf(t / 0.2, 0.0, 1.0)
			pitch = 0.42 * sin(k * PI) * (1.0 - k * 0.3) * (-1.0 if _nollie else 1.0)
			# estirón explosivo del pop durante las primeras centésimas
			pop_k = 1.0 - smoothstep(0.0, 0.1, t)
			# 2. recogida rápida: rodillas muy arriba (como en la referencia de mocap)
			tuck = smoothstep(0.04, 0.16, t)
		else:
			tuck = smoothstep(0.0, 0.25, t) * 0.45
		var rise := 0.0
		if _flip_target > 0.0 or _shove_target > 0.0:
			flip_dir = _flip_dir
			flip = _flip_dir * _flip_done
			shove = _shove_dir * _shove_done
			# La tabla sube por delante de las piernas mientras gira (también en las
			# vueltas extra) y los pies se apartan por encima; al atraparla baja a los pies.
			_rise_k = move_toward(_rise_k, 0.0 if _caught else 1.0, delta * (5.0 if _caught else 8.0))
			var arc := smoothstep(0.0, 1.0, _rise_k)
			rise = arc * 0.2
			gap = arc * 0.12
			board_x = flip_dir * arc * 0.07
			# 3. catch: rebote corto de la tabla al quedar atrapada
			if _catch_time >= 0.0:
				var ct := _catch_time
				var wob := sin(ct * 38.0) * exp(-ct * 13.0)
				flip += _flip_dir * wob * 0.14
				shove += _shove_dir * wob * 0.1
				tuck = minf(tuck + exp(-ct * 9.0) * 0.25, 1.15)
		# 4. estirar las piernas antes de tocar suelo
		if vel.y < 0.0:
			var ground := park.height_at(position.x, position.z)
			var ttg := (position.y - ground) / -vel.y
			var ext := 1.0 - clampf((ttg - 0.06) / 0.22, 0.0, 1.0)
			tuck *= 1.0 - ext * 0.85
			gap *= 1.0 - ext
			rise *= 1.0 - ext
		lift = tuck * 0.22 + rise + 0.19 * absf(sin(pitch))
		model.set_trick_rotation(flip, shove)
	else:
		_rise_k = 0.0
	model.update_pose(delta, {
		"crouch": _crouch,
		"push": _push_phase,
		"lean": _lean,
		"air": state == State.AIR,
		"tuck": tuck,
		"pitch": pitch,
		"lift": lift,
		"gap": gap,
		"board_x": board_x,
		"flip_dir": flip_dir,
		"land": _land_comp,
		"pop": pop_k,
		"speed": current_speed() if state != State.AIR else 0.0,
		"grab": _grab_id,
		"grind": state == State.GRIND,
		"steer": _steer,
		"spin_vel": _spin_vel if state == State.AIR else _offset_vel * 0.5,
		"revert": sin(clampf(_revert_t / _revert_dur, 0.0, 1.0) * PI) if _revert_t >= 0.0 else 0.0,
		"catch_t": _catch_time if state == State.AIR else -1.0,
		"time": _anim_t,
		"brake": _brake_k if state == State.RIDING else 0.0,
	})

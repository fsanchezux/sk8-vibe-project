class_name FlickDetector
extends RefCounted
## Reconoce gestos estilo "Flick-it" de Skate 3 en el stick derecho.
## El stick es un Vector2 normalizado con y positiva hacia ABAJO (como la pantalla).
##
##   abajo -> arriba            = Ollie
##   abajo -> arriba-izquierda  = Kickflip
##   abajo -> arriba-derecha    = Heelflip
##   abajo -> izquierda/derecha = Pop Shove-it (BS / FS)
##   abajo -> lado -> arriba    = Varial Kickflip / Varial Heelflip
##   abajo -> lado -> diagonal del mismo lado = 360 Flip (izquierda) / Laser Flip (derecha)
##
## Los mismos gestos empezando hacia ARRIBA (arriba -> abajo...) son la versión nollie
## (pop con el pie delantero): ids con prefijo "nollie_".
## En táctil, un toque rápido o subir y volver al centro = empujar (FSA-164).
##
## Mantener el stick en la zona del truco después del flick sigue girando la tabla
## (doble, triple kickflip...; 360, 540 shove-it...) hasta que vuelve al centro:
## held_zone() dice en qué zona sigue.

enum Phase { NEUTRAL, PREP, SIDE, LOCKED }

const DEAD_ZONE := 0.3
const DOWN_ZONE := 0.6
const UP_ZONE := 0.5
const DIAGONAL := 0.4
const SIDE_WINDOW := 0.16
const NEUTRAL_GRACE := 0.22

## Si subir el stick y volver al centro cuenta como empujar (táctil sí, mando no).
var up_pushes := true
var phase := Phase.NEUTRAL
## Fuerza del pop del último truco (0..1), según lo rápido que fue el flick.
var power := 1.0

var _last := Vector2.ZERO
var _queued := ""
var _wind_t := 0.0
var _side_dir := 0
var _side_t := 0.0
var _neutral_t := -1.0
var _nollie := false
var _fired_nollie := false


func reset() -> void:
	phase = Phase.NEUTRAL
	_queued = ""
	_last = Vector2.ZERO
	_neutral_t = -1.0


func is_winding() -> bool:
	return phase == Phase.PREP or phase == Phase.SIDE


## Devuelve el id pendiente ("push" o un truco, o "") y lo vacía.
func consume() -> String:
	var t := _queued
	_queued = ""
	return t


## Encola una acción directamente (atajos de teclado).
func queue(id: String) -> void:
	if id != "push":
		power = 1.0
	_queued = id


## Toque rápido sin arrastrar en la mitad derecha = empujar.
func tap() -> void:
	if up_pushes and (phase == Phase.NEUTRAL or phase == Phase.LOCKED):
		_queued = "push"


## Zona en la que sigue el stick tras el flick: "flip_l", "flip_r", "side_l",
## "side_r" o "" (en el centro o en otra zona).
func held_zone() -> String:
	if phase != Phase.LOCKED or _last.length() < 0.55:
		return ""
	var vy := -_last.y if _fired_nollie else _last.y
	if vy < -0.3 and absf(_last.x) > 0.3:
		return "flip_l" if _last.x < 0.0 else "flip_r"
	if absf(_last.x) > 0.6 and absf(vy) < 0.6:
		return "side_l" if _last.x < 0.0 else "side_r"
	return ""


## Llamar cada frame para que funcionen los tiempos de espera.
func update() -> void:
	feed(_last)


## El dedo se ha levantado.
func release() -> void:
	if phase == Phase.SIDE:
		_fire("bs_shove" if _side_dir < 0 else "fs_shove", _now())
	elif phase == Phase.PREP and _nollie and up_pushes:
		_queued = "push"
	phase = Phase.NEUTRAL
	_last = Vector2.ZERO
	_neutral_t = -1.0


func feed(v: Vector2) -> void:
	var now := _now()
	_last = v
	var neutral := v.length() < DEAD_ZONE
	# vy > 0 = "cargando" (abajo en normal, arriba en nollie)
	var vy := -v.y if _nollie else v.y
	match phase:
		Phase.LOCKED:
			if neutral:
				phase = Phase.NEUTRAL
		Phase.NEUTRAL:
			if v.y > DOWN_ZONE:
				_start_prep(false, now)
			elif v.y < -DOWN_ZONE:
				_start_prep(true, now)
		Phase.PREP:
			if vy > DOWN_ZONE:
				_wind_t = now
				_neutral_t = -1.0
			elif vy < -UP_ZONE:
				var id := "ollie"
				if v.x < -DIAGONAL:
					id = "kickflip"
				elif v.x > DIAGONAL:
					id = "heelflip"
				_fire(id, now)
			elif absf(v.x) > DOWN_ZONE and vy < 0.5:
				phase = Phase.SIDE
				_side_dir = 1 if v.x > 0.0 else -1
				_side_t = now
			elif neutral:
				if _nollie and up_pushes:
					# Subir y volver al centro sin bajar = empujar
					_queued = "push"
					phase = Phase.NEUTRAL
				else:
					_check_neutral(now)
			else:
				_neutral_t = -1.0
		Phase.SIDE:
			if vy < -UP_ZONE:
				# Barrido hacia la diagonal del mismo lado = giro de 360 de la tabla
				var full := v.x * _side_dir > DIAGONAL
				if _side_dir < 0:
					_fire("tre_flip" if full else "varial_kickflip", now)
				else:
					_fire("laser_flip" if full else "varial_heelflip", now)
			elif now - _side_t > SIDE_WINDOW:
				_fire("bs_shove" if _side_dir < 0 else "fs_shove", now)


func _start_prep(nollie: bool, now: float) -> void:
	phase = Phase.PREP
	_nollie = nollie
	_wind_t = now
	_neutral_t = -1.0


func _check_neutral(now: float) -> void:
	# Pequeño margen para poder pasar por el centro (o soltar una tecla y pulsar otra).
	if _neutral_t < 0.0:
		_neutral_t = now
	elif now - _neutral_t > NEUTRAL_GRACE:
		phase = Phase.NEUTRAL
		_neutral_t = -1.0


func _fire(id: String, now: float) -> void:
	var dt := now - _wind_t
	power = clampf(1.0 - (dt - 0.05) / 0.3, 0.25, 1.0)
	_queued = ("nollie_" + id) if _nollie else id
	_fired_nollie = _nollie
	phase = Phase.LOCKED
	_neutral_t = -1.0


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0

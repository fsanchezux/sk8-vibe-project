class_name TouchControls
extends Control
## Dos sticks virtuales flotantes: aparecen donde pones el dedo (FSA-164).
## Mitad izquierda = movimiento lateral. Doble toque = grab (se mantiene mientras
##   el segundo toque siga apoyado; arrastrarlo elige el grab).
## Mitad derecha = empujar (flick arriba o toque) y trucos (ver FlickDetector).
## Los sticks son grises y casi transparentes para no tapar el juego (FSA-169). El
## derecho es más grande (más recorrido = más control de la altura del salto) y deja
## dibujado el trazo del dedo hasta que cae el truco, para ver qué gesto has hecho.

const RADIUS := 90.0
const KNOB_RADIUS := 38.0
const RADIUS_R := 130.0
const KNOB_RADIUS_R := 46.0
## Franja superior reservada para el HUD (pausa, tiempo, etc.).
const TOP_MARGIN := 170.0
const DOUBLE_TAP := 0.3
const TAP_TIME := 0.22

const INK := Color(0.2, 0.16, 0.24)
const GREY := Color(0.62, 0.62, 0.66)
const TRAIL := Color(1.0, 1.0, 1.0)
## Cuánto tarda el trazo en desvanecerse tras caer el truco.
const TRAIL_FADE := 0.45
## Si no llega a caer (o no hubo truco), el trazo se borra solo tras este tiempo.
const TRAIL_MAX_HOLD := 3.0

var left_vector := Vector2.ZERO
var right_vector := Vector2.ZERO
var flick: FlickDetector
## El dedo del doble toque sigue apoyado.
var grab_held := false

var _left_index := -1
var _left_origin := Vector2.ZERO
var _right_index := -1
var _right_origin := Vector2.ZERO
var _grab_edge := false
var _left_press_t := 0.0
var _left_release_t := -10.0
var _left_last_was_tap := false
var _right_press_t := 0.0
var _right_max_drag := 0.0
## Trazo del dedo derecho (posiciones en pantalla) y su opacidad.
var _trail := PackedVector2Array()
var _trail_alpha := 0.0
var _trail_hold_t := -1.0
var _trail_fading := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func reset() -> void:
	_left_index = -1
	_right_index = -1
	left_vector = Vector2.ZERO
	right_vector = Vector2.ZERO
	grab_held = false
	_grab_edge = false
	_left_last_was_tap = false
	_trail.clear()
	_trail_alpha = 0.0
	_trail_fading = false
	_trail_hold_t = -1.0
	if flick:
		flick.reset()
	queue_redraw()


## El truco ha caído (o te has caído): el trazo se desvanece.
func end_trail() -> void:
	if _right_index == -1 and _trail_alpha > 0.0:
		_trail_fading = true


func _process(delta: float) -> void:
	if _trail_alpha <= 0.0:
		return
	if _right_index == -1 and not _trail_fading:
		_trail_hold_t += delta
		if _trail_hold_t > TRAIL_MAX_HOLD:
			_trail_fading = true
	if _trail_fading:
		_trail_alpha = maxf(_trail_alpha - delta / TRAIL_FADE, 0.0)
		if _trail_alpha <= 0.0:
			_trail.clear()
		queue_redraw()


## El dedo izquierdo está apoyado (rodando = empujar sin parar).
func left_held() -> bool:
	return _left_index != -1 and not grab_held


## Devuelve true una vez por cada doble toque.
func consume_grab() -> bool:
	var e := _grab_edge
	_grab_edge = false
	return e


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var now := Time.get_ticks_msec() / 1000.0
	if event is InputEventScreenTouch:
		var half := get_viewport_rect().size.x * 0.5
		if event.pressed:
			if event.position.y < TOP_MARGIN:
				return
			if event.position.x < half and _left_index == -1:
				_left_index = event.index
				_left_origin = event.position
				left_vector = Vector2.ZERO
				if _left_last_was_tap and now - _left_release_t < DOUBLE_TAP:
					_grab_edge = true
					grab_held = true
				_left_press_t = now
			elif event.position.x >= half and _right_index == -1:
				_right_index = event.index
				_right_origin = event.position
				right_vector = Vector2.ZERO
				_right_press_t = now
				_right_max_drag = 0.0
				_trail = PackedVector2Array([event.position])
				_trail_alpha = 1.0
				_trail_fading = false
				_trail_hold_t = 0.0
		else:
			if event.index == _left_index:
				_left_index = -1
				left_vector = Vector2.ZERO
				# Un toque corto puede ser el primero de un doble toque (pero no el segundo).
				_left_last_was_tap = now - _left_press_t < TAP_TIME and not grab_held
				_left_release_t = now
				grab_held = false
			elif event.index == _right_index:
				_right_index = -1
				right_vector = Vector2.ZERO
				var tricked := false
				if flick:
					tricked = flick.phase in [FlickDetector.Phase.RISE, FlickDetector.Phase.SIDE, FlickDetector.Phase.LOCKED]
					flick.release()
					if now - _right_press_t < TAP_TIME and _right_max_drag < 0.3:
						flick.tap()
				# Sin truco (toque o empujar) no hay nada que esperar: se borra ya.
				if not tricked:
					_trail_fading = true
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _left_index:
			_left_origin = _follow(_left_origin, event.position, RADIUS)
			left_vector = (event.position - _left_origin) / RADIUS
			queue_redraw()
		elif event.index == _right_index:
			_right_origin = _follow(_right_origin, event.position, RADIUS_R)
			right_vector = (event.position - _right_origin) / RADIUS_R
			if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(event.position) > 4.0:
				_trail.append(event.position)
			_right_max_drag = maxf(_right_max_drag, right_vector.length())
			if flick:
				flick.feed(right_vector)
			queue_redraw()


## Si el dedo se pasa del radio, la base le sigue (stick flotante).
func _follow(origin: Vector2, pos: Vector2, radius: float) -> Vector2:
	var d := pos - origin
	if d.length() > radius:
		return pos - d.normalized() * radius
	return origin


func _draw() -> void:
	var size_v := get_viewport_rect().size
	var font := get_theme_default_font()
	_draw_stick(_left_index, _left_origin, left_vector, Vector2(size_v.x * 0.25, size_v.y * 0.84),
		RADIUS, KNOB_RADIUS, "girar · remar", "mantén para remar · 2 toques: grab", font, grab_held)
	_draw_stick(_right_index, _right_origin, right_vector, Vector2(size_v.x * 0.75, size_v.y * 0.82),
		RADIUS_R, KNOB_RADIUS_R, "empujar ↑", "↓↑ trucos", font, false)
	_draw_trail()


func _draw_stick(index: int, origin: Vector2, vec: Vector2, idle_pos: Vector2, radius: float,
		knob_radius: float, label: String, hint: String, font: Font, active: bool) -> void:
	if index == -1:
		draw_arc(idle_pos, radius, 0.0, TAU, 64, Color(GREY, 0.18), 2.0, true)
		_text(font, idle_pos + Vector2(0, -4), label, 24, Color(1, 1, 1, 0.45))
		_text(font, idle_pos + Vector2(0, 26), hint, 18, Color(1, 1, 1, 0.3))
		return
	draw_circle(origin, radius, Color(GREY, 0.07))
	draw_arc(origin, radius, 0.0, TAU, 64, Color(GREY, 0.22), 2.0, true)
	var knob := origin + vec.limit_length(1.0) * radius
	# Con el grab activo el pomo se marca un poco más para saber que está cogido.
	draw_circle(knob, knob_radius, Color(GREY, 0.45 if active else 0.22))


## Trazo lineal del dedo derecho desde que lo apoyas hasta que cae el truco.
func _draw_trail() -> void:
	if _trail.size() < 2 or _trail_alpha <= 0.0:
		return
	draw_polyline(_trail, Color(INK, 0.25 * _trail_alpha), 9.0, true)
	draw_polyline(_trail, Color(TRAIL, 0.75 * _trail_alpha), 5.0, true)
	draw_circle(_trail[0], 7.0, Color(TRAIL, 0.75 * _trail_alpha))
	var tip := _trail[_trail.size() - 1]
	draw_circle(tip, 9.0, Color(TRAIL, 0.9 * _trail_alpha))


func _text(font: Font, center: Vector2, text: String, fs: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var p := center + Vector2(-w * 0.5, fs * 0.35)
	draw_string(font, p + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, color.a * 0.5))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

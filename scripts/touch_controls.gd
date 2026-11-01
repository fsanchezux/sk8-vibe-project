class_name TouchControls
extends Control
## Dos sticks virtuales flotantes: aparecen donde pones el dedo (FSA-164).
## Mitad izquierda = movimiento lateral. Doble toque = grab (se mantiene mientras
##   el segundo toque siga apoyado; arrastrarlo elige el grab).
## Mitad derecha = empujar (flick arriba o toque) y trucos (ver FlickDetector).

const RADIUS := 90.0
const KNOB_RADIUS := 38.0
## Franja superior reservada para el HUD (pausa, tiempo, etc.).
const TOP_MARGIN := 170.0
const DOUBLE_TAP := 0.3
const TAP_TIME := 0.22

const INK := Color(0.2, 0.16, 0.24)
const YELLOW := Color(0.95, 0.47, 0.4)

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
	if flick:
		flick.reset()
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
				if flick:
					flick.release()
					if now - _right_press_t < TAP_TIME and _right_max_drag < 0.3:
						flick.tap()
		queue_redraw()
	elif event is InputEventScreenDrag:
		if event.index == _left_index:
			_left_origin = _follow(_left_origin, event.position)
			left_vector = (event.position - _left_origin) / RADIUS
			queue_redraw()
		elif event.index == _right_index:
			_right_origin = _follow(_right_origin, event.position)
			right_vector = (event.position - _right_origin) / RADIUS
			_right_max_drag = maxf(_right_max_drag, right_vector.length())
			if flick:
				flick.feed(right_vector)
			queue_redraw()


## Si el dedo se pasa del radio, la base le sigue (stick flotante).
func _follow(origin: Vector2, pos: Vector2) -> Vector2:
	var d := pos - origin
	if d.length() > RADIUS:
		return pos - d.normalized() * RADIUS
	return origin


func _draw() -> void:
	var size_v := get_viewport_rect().size
	var font := get_theme_default_font()
	_draw_stick(_left_index, _left_origin, left_vector, Vector2(size_v.x * 0.25, size_v.y * 0.84),
		"girar · remar", "mantén para remar · 2 toques: grab", font, grab_held)
	_draw_stick(_right_index, _right_origin, right_vector, Vector2(size_v.x * 0.75, size_v.y * 0.84),
		"empujar ↑", "↓↑ trucos", font, false)


func _draw_stick(index: int, origin: Vector2, vec: Vector2, idle_pos: Vector2, label: String, hint: String, font: Font, active: bool) -> void:
	if index == -1:
		draw_arc(idle_pos, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.35), 2.5, true)
		_text(font, idle_pos + Vector2(0, -4), label, 24, Color(1, 1, 1, 0.7))
		_text(font, idle_pos + Vector2(0, 26), hint, 18, Color(1, 1, 1, 0.5))
		return
	draw_circle(origin, RADIUS, Color(INK, 0.18))
	draw_arc(origin, RADIUS, 0.0, TAU, 64, Color(1, 1, 1, 0.5), 2.5, true)
	var knob := origin + vec.limit_length(1.0) * RADIUS
	draw_circle(knob, KNOB_RADIUS, YELLOW if active else Color(1, 1, 1, 0.85))


func _text(font: Font, center: Vector2, text: String, fs: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
	var p := center + Vector2(-w * 0.5, fs * 0.35)
	draw_string(font, p + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(INK, color.a * 0.5))
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

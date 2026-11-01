class_name GameUI
extends CanvasLayer
## Interfaz minimalista con Nunito ExtraBold: pantalla de entrada con el ambiente del
## proyecto (SK8_VIBE/PROJECT sobre el atardecer) en la que basta tocar para entrar
## con un fundido, HUD discreto, pausa y resultados. La escena 3D siempre se ve detrás.

signal start_requested
signal pause_requested
signal resume_requested
signal restart_requested
signal menu_requested
signal quit_requested
signal back_requested
## Botones del punto de reset (FSA-169).
signal spot_mark_requested
signal spot_return_requested

const FONT := preload("res://assets/fonts/Nunito-ExtraBold.ttf")
const FONT_LOGO := preload("res://assets/fonts/Nunito-Black.ttf")
const TITLE := "SK8_VIBE/PROJECT"

const CREAM := Color(1.0, 0.93, 0.91)
const INK := Color(0.12, 0.08, 0.18)
const SHADE := Color(0.1, 0.06, 0.16, 0.35)
const CORAL := Color(1.0, 0.5, 0.55)
const YELLOW := Color(1.0, 0.86, 0.7)
const RED := Color(1.0, 0.55, 0.55)

var touch: TouchControls

var _theme := Theme.new()
var _menu: Control
var _hud: Control
var _pause: Control
var _results: Control
var _fade: ColorRect
var _hint: Label
var _menu_best: Label
var _score_label: Label
var _time_label: Label
var _time_blink := false
var _combo_label: Label
var _combo_value: Label
var _trick_label: Label
var _trick_tween: Tween
var _trick_y := 0.0
var _res_score: Label
var _res_best: Label
var _res_combo: Label
var _res_record: Label
var _pause_first: Button
var _results_first: Button
var _fading := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_theme.default_font = FONT
	_theme.default_font_size = 30
	touch = TouchControls.new()
	touch.process_mode = Node.PROCESS_MODE_PAUSABLE
	touch.theme = _theme
	add_child(touch)
	_hud = _build_hud()
	_pause = _build_pause()
	_results = _build_results()
	_menu = _build_menu()
	_fade = ColorRect.new()
	_fade.color = Color(INK, 0.0)
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		back_requested.emit()
		return
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_START and not _menu.visible:
		back_requested.emit()
		return
	# Pantalla de entrada: cualquier toque, clic, tecla o botón entra al juego
	if _menu.visible and not _fading and _is_press(event):
		start_requested.emit()


func _is_press(e: InputEvent) -> bool:
	if e is InputEventScreenTouch or e is InputEventMouseButton or e is InputEventJoypadButton:
		return e.pressed
	if e is InputEventKey:
		return e.pressed and not e.echo
	return false


## Fundido: oscurece, ejecuta `action` (p. ej. empezar la partida) y vuelve a aclarar.
func fade_through(action: Callable) -> void:
	if _fading:
		return
	_fading = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 0.45).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(action)
	tw.tween_interval(0.1)
	tw.tween_property(_fade, "color:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func(): _fading = false)


func show_menu(best: int) -> void:
	_menu_best.text = "récord  %d" % best if best > 0 else ""
	_show(_menu)
	touch.hide()
	touch.reset()


func show_playing() -> void:
	_show(_hud)
	touch.show()
	touch.reset()


func show_pause() -> void:
	_pause.show()
	_focus_first(_pause_first)
	touch.hide()
	touch.reset()


func show_results(score: int, best: int, best_combo: int, record: bool) -> void:
	_res_score.text = str(score)
	_res_best.text = "récord  %d" % best
	_res_combo.text = "mejor combo  %d" % best_combo
	_res_record.visible = record
	_show(_results)
	_focus_first(_results_first)
	touch.hide()
	touch.reset()
	_res_score.modulate.a = 0.0
	create_tween().tween_property(_res_score, "modulate:a", 1.0, 0.6)


func set_score(score: int) -> void:
	_score_label.text = str(score)


func set_time(seconds: float) -> void:
	var s := int(ceil(seconds))
	_time_label.text = "%d:%02d" % [s / 60, s % 60]
	var blink := seconds <= 10.0 and seconds > 0.0 and fmod(seconds, 1.0) > 0.5
	if blink != _time_blink:
		_time_blink = blink
		_time_label.add_theme_color_override("font_color", CORAL if blink else CREAM)


## Combo en marcha: trucos encadenados y "puntos × multiplicador".
func set_combo(text: String, base: int, mult: int) -> void:
	_combo_label.text = text.to_lower()
	_combo_value.text = "" if mult == 0 else "%d × %d" % [base, mult]


func popup_trick(text: String, color := Color.WHITE) -> void:
	_trick_label.text = text.to_lower()
	_trick_label.modulate = Color(color, 0.0)
	_trick_label.position.y = _trick_y + 24.0
	if _trick_tween:
		_trick_tween.kill()
	_trick_tween = create_tween()
	_trick_tween.set_parallel(true)
	_trick_tween.tween_property(_trick_label, "modulate:a", 1.0, 0.2)
	_trick_tween.tween_property(_trick_label, "position:y", _trick_y, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_trick_tween.chain().tween_interval(0.9)
	_trick_tween.chain().tween_property(_trick_label, "modulate:a", 0.0, 0.6)


func _process(_delta: float) -> void:
	if _menu.visible and _hint:
		_hint.modulate.a = 0.45 + 0.35 * sin(Time.get_ticks_msec() / 1000.0 * 2.2)


func _show(screen: Control) -> void:
	for c in [_menu, _hud, _pause, _results]:
		c.visible = c == screen


func _focus_first(b: Button) -> void:
	if not Input.get_connected_joypads().is_empty():
		b.call_deferred("grab_focus")


# ---------------------------------------------------------------- pantallas

## Pantalla de entrada: el atardecer del park de fondo, el título y "toca para empezar".
func _build_menu() -> Control:
	var root := _screen(Control.MOUSE_FILTER_IGNORE)
	root.add_child(_gradient(0.55, 0.0, 0.6))
	var logo := _label(TITLE, 62, CREAM)
	logo.add_theme_font_override("font", FONT_LOGO)
	logo.add_theme_color_override("font_shadow_color", Color(0.55, 0.2, 0.35, 0.45))
	logo.add_theme_constant_override("shadow_offset_y", 4)
	logo.add_theme_constant_override("shadow_outline_size", 10)
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -360
	logo.offset_right = 360
	logo.offset_top = 150
	root.add_child(logo)
	_menu_best = _label("", 24, Color(CREAM, 0.75))
	_menu_best.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_menu_best.offset_left = -300
	_menu_best.offset_right = 300
	_menu_best.offset_top = 240
	root.add_child(_menu_best)
	_hint = _label("toca para empezar", 26, CREAM)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -300
	_hint.offset_right = 300
	_hint.offset_top = -170
	_hint.offset_bottom = -120
	root.add_child(_hint)
	return root


func _build_hud() -> Control:
	var root := _screen(Control.MOUSE_FILTER_IGNORE)
	var score_box := VBoxContainer.new()
	score_box.position = Vector2(40, 54)
	score_box.add_theme_constant_override("separation", -10)
	root.add_child(score_box)
	var cap := _label("puntos", 20, Color(CREAM, 0.7))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_box.add_child(cap)
	_score_label = _label("0", 48, CREAM)
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	score_box.add_child(_score_label)

	_time_label = _label("2:00", 40, CREAM)
	_time_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_time_label.offset_left = -100
	_time_label.offset_right = 100
	_time_label.offset_top = 62
	root.add_child(_time_label)

	var pause_btn := _round_button("II", func(): pause_requested.emit())
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.offset_left = -120
	pause_btn.offset_right = -40
	pause_btn.offset_top = 56
	pause_btn.offset_bottom = 136
	root.add_child(pause_btn)

	# Punto de reset: "fijar" lo pone donde estás y "volver" te devuelve allí.
	# Van en la franja superior, donde los sticks no reciben toques.
	var back_btn := _round_button("volver", func(): spot_return_requested.emit())
	back_btn.add_theme_font_size_override("font_size", 18)
	back_btn.custom_minimum_size = Vector2(72, 72)
	back_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	back_btn.offset_left = -204
	back_btn.offset_right = -132
	back_btn.offset_top = 60
	back_btn.offset_bottom = 132
	root.add_child(back_btn)
	var mark_btn := _round_button("fijar", func(): spot_mark_requested.emit())
	mark_btn.add_theme_font_size_override("font_size", 18)
	mark_btn.custom_minimum_size = Vector2(72, 72)
	mark_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	mark_btn.offset_left = -288
	mark_btn.offset_right = -216
	mark_btn.offset_top = 60
	mark_btn.offset_bottom = 132
	root.add_child(mark_btn)

	_combo_label = _label("", 26, Color(CREAM, 0.85))
	_combo_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_label.offset_left = -330
	_combo_label.offset_right = 330
	_combo_label.offset_top = 170
	_combo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_combo_label)
	_combo_value = _label("", 36, YELLOW)
	_combo_value.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_combo_value.offset_left = -200
	_combo_value.offset_right = 200
	_combo_value.offset_top = 240
	root.add_child(_combo_value)

	_trick_label = _label("", 46, Color.WHITE)
	_trick_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_trick_label.offset_left = -330
	_trick_label.offset_right = 330
	_trick_label.offset_top = 330
	_trick_label.offset_bottom = 480
	_trick_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_trick_label.modulate.a = 0.0
	root.add_child(_trick_label)
	_trick_y = _trick_label.position.y
	return root


func _build_pause() -> Control:
	var root := _screen(Control.MOUSE_FILTER_STOP)
	root.add_child(_dim(0.5))
	var box := _center_box(root)
	box.add_child(_label("pausa", 56, CREAM))
	box.add_child(_spacer(30))
	_pause_first = _button("continuar", func(): resume_requested.emit(), true)
	box.add_child(_pause_first)
	box.add_child(_button("reiniciar", func(): restart_requested.emit()))
	box.add_child(_button("inicio", func(): menu_requested.emit()))
	return root


func _build_results() -> Control:
	var root := _screen(Control.MOUSE_FILTER_STOP)
	root.add_child(_gradient(0.35, 0.2, 0.75))
	var box := _center_box(root)
	box.add_child(_label("se acabó el tiempo", 26, Color(CREAM, 0.75)))
	_res_score = _label("0", 110, CREAM)
	box.add_child(_res_score)
	_res_record = _label("nuevo récord", 28, CORAL)
	box.add_child(_res_record)
	_res_best = _label("", 24, CREAM)
	box.add_child(_res_best)
	_res_combo = _label("", 22, Color(CREAM, 0.75))
	box.add_child(_res_combo)
	box.add_child(_spacer(50))
	_results_first = _button("otra vez", func(): restart_requested.emit(), true)
	box.add_child(_results_first)
	box.add_child(_button("inicio", func(): menu_requested.emit()))
	return root


# ---------------------------------------------------------------- piezas

func _screen(filter: Control.MouseFilter) -> Control:
	var c := Control.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = filter
	c.theme = _theme
	add_child(c)
	return c


func _dim(alpha: float) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(INK, alpha)
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Degradado vertical: arriba, centro y abajo con su opacidad.
func _gradient(top: float, mid: float, bottom: float) -> TextureRect:
	var g := Gradient.new()
	g.set_color(0, Color(INK, top))
	g.set_color(1, Color(INK, bottom))
	g.add_point(0.5, Color(INK, mid))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _center_box(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(box)
	return box


func _spacer(h: float) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, font_size / 20))
	l.add_theme_constant_override("shadow_outline_size", maxi(4, font_size / 8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, cb: Callable, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(420, 90)
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", 32)
	var fg := INK if primary else CREAM
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, fg)
	var bg := CREAM if primary else Color(CREAM, 0.0)
	b.add_theme_stylebox_override("normal", _style(bg, not primary))
	b.add_theme_stylebox_override("hover", _style(bg.lightened(0.05) if primary else Color(CREAM, 0.08), not primary))
	b.add_theme_stylebox_override("pressed", _style(CORAL if primary else Color(CREAM, 0.18), not primary))
	var focus := _style(Color(0, 0, 0, 0), true)
	focus.border_color = CORAL
	focus.set_border_width_all(4)
	b.add_theme_stylebox_override("focus", focus)
	b.pressed.connect(cb)
	return b


func _round_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(80, 80)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 32)
	for k in ["font_color", "font_hover_color", "font_pressed_color"]:
		b.add_theme_color_override(k, CREAM)
	b.add_theme_stylebox_override("normal", _style(SHADE, false))
	b.add_theme_stylebox_override("hover", _style(Color(SHADE, 0.5), false))
	b.add_theme_stylebox_override("pressed", _style(Color(CORAL, 0.7), false))
	b.pressed.connect(cb)
	return b


func _style(color: Color, outline: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(46)
	if outline:
		s.border_color = Color(CREAM, 0.5)
		s.set_border_width_all(3)
	return s

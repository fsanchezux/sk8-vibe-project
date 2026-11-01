extends Node3D
## Punto de entrada: crea el skatepark, el skater, la cámara y la UI, y gestiona
## los estados MENÚ / JUGANDO / PAUSA / RESULTADOS.
## Modo de juego (FSA-165): sesión de 2 minutos para hacer el máximo de puntos.

enum GameState { MENU, PLAYING, PAUSED, RESULTS }

const SESSION_TIME := 120.0
## Tiempo rodando tras aterrizar antes de cerrar el combo (margen para encadenar).
const COMBO_END_DELAY := 0.5
const RECORDS_PATH := "user://records.cfg"
const MUSIC_PATH := "res://assets/audio/ambient.mp3"
## Cámara lenta en los trucos: cuánto se frena el tiempo como máximo (0.2 = al 80 %).
const SLOWMO := 0.2
## Con un combo largo la cámara lenta crece hasta este máximo (FSA-203, de prueba).
const SLOWMO_MAX := 0.45
## Trucos encadenados con los que se alcanza SLOWMO_MAX.
const SLOWMO_FULL_COMBO := 7

var state := GameState.MENU
var score := 0
var time_left := SESSION_TIME
var best_score := 0
var best_combo := 0

var park: Skatepark
var skater: Skater
var camera: ChaseCamera
var ui: GameUI
var combo := Combo.new()
var _ground_t := -1.0
var _spot_marker: MeshInstance3D


func _ready() -> void:
	_load_records()
	_build_world()

	park = Skatepark.new()
	# Módulos colocados a mano en el nodo "Modules" de main.tscn
	var modules_root := get_node_or_null("Modules")
	if modules_root:
		for m in modules_root.get_children():
			if m is ParkModule:
				park.modules.append(m)
	add_child(park)
	var props := StreetProps.new()
	props.park = park
	add_child(props)

	var marks := SkidMarks.new()
	add_child(marks)

	skater = Skater.new()
	skater.park = park
	skater.skid_marks = marks
	add_child(skater)
	skater.trick_done.connect(_on_trick_done)
	skater.landed.connect(_on_landed)
	skater.bailed.connect(_on_bailed)

	camera = ChaseCamera.new()
	camera.target = skater
	add_child(camera)
	skater.impact.connect(camera.kick)

	ui = GameUI.new()
	add_child(ui)
	skater.touch = ui.touch
	ui.touch.flick = skater.flick
	skater.landed.connect(ui.touch.end_trail)
	skater.bailed.connect(ui.touch.end_trail)
	ui.spot_mark_requested.connect(_mark_spot)
	ui.spot_return_requested.connect(_return_to_spot)

	ui.start_requested.connect(func(): ui.fade_through(_start))
	ui.pause_requested.connect(_pause)
	ui.resume_requested.connect(_resume)
	ui.restart_requested.connect(func(): ui.fade_through(_start))
	ui.menu_requested.connect(func(): ui.fade_through(_go_menu))
	ui.quit_requested.connect(_quit)
	ui.back_requested.connect(_on_back)

	_go_menu()


func _process(delta: float) -> void:
	if state != GameState.PLAYING:
		return
	# El cronómetro va en tiempo real aunque haya cámara lenta.
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	time_left = maxf(time_left - real_dt, 0.0)
	ui.set_time(time_left)
	_update_slowmo(real_dt)

	# Salir por la abertura del este: vuelta al principio con la misma velocidad.
	if skater.position.x > Skatepark.EXIT_X:
		skater.teleport_to(park.spawn_pos, park.spawn_yaw)
		ui.touch.reset()
		camera.snap()

	# El combo se cierra al rodar un momento sin encadenar otro truco.
	if combo.active() and _ground_t >= 0.0 and skater.state == Skater.State.RIDING:
		_ground_t += delta
		if _ground_t >= COMBO_END_DELAY:
			_bank_combo()

	if time_left <= 0.0:
		_finish()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			_on_back()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			if state == GameState.PLAYING:
				_pause()


## Ralentiza muy ligeramente el tiempo mientras se hace un truco (entra y sale suave).
## El sonido baja un poco de tono con él. Cuantos más trucos seguidos, más se nota.
func _update_slowmo(real_dt: float) -> void:
	var chain := clampf(float(combo.multiplier() - 1) / float(SLOWMO_FULL_COMBO - 1), 0.0, 1.0)
	var target := 1.0 - lerpf(SLOWMO, SLOWMO_MAX, chain) * skater.trick_focus()
	Engine.time_scale = lerpf(Engine.time_scale, target, 1.0 - exp(-real_dt * 7.0))
	AudioServer.playback_speed_scale = lerpf(1.0, Engine.time_scale, 0.5)


func _reset_slowmo() -> void:
	Engine.time_scale = 1.0
	AudioServer.playback_speed_scale = 1.0


# ---------------------------------------------------------------- estados

func _go_menu() -> void:
	_reset_slowmo()
	get_tree().paused = false
	state = GameState.MENU
	skater.input_enabled = false
	skater.reset_skater(park.spawn_pos, park.spawn_yaw)
	if _spot_marker:
		_spot_marker.visible = false
	camera.orbit = true
	camera.snap()
	ui.show_menu(best_score)


func _start() -> void:
	_reset_slowmo()
	get_tree().paused = false
	state = GameState.PLAYING
	score = 0
	time_left = SESSION_TIME
	combo.clear()
	_ground_t = -1.0
	ui.set_score(score)
	ui.set_time(time_left)
	ui.set_combo("", 0, 0)
	skater.reset_skater(park.spawn_pos, park.spawn_yaw)
	skater.mark_spot(true)
	_place_spot_marker()
	skater.input_enabled = true
	camera.orbit = false
	camera.snap()
	ui.show_playing()


func _pause() -> void:
	if state != GameState.PLAYING:
		return
	state = GameState.PAUSED
	_reset_slowmo()
	get_tree().paused = true
	ui.show_pause()


func _resume() -> void:
	if state != GameState.PAUSED:
		return
	state = GameState.PLAYING
	get_tree().paused = false
	skater.flick.reset()
	ui.show_playing()


func _finish() -> void:
	_reset_slowmo()
	state = GameState.RESULTS
	skater.input_enabled = false
	# El combo que esté en marcha cuenta si no te has caído.
	if combo.active() and skater.state != Skater.State.BAIL:
		_bank_combo()
	combo.clear()
	var record := score > best_score
	best_score = maxi(best_score, score)
	_save_records()
	ui.show_results(score, best_score, best_combo, record)


func _quit() -> void:
	get_tree().quit()


func _on_back() -> void:
	match state:
		GameState.PLAYING:
			_pause()
		GameState.PAUSED:
			_resume()
		GameState.RESULTS:
			_go_menu()
		GameState.MENU:
			_quit()


# ---------------------------------------------------------------- puntos

func _on_trick_done(trick_name: String, points: int) -> void:
	if state != GameState.PLAYING:
		return
	combo.add(trick_name, points)
	_ground_t = -1.0
	ui.set_combo(combo.label(), combo.base, combo.multiplier())


func _on_landed() -> void:
	_ground_t = 0.0
	# A partir de x3, cada truco que cae suena (sin chispas)
	if state == GameState.PLAYING and combo.multiplier() >= 3:
		skater.celebrate(combo.multiplier())


## Punto de reset en teclado: F = fijar, R = volver. En mando: Back/Select = fijar, Y = volver.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			_mark_spot()
		elif event.physical_keycode == KEY_R:
			_return_to_spot()
	elif event is InputEventJoypadButton and event.pressed:
		if event.button_index == JOY_BUTTON_BACK:
			_mark_spot()
		elif event.button_index == JOY_BUTTON_Y:
			_return_to_spot()


func _mark_spot() -> void:
	if state != GameState.PLAYING:
		return
	if skater.mark_spot():
		_place_spot_marker()
		ui.popup_trick("SPOT FIJADO", GameUI.YELLOW)


## Aro amarillo en el suelo que enseña dónde está el punto de reset.
func _place_spot_marker() -> void:
	if _spot_marker == null:
		var ring := TorusMesh.new()
		ring.inner_radius = 0.55
		ring.outer_radius = 0.7
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.2, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ring.material = mat
		_spot_marker = MeshInstance3D.new()
		_spot_marker.mesh = ring
		_spot_marker.scale = Vector3(1.0, 0.05, 1.0)
		add_child(_spot_marker)
	_spot_marker.position = skater.spot_position() + Vector3(0.0, 0.03, 0.0)
	_spot_marker.visible = true


## Volver al spot pierde el combo en curso (si no, se podría encadenar sin fin) y no
## se puede hacer en mitad de un truco.
func _return_to_spot() -> void:
	if state != GameState.PLAYING or not skater.can_return_to_spot():
		return
	combo.clear()
	_ground_t = -1.0
	ui.set_combo("", 0, 0)
	ui.touch.reset()
	skater.go_to_spot()
	camera.snap()


func _on_bailed() -> void:
	if state != GameState.PLAYING:
		return
	combo.clear()
	_ground_t = -1.0
	ui.set_combo("", 0, 0)
	ui.popup_trick("¡BAIL!", GameUI.RED)


func _bank_combo() -> void:
	var pts := combo.total()
	var mult := combo.multiplier()
	score += pts
	best_combo = maxi(best_combo, pts)
	ui.set_score(score)
	if mult > 1:
		ui.popup_trick("COMBO x%d\n+%d" % [mult, pts], GameUI.YELLOW)
	else:
		ui.popup_trick("%s\n+%d" % [combo.tricks[0], pts], Color.WHITE)
	combo.clear()
	_ground_t = -1.0
	ui.set_combo("", 0, 0)


func _load_records() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RECORDS_PATH) == OK:
		best_score = int(cfg.get_value("records", "best_score", 0))


func _save_records() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("records", "best_score", best_score)
	cfg.save(RECORDS_PATH)


# ---------------------------------------------------------------- mundo

func _build_world() -> void:
	# Atardecer tranquilo en estilo low-poly: cielo lavanda a melocotón, sol bajo y
	# cálido con sombras largas y suaves, luz ambiente violeta del cielo, neblina
	# que funde el fondo y un poco de brillo en las luces.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky_mat := ProceduralSkyMaterial.new()
	# Atardecer: violeta arriba, rosa y naranja intenso en el horizonte, sol grande y bajo
	sky_mat.sky_top_color = Color(0.11, 0.1, 0.28)
	sky_mat.sky_horizon_color = Color(0.98, 0.4, 0.5)
	sky_mat.ground_horizon_color = Color(0.98, 0.4, 0.5)
	sky_mat.ground_bottom_color = Color(0.18, 0.12, 0.22)
	sky_mat.sky_curve = 0.09
	sky_mat.sun_angle_max = 14.0
	sky_mat.sun_curve = 0.08
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.36, 0.3, 0.5)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.fog_enabled = true
	env.fog_light_color = Color(0.9, 0.45, 0.48)
	env.fog_density = 0.0024
	env.fog_sun_scatter = 0.2
	env.fog_sky_affect = 0.1
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.05
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.12
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-9.0, -24.0, 0.0)
	sun.light_color = Color(1.0, 0.55, 0.38)
	sun.light_energy = 1.05
	sun.shadow_enabled = true
	sun.shadow_blur = 1.6
	sun.directional_shadow_max_distance = 50.0
	add_child(sun)

	add_child(Scenery.new())

	# Música ambiente del proyecto (assets/audio/ambient.mp3) en bucle. Sigue sonando
	# en pausa y en los menús.
	var music_stream: AudioStream = null
	if ResourceLoader.exists(MUSIC_PATH):
		music_stream = load(MUSIC_PATH)
		if music_stream is AudioStreamMP3:
			(music_stream as AudioStreamMP3).loop = true
	if music_stream:
		var music := AudioStreamPlayer.new()
		music.stream = music_stream
		music.volume_db = -6.0
		music.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(music)
		music.play()

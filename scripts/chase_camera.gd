class_name ChaseCamera
extends Camera3D
## Cámara baja detrás del skater, con algo de retraso en el giro (estilo Skate 3).
## En vertical usamos FOV horizontal fijo para que se vea bien lo que hay delante.
## En el aire mantiene la dirección (no da la vuelta en los quarters hasta aterrizar),
## no se mete dentro de rampas ni paredes, y tiembla un poco con los golpes.
## Desenfoca el fondo (profundidad de campo) para el aire de maqueta low-poly.

var target: Skater
var distance := 2.8
var height := 1.45
var look_ahead := 1.2
## En el menú la cámara orbita lentamente alrededor del skater.
var orbit := false

var _yaw := 0.0
var _y := 0.0
var _orbit_angle := 0.0
var _shake := 0.0
var _dip := 0.0
var _focus := 0.0
var _rng := RandomNumberGenerator.new()
var _play_attr: CameraAttributesPractical
var _menu_attr: CameraAttributesPractical


func _ready() -> void:
	# Se mueve en _process leyendo la posición ya interpolada del skater.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	keep_aspect = Camera3D.KEEP_WIDTH
	fov = 68.0
	near = 0.05
	far = 500.0
	current = true
	_play_attr = _dof(22.0, 30.0)
	_menu_attr = _dof(30.0, 45.0)
	attributes = _play_attr


func _dof(distance: float, transition: float) -> CameraAttributesPractical:
	var a := CameraAttributesPractical.new()
	a.dof_blur_far_enabled = true
	a.dof_blur_far_distance = distance
	a.dof_blur_far_transition = transition
	a.dof_blur_amount = 0.08
	return a


## Plano de la pantalla de entrada: a ras de suelo mirando al atardecer, con las
## farolas y el park, y una deriva lateral muy lenta.
func _title_shot(delta: float) -> void:
	_orbit_angle += delta * 0.05
	global_position = Vector3(-4.0 + sin(_orbit_angle) * 3.0, 7.0, -15.5)
	look_at(Vector3(-1.0 + sin(_orbit_angle) * 1.5, 2.0, 16.0), Vector3.UP)
	fov = 58.0
	attributes = _menu_attr


## Golpe de cámara (pop, aterrizaje, bail).
func kick(strength: float) -> void:
	_shake = maxf(_shake, strength * 0.06)
	_dip = maxf(_dip, strength * 0.12)


func snap() -> void:
	if not target:
		return
	_orbit_angle = 0.0
	_yaw = _desired_yaw()
	_y = target.global_position.y + height
	_update(0.0, true)


func _process(delta: float) -> void:
	if target:
		_update(delta, false)


func _desired_yaw() -> float:
	if orbit:
		return target.heading + 2.3 + _orbit_angle
	return target.cam_heading


func _update(delta: float, instant: bool) -> void:
	if orbit:
		_title_shot(delta)
		return
	var tpos := target.get_global_transform_interpolated().origin
	if orbit:
		_orbit_angle += delta * 0.25
	var follow := 1.0 if instant else 1.0 - exp(-delta * (3.5 if not orbit else 20.0))
	_yaw = lerp_angle(_yaw, _desired_yaw(), follow)
	var back := Vector3(sin(_yaw), 0.0, cos(_yaw))
	var dist := 3.0 if orbit else distance
	var cam := tpos + back * dist + Vector3.UP * height
	_y = lerpf(_y, cam.y, 1.0 if instant else 1.0 - exp(-delta * 5.0))
	cam.y = _y

	# Dentro de la nave y por encima del suelo/rampas que haya bajo la cámara
	var park := target.park
	if park:
		cam.x = clampf(cam.x, -Skatepark.HALF_X + 0.4, Skatepark.HALF_X - 0.4)
		cam.z = clampf(cam.z, -Skatepark.HALF_Z + 0.4, Skatepark.HALF_Z - 0.4)
		cam.y = clampf(cam.y, park.height_at(cam.x, cam.z) + 0.5, Skatepark.WALL_H - 0.8)

	_shake = move_toward(_shake, 0.0, delta * 0.25)
	_dip = lerpf(_dip, 0.0, 1.0 - exp(-delta * 8.0))
	var jitter := Vector3(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1), 0.0) * _shake
	global_position = cam + jitter + Vector3.DOWN * _dip
	var look := tpos - back * (0.0 if orbit else look_ahead) + Vector3.UP * (1.0 if orbit else 0.55)
	look_at(look, Vector3.UP)
	attributes = _menu_attr if orbit else _play_attr
	if orbit:
		fov = 52.0
	else:
		# Leve acercamiento durante la cámara lenta de los trucos
		_focus = lerpf(_focus, target.trick_focus(), 1.0 - exp(-delta * 6.0))
		fov = lerpf(68.0, 78.0, clampf(target.current_speed() / target.max_speed, 0.0, 1.0)) - _focus * 5.0

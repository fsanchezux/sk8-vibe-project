class_name SkaterModel
extends Node3D
## Skater: personaje low-poly del kit "Creative Character" (CharacterRig) sobre una
## tabla low-poly. Toda la pose se calcula aquí con IK en el "espacio del rider":
## el rider mira a +X, la tabla va a lo largo de Z y se avanza hacia -Z (postura
## regular, pie izquierdo delante). Luego se pasa al espacio del modelo del personaje.

const DECK_Y := 0.085
const FRONT_FOOT_Z := -0.21
const BACK_FOOT_Z := 0.19
## Los tobillos van un poco hacia el talón para que la zapatilla quede centrada en la tabla.
const FOOT_X := -0.05
## El pie que rema pisa justo al lado de la tabla, en la línea de marcha (no de lado).
const PUSH_X := 0.13

## Medidas de la tabla (más ancha que antes, con nose y tail redondeados).
const DECK_HALF_W := 0.125
const DECK_HALF_LEN := 0.41
const DECK_THICK := 0.014
const KICK_START := 0.27
const KICK_ANGLE := 0.33

const COL_GRIP := Color(0.16, 0.15, 0.18)
const COL_DECK := Color(0.85, 0.32, 0.28)
const COL_DECK_EDGE := Color(0.95, 0.78, 0.55)
const COL_METAL := Color(0.72, 0.72, 0.76)
const COL_WHEEL := Color(0.98, 0.9, 0.7)

## Punto de la tabla donde agarra la mano en cada grab (espacio del rider) y con qué mano.
const GRAB_POINTS := {
	"indy": [Vector3(0.11, 0.0, 0.03), "b"],
	"melon": [Vector3(-0.11, 0.0, -0.03), "f"],
	"nosegrab": [Vector3(0.0, 0.03, -0.37), "f"],
	"tailgrab": [Vector3(0.0, 0.03, 0.37), "b"],
	"stalefish": [Vector3(-0.11, 0.0, 0.1), "b"],
}

## Del espacio del rider al del modelo (el personaje mira a +Z).
const TO_MODEL := Basis(Vector3(0, 0, 1), Vector3(0, 1, 0), Vector3(-1, 0, 0))

var lean_root: Node3D
var board_root: Node3D
var board_pivot: Node3D
var rider: Node3D
var rig: CharacterRig
var earphones: Earphones

## Muelle de los brazos: rigidez y amortiguación (menos amortiguación = más rebote).
const ARM_STIFFNESS := 170.0
const ARM_DAMPING := 12.0

var _wheels: Array[Node3D] = []
var _arm_f_pos := Vector3.ZERO
var _arm_f_vel := Vector3.ZERO
var _arm_b_pos := Vector3.ZERO
var _arm_b_vel := Vector3.ZERO
var _arms_ready := false
var _prev_land := 0.0
var _prev_catch := -1.0
var _bail_t := -1.0
var _bail_speed := 0.0
var _fade := 1.0
var _grab_k := 0.0
var _grab_id := "indy"
var _mats := {}

# Medidas del personaje (en reposo)
var _thigh := 0.0
var _shin := 0.0
var _ankle_h := 0.0
var _upper_arm := 0.0
var _forearm := 0.0
var _leg := 0.0


func _ready() -> void:
	lean_root = _node(self)
	board_root = _node(lean_root)
	board_pivot = _node(board_root)
	board_pivot.position.y = 0.075
	_build_board()
	rider = _node(lean_root)
	rig = CharacterRig.new()
	rig.rotation.y = PI * 0.5
	rider.add_child(rig)
	rig.set_outfit(CharacterRig.OUTFIT_ID)
	earphones = Earphones.new()
	earphones.rig = rig
	add_child(earphones)
	_thigh = CharacterRig.length(CharacterRig.THIGH_L)
	_shin = CharacterRig.length(CharacterRig.SHIN_L)
	_ankle_h = CharacterRig.rest(CharacterRig.FOOT_L).y
	_upper_arm = CharacterRig.length(CharacterRig.UPPERARM_L)
	_forearm = CharacterRig.length(CharacterRig.FOREARM_L)
	_leg = _thigh + _shin
	update_pose(0.0, {})


# ---------------------------------------------------------------- API

func set_outfit(id: String) -> void:
	rig.set_outfit(id)


func reset() -> void:
	_bail_t = -1.0
	_grab_k = 0.0
	if not is_node_ready():
		return
	rider.transform = Transform3D.IDENTITY
	board_root.transform = Transform3D.IDENTITY
	lean_root.transform = Transform3D.IDENTITY
	set_trick_rotation(0.0, 0.0)


func start_bail(speed: float) -> void:
	_bail_t = 0.0
	_bail_speed = speed


## flip: giro sobre el eje largo de la tabla. shove: giro sobre el eje vertical.
## Opacidad del skater y la tabla (1 = visible, 0 = invisible), para desvanecerse
## tras una caída y volver a aparecer.
func set_fade(alpha: float) -> void:
	if is_equal_approx(alpha, _fade):
		return
	_fade = alpha
	for n in find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n
		g.transparency = 1.0 - alpha
		g.visible = alpha > 0.01


func set_trick_rotation(flip: float, shove: float) -> void:
	board_pivot.basis = Basis(Vector3.UP, shove) * Basis(Vector3.BACK, flip)


func update_pose(delta: float, p: Dictionary) -> void:
	var crouch: float = p.get("crouch", 0.0)
	var push: float = p.get("push", -1.0)
	var lean: float = p.get("lean", 0.0)
	var air: bool = p.get("air", false)
	var tuck: float = p.get("tuck", 0.0)
	var pitch: float = p.get("pitch", 0.0)
	var lift: float = p.get("lift", 0.0)
	var gap: float = p.get("gap", 0.0)
	var board_x: float = p.get("board_x", 0.0)
	var flip_dir: float = p.get("flip_dir", 0.0)
	var land: float = p.get("land", 0.0)
	var pop: float = p.get("pop", 0.0)
	var speed: float = p.get("speed", 0.0)
	var grab: String = p.get("grab", "")
	var grind: bool = p.get("grind", false)
	var steer: float = p.get("steer", 0.0)
	var spin_vel: float = p.get("spin_vel", 0.0)
	var catch_t: float = p.get("catch_t", -1.0)
	var t: float = p.get("time", 0.0)
	var revert: float = p.get("revert", 0.0)
	var brake: float = p.get("brake", 0.0)

	for w in _wheels:
		w.rotation.x -= speed / 0.027 * delta

	if _bail_t >= 0.0:
		_bail_t += delta
		_pose_bail()
		return

	if grab != "":
		_grab_id = grab
	_grab_k = move_toward(_grab_k, 1.0 if grab != "" else 0.0, delta * 9.0)
	var gk := smoothstep(0.0, 1.0, _grab_k)

	# Rodando las rodillas nunca van del todo estiradas (postura de la referencia)
	var windup := crouch if not air else 0.0
	if not air:
		crouch = maxf(crouch, 0.14)
	if air:
		crouch = maxf(crouch, 0.25 + tuck * 0.55) * (1.0 - pop)
	if grind:
		crouch = maxf(crouch, 0.45)
	var comp := land * land * (3.0 - 2.0 * land)
	crouch = clampf(crouch + comp * 0.95, 0.0, 1.25)
	lift = lerpf(lift, 0.3, gk)
	pitch = lerpf(pitch, 0.08, gk)
	# Derrape (powerslide): la tabla cruzada (eso lo gira el skater) y él agachado,
	# cargando el peso en los talones contra la marcha.
	if brake > 0.0:
		crouch = clampf(crouch + smoothstep(0.0, 1.0, brake) * 0.45, 0.0, 1.25)
	tuck = maxf(tuck, gk)

	# Revert: se agacha y carga el peso atrás (talones) mientras la tabla derrapa
	crouch = clampf(crouch + revert * 0.4, 0.0, 1.25)
	lean_root.rotation = Vector3(0.0, 0.0, lean + revert * 0.2 + brake * 0.25)
	board_root.position = Vector3(board_x, lift, 0.0)
	board_root.rotation = Vector3(pitch, 0.0, 0.0)

	var push_s := sin(push * PI) if push >= 0.0 else 0.0
	# La cadera sube menos que la tabla: las rodillas se recogen hacia el pecho.
	var k := _leg / 0.88
	var hip_y := DECK_Y + _ankle_h + _leg * lerpf(0.96, 0.5, minf(crouch, 1.0)) \
		- maxf(crouch - 1.0, 0.0) * 0.2 - (push_s * 0.17 - lift * 0.5 + gk * 0.06 - pop * 0.07 + comp * 0.06) * k
	var hip := Vector3(-0.03 - crouch * 0.05 + push_s * 0.04, hip_y, -push_s * 0.07)

	# Pies (sobre la tabla, o separados de ella mientras gira en un flip)
	var foot_f := Vector3(FOOT_X, DECK_Y + lift + gap + 0.21 * sin(pitch), FRONT_FOOT_Z)
	var foot_b := Vector3(FOOT_X, DECK_Y + lift + gap * 0.6 - 0.19 * sin(pitch), BACK_FOOT_Z)
	foot_f.x += flip_dir * gap * 0.9
	foot_f.z -= gap * 0.25
	var yaw_f := 0.35
	var yaw_b := -0.1
	if push >= 0.0:
		foot_b = _push_foot(push)
		foot_f.z = FRONT_FOOT_Z - 0.03
		yaw_f = lerpf(0.35, 1.3, push_s)
		yaw_b = lerpf(-0.1, 1.1, push_s)

	# Tronco: inclinado hacia las puntas, mucho más doblado para agarrar la tabla.
	# En los giros los hombros van por delante de la rotación (como al lanzar un 180).
	# Tronco: algo adelantado al rodar; en la preparación de un truco se inclina mucho
	# sobre las rodillas mirando la tabla (como en la referencia de mocap).
	var bend := lerpf(0.2 + minf(crouch, 1.0) * 0.36 + windup * 0.35 - push_s * 0.1 - brake * 0.25, 0.85, gk)
	var twist := clampf(spin_vel * 0.09, -0.6, 0.6) - steer * 0.12
	# Al remar el tronco gira hacia la marcha y se echa hacia delante (hacia el morro)
	var torso := Basis.from_euler(Vector3(-brake * 0.2 - push_s * 0.42, push_s * 0.95 + twist, -bend))
	var look_down := windup * 0.35 + (tuck * 0.3 if air else 0.0)
	var head_rot := Basis.from_euler(Vector3(0.0, 1.05 - push_s * 0.5 - windup * 0.4, bend * 0.5 + gk * 0.3 + look_down - bend * 0.35))
	var shoulders := _pose_trunk(hip, torso, head_rot)

	_pose_leg(CharacterRig.THIGH_L, hip + Vector3(0, 0, -0.1), foot_f, yaw_f, Vector3(1, 0, -0.35))
	_pose_leg(CharacterRig.THIGH_R, hip + Vector3(0, 0, 0.1), foot_b, yaw_b, Vector3(1, 0, 0.35))

	# Brazos en consonancia con el cuerpo (offsets respecto a cada hombro, en ejes del torso:
	# x = hacia las puntas, y = arriba, z = hacia el tail; el brazo delantero va a -z).
	var offs := _arm_targets(crouch, push, push_s, air, tuck, pop, gap, flip_dir, comp, grind, steer, spin_vel, catch_t, t)
	# Preparación: los brazos cuelgan hacia las rodillas (compensa la inclinación del torso)
	offs[0] += Vector3(windup * 0.26, windup * 0.06, windup * 0.02)
	offs[1] += Vector3(windup * 0.24, windup * 0.04, -windup * 0.06)
	# Freno: brazos hacia delante para equilibrar el peso atrás
	offs[0] += Vector3(brake * 0.12, brake * 0.14, -brake * 0.1)
	offs[1] += Vector3(brake * 0.1, brake * 0.1, -brake * 0.06)
	_spring_arms(delta, offs[0], offs[1], land, catch_t)
	var hand_f: Vector3 = shoulders[0] + torso * _arm_f_pos
	var hand_b: Vector3 = shoulders[1] + torso * _arm_b_pos
	if gk > 0.0:
		var gp: Array = GRAB_POINTS[_grab_id]
		var board_pt: Vector3 = gp[0] + Vector3(0.0, DECK_Y + lift + 0.04, 0.0)
		if gp[1] == "f":
			hand_f = hand_f.lerp(board_pt, gk)
			hand_b = hand_b.lerp(shoulders[1] + torso * Vector3(0.04, 0.07, 0.34), gk)
		else:
			hand_b = hand_b.lerp(board_pt, gk)
			hand_f = hand_f.lerp(shoulders[0] + torso * Vector3(0.17, 0.11, -0.3), gk)
	_pose_arm(CharacterRig.UPPERARM_L, shoulders[0], hand_f, torso * Vector3(-0.3, -1.0, -0.3))
	_pose_arm(CharacterRig.UPPERARM_R, shoulders[1], hand_b, torso * Vector3(-0.3, -1.0, 0.3))
	rig.apply()


# ---------------------------------------------------------------- brazos

## Objetivos de las manos según lo que hace el cuerpo. Devuelve [delantera, trasera].
func _arm_targets(crouch: float, push: float, push_s: float, air: bool, tuck: float, pop: float,
		gap: float, flip_dir: float, comp: float, grind: bool, steer: float, spin_vel: float,
		catch_t: float, t: float) -> Array:
	var c := minf(crouch, 1.0)
	# Rodando: brazos muy relajados, casi estirados colgando junto a los muslos (codo
	# apenas doblado), algo adelantados al agacharse, con un leve vaivén
	var sway := sin(t * 1.7) * 0.015
	var f := Vector3(0.05 + c * 0.07, -0.44 + c * 0.07 + sway, -0.08 - c * 0.08)
	var b := Vector3(0.0 + c * 0.05, -0.45 + c * 0.06 - sway, 0.07 + c * 0.06)
	# Carving: las manos acompañan la inclinación hacia dentro de la curva y el
	# brazo de fuera sube para equilibrar
	f += Vector3(steer * 0.1, absf(steer) * 0.06, -absf(steer) * 0.03)
	b += Vector3(steer * 0.1, absf(steer) * 0.1, absf(steer) * 0.04)
	# Empujar: los brazos se balancean al contrario que la pierna que empuja
	if push >= 0.0:
		var swing := sin(push * TAU - 0.6)
		f = f.lerp(Vector3(0.12, -0.38, -0.14), push_s) + Vector3(0.04 * swing, 0.02, -0.1 * swing)
		b = b.lerp(Vector3(-0.04, -0.42, 0.16), push_s) + Vector3(-0.04 * swing, 0.0, 0.12 * swing)
	if air:
		# En el aire: brazos abiertos para el equilibrio
		f = Vector3(0.22, -0.06 + tuck * 0.08, -0.42)
		b = Vector3(0.02, -0.13 + tuck * 0.06, 0.38)
		# Pop: los brazos suben de golpe con el estirón
		f += Vector3(0.04, 0.22, 0.0) * pop
		b += Vector3(0.02, 0.2, 0.0) * pop
		# Flip: más abiertos y altos mientras la tabla gira; el delantero sigue el flick
		f += Vector3(flip_dir * 0.06, gap * 1.3, -gap * 0.7)
		b += Vector3(-flip_dir * 0.03, gap * 1.0, gap * 0.7)
		# Catch: los brazos bajan de golpe al pisar la tabla
		if catch_t >= 0.0:
			var stomp := exp(-catch_t * 9.0) * 0.14
			f.y -= stomp
			b.y -= stomp
	if grind:
		# Grind: brazos abiertos haciendo de balancín
		var w := sin(t * 4.3) * 0.05 + sin(t * 7.1) * 0.02
		f = Vector3(0.12, -0.12 + w, -0.42)
		b = Vector3(0.04, -0.15 - w, 0.42)
	# Al aterrizar caen con la flexión de piernas
	f += Vector3(comp * 0.12, -comp * 0.06, -comp * 0.08)
	b += Vector3(comp * 0.02, -comp * 0.02, comp * 0.1)
	# Giros: los brazos van por delante de la rotación
	var lead := Basis(Vector3.UP, clampf(spin_vel * 0.05, -0.5, 0.5))
	return [lead * f, lead * b]


## Las manos siguen a su objetivo con un muelle: llegan con algo de retraso y un
## pequeño rebote. Los golpes (aterrizaje, catch) les dan un impulso hacia abajo.
func _spring_arms(delta: float, target_f: Vector3, target_b: Vector3, land: float, catch_t: float) -> void:
	if delta <= 0.0 or not _arms_ready:
		_arm_f_pos = target_f
		_arm_b_pos = target_b
		_arm_f_vel = Vector3.ZERO
		_arm_b_vel = Vector3.ZERO
		_arms_ready = delta > 0.0
		_prev_land = land
		_prev_catch = catch_t
		return
	var kick := Vector3.ZERO
	if land > _prev_land + 0.15:
		kick.y -= 1.8 * land
	if catch_t >= 0.0 and _prev_catch < 0.0:
		kick.y -= 1.1
	_prev_land = land
	_prev_catch = catch_t
	_arm_f_vel += kick
	_arm_b_vel += kick * 0.9
	var damp := exp(-ARM_DAMPING * delta)
	_arm_f_vel = (_arm_f_vel + (target_f - _arm_f_pos) * ARM_STIFFNESS * delta) * damp
	_arm_b_vel = (_arm_b_vel + (target_b - _arm_b_pos) * ARM_STIFFNESS * delta) * damp
	_arm_f_pos += _arm_f_vel * delta
	_arm_b_pos += _arm_b_vel * delta


# ---------------------------------------------------------------- partes del cuerpo

## Coloca caderas, columna, cuello y cabeza. Devuelve [hombro delantero, hombro trasero]
## en espacio del rider.
func _pose_trunk(hip: Vector3, torso: Basis, head_rot: Basis) -> Array:
	var hips_pos := hip + Vector3(0.0, _rest(CharacterRig.HIPS).y - _rest(CharacterRig.THIGH_L).y, 0.0)
	var spine_rot := Basis().slerp(torso, 0.5)
	var spine_pos := hips_pos + spine_rot * _offset(CharacterRig.HIPS, CharacterRig.SPINE)
	var chest_pos := spine_pos + torso * _offset(CharacterRig.SPINE, CharacterRig.CHEST)
	var neck_pos := chest_pos + torso * _offset(CharacterRig.CHEST, CharacterRig.NECK)
	var head_pos := neck_pos + torso * _offset(CharacterRig.NECK, CharacterRig.HEAD)
	rig.set_global(CharacterRig.HIPS, _m(hips_pos), Basis())
	rig.set_global(CharacterRig.SPINE, _m(spine_pos), _mb(spine_rot))
	rig.set_global(CharacterRig.CHEST, _m(chest_pos), _mb(torso))
	rig.set_global(CharacterRig.NECK, _m(neck_pos), _mb(torso))
	rig.set_global(CharacterRig.HEAD, _m(head_pos), _mb(torso * head_rot))
	var sh_f := chest_pos + torso * _offset(CharacterRig.CHEST, CharacterRig.UPPERARM_L)
	var sh_b := chest_pos + torso * _offset(CharacterRig.CHEST, CharacterRig.UPPERARM_R)
	return [sh_f, sh_b]


func _rest(bone: int) -> Vector3:
	return CharacterRig.rest(bone)


## Vector de reposo entre dos articulaciones, en espacio del rider.
func _offset(from: int, to: int) -> Vector3:
	return _to_rider(_rest(to) - _rest(from))


## Pierna con IK de 2 huesos: cadera -> rodilla -> tobillo, y el pie apuntando
## hacia las puntas con el giro `yaw`.
func _pose_leg(thigh: int, hip: Vector3, foot: Vector3, yaw: float, hint: Vector3) -> void:
	var ankle := foot + Vector3(0.0, _ankle_h, 0.0)
	var knee := _ik(hip, ankle, _thigh, _shin, hint)
	var bend := knee - (hip + ankle) * 0.5
	if bend.length() < 0.01:
		bend = hint
	var fwd := Vector3(0, 0, 1) # rodilla hacia delante en reposo (espacio modelo)
	rig.aim(thigh, _m(hip), _m(knee), _m(bend), fwd)
	rig.aim(thigh + 1, _m(knee), _m(ankle), _m(bend), fwd)
	var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
	var toe := ankle + dir * 0.18 + Vector3(0.0, -0.08, 0.0)
	rig.aim(thigh + 2, _m(ankle), _m(toe), Vector3.UP, Vector3.UP)


## Brazo con IK: hombro -> codo -> muñeca, y la mano siguiendo al antebrazo.
func _pose_arm(upper: int, shoulder: Vector3, hand: Vector3, hint: Vector3) -> void:
	var elbow := _ik(shoulder, hand, _upper_arm, _forearm, hint)
	var dir := (hand - elbow).normalized()
	var wrist := elbow + dir * _forearm
	var bend := elbow - (shoulder + wrist) * 0.5
	if bend.length() < 0.01:
		bend = hint
	var back := Vector3(0, 0, -1) # codo hacia atrás en reposo (espacio modelo)
	rig.aim(upper, _m(shoulder), _m(elbow), _m(bend), back)
	rig.aim(upper + 1, _m(elbow), _m(wrist), _m(bend), back)
	rig.aim(upper + 2, _m(wrist), _m(wrist + dir * 0.12), _m(bend), back)


func _m(p: Vector3) -> Vector3:
	return TO_MODEL * p


func _mb(b: Basis) -> Basis:
	return TO_MODEL * b * TO_MODEL.inverse()


func _to_rider(v: Vector3) -> Vector3:
	return TO_MODEL.inverse() * v


# ---------------------------------------------------------------- poses

## Pie que rema (exagerado, como pidió el usuario a partir de la referencia):
## 0-0.3 sale de la tabla y se lanza muy adelante, junto al pie delantero;
## 0.3-0.68 apoya y empuja en un trazo largo hasta muy atrás;
## 0.68-1 se recoge con la rodilla alta y vuelve a la tabla.
func _push_foot(phase: float) -> Vector3:
	if phase < 0.3:
		var k := smoothstep(0.0, 1.0, phase / 0.3)
		return Vector3(lerpf(FOOT_X, PUSH_X, k), lerpf(DECK_Y, 0.0, k) + sin(k * PI) * 0.1, lerpf(BACK_FOOT_Z, -0.5, k))
	if phase < 0.68:
		var k := (phase - 0.3) / 0.38
		return Vector3(PUSH_X, 0.0, lerpf(-0.5, 0.72, k))
	var k := smoothstep(0.0, 1.0, (phase - 0.68) / 0.32)
	return Vector3(lerpf(PUSH_X, FOOT_X, k), lerpf(0.0, DECK_Y, k) + sin(k * PI) * 0.18, lerpf(0.72, BACK_FOOT_Z, k))


func _pose_bail() -> void:
	var k := clampf(_bail_t / 0.5, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - k, 3.0)
	lean_root.rotation = Vector3.ZERO
	# El cuerpo cae de lado hacia las puntas
	rider.rotation = Vector3(0.0, 0.0, -1.45 * e)
	rider.position = Vector3(0.25 * e, 0.12 * sin(k * PI), 0.0)
	# La tabla sigue rodando sola y vuelca
	var roll := (1.0 - exp(-_bail_t * 1.5)) * minf(_bail_speed * 0.5 + 1.0, 4.0)
	board_root.position = Vector3(-0.3 * e, 0.15 * e, -roll)
	board_root.rotation = Vector3(0.0, 0.6 * e, PI * e)

	var hip := Vector3(-0.05, 0.68, 0.0)
	var torso := Basis.from_euler(Vector3(0.0, 0.0, 0.3 * e))
	var shoulders := _pose_trunk(hip, torso, Basis.from_euler(Vector3(0.0, 0.6, 0.0)))
	_pose_leg(CharacterRig.THIGH_L, hip + Vector3(0, 0, -0.1), Vector3(0.25, 0.1, -0.3), 0.3, Vector3(1, 0, 0))
	_pose_leg(CharacterRig.THIGH_R, hip + Vector3(0, 0, 0.1), Vector3(0.1, 0.05, 0.3), 0.0, Vector3(1, 0, 0))
	# Brazos agitándose al perder el equilibrio y apoyándose al llegar al suelo
	var flail := (1.0 - k) * 0.18
	var bt := _bail_t * 11.0
	_pose_arm(CharacterRig.UPPERARM_L, shoulders[0], shoulders[0] + Vector3(0.1 + sin(bt) * flail, 0.15 + cos(bt * 1.3) * flail, -0.35), Vector3(0, -1, 0))
	_pose_arm(CharacterRig.UPPERARM_R, shoulders[1], shoulders[1] + Vector3(0.1 + cos(bt * 0.9) * flail, 0.2 + sin(bt * 1.1) * flail, 0.35), Vector3(0, -1, 0))
	_arms_ready = false
	rig.apply()


## IK analítica de 2 huesos. Devuelve la posición de la articulación intermedia.
func _ik(a: Vector3, target: Vector3, l1: float, l2: float, hint: Vector3) -> Vector3:
	var to := target - a
	var d := clampf(to.length(), 0.01, (l1 + l2) * 0.999)
	var dir := to.normalized()
	var x := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - x * x, 0.0))
	var bend := hint - dir * hint.dot(dir)
	if bend.length() < 0.001:
		bend = Vector3.UP.cross(dir)
	return a + dir * x + bend.normalized() * h


# ---------------------------------------------------------------- tabla

func _build_board() -> void:
	_build_deck()
	for z in [-0.21, 0.21]:
		_box(board_pivot, Vector3(0.07, 0.022, 0.08), Vector3(0, -0.018, z), COL_METAL)
		_box(board_pivot, Vector3(0.2, 0.022, 0.03), Vector3(0, -0.04, z), COL_METAL)
		for x in [-0.095, 0.095]:
			var axle := _node(board_pivot)
			axle.position = Vector3(x, -0.048, z)
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.028
			cyl.bottom_radius = 0.028
			cyl.height = 0.034
			cyl.radial_segments = 6
			cyl.rings = 1
			var w := _mesh(axle, cyl, COL_WHEEL)
			w.rotation.z = PI * 0.5
			_wheels.append(axle)


## Tabla: contorno con nose y tail redondeados, kicktails levantados, lija arriba,
## gráfico abajo y canto de madera.
func _build_deck() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 36
	var zs: Array[float] = []
	var ws: Array[float] = []
	var ys: Array[float] = []
	for i in steps + 1:
		var z := lerpf(-DECK_HALF_LEN, DECK_HALF_LEN, float(i) / steps)
		zs.append(z)
		ws.append(_deck_half_width(z))
		ys.append(_deck_height(z))
	var top := DECK_THICK * 0.5
	for i in steps:
		var z0 := zs[i]
		var z1 := zs[i + 1]
		var w0 := ws[i]
		var w1 := ws[i + 1]
		var y0 := ys[i]
		var y1 := ys[i + 1]
		# Lija (arriba), gráfico (abajo)
		_deck_quad(st, Vector3(-w0, y0 + top, z0), Vector3(w0, y0 + top, z0), Vector3(w1, y1 + top, z1), Vector3(-w1, y1 + top, z1), Vector3.UP, COL_GRIP)
		_deck_quad(st, Vector3(-w0, y0 - top, z0), Vector3(w0, y0 - top, z0), Vector3(w1, y1 - top, z1), Vector3(-w1, y1 - top, z1), Vector3.DOWN, COL_DECK)
		# Cantos
		for s in [-1.0, 1.0]:
			var n := Vector3(s, 0.0, -(w1 - w0) * s / maxf(z1 - z0, 0.0001)).normalized()
			_deck_quad(st, Vector3(w0 * s, y0 - top, z0), Vector3(w1 * s, y1 - top, z1), Vector3(w1 * s, y1 + top, z1), Vector3(w0 * s, y0 + top, z0), n, COL_DECK_EDGE)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	board_pivot.add_child(mi)


func _deck_half_width(z: float) -> float:
	var a := absf(z)
	var flat := DECK_HALF_LEN - DECK_HALF_W
	if a <= flat:
		return DECK_HALF_W
	var k := clampf((a - flat) / DECK_HALF_W, 0.0, 1.0)
	return maxf(DECK_HALF_W * sqrt(1.0 - k * k), 0.012)


func _deck_height(z: float) -> float:
	var a := absf(z)
	return 0.0 if a <= KICK_START else (a - KICK_START) * tan(KICK_ANGLE)


func _deck_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	for p in [a, b, c, a, c, d]:
		st.set_color(col)
		st.set_normal(n)
		st.add_vertex(p)


func _node(parent: Node3D) -> Node3D:
	var n := Node3D.new()
	parent.add_child(n)
	return n


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var m := _mesh(parent, bm, color)
	m.position = pos
	return m


func _mesh(parent: Node3D, mesh: Mesh, color: Color) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = _mat(color)
	parent.add_child(m)
	return m


func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = 1.0
		mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		_mats[key] = mat
	return _mats[key]

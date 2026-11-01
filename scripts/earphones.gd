class_name Earphones
extends Node3D
## Auriculares de cable con física: dos cables desde las orejas que se juntan a la
## altura del pecho y bajan hasta el bolsillo. Se simulan como cuerdas (Verlet) con
## gravedad e inercia, chocando con el cuerpo y la cabeza, así se balancean al remar,
## saltar y girar. Se dibujan como cintas finas orientadas a la cámara.

const SEG := 0.05
const WIDTH := 0.012
const GRAVITY := Vector3(0.0, -9.8, 0.0)
const DAMPING := 0.985
const ITERATIONS := 8
## Puntos de anclaje relativos a la articulación de su hueso (espacio del modelo).
const EAR_L := Vector3(0.152, 0.12, 0.01)
const EAR_R := Vector3(-0.152, 0.12, 0.01)
const POCKET := Vector3(-0.15, -0.03, 0.12)
const BODY_RADIUS := 0.2
const HEAD_RADIUS := 0.155

var rig: CharacterRig

var _p: PackedVector3Array = []
var _prev: PackedVector3Array = []
var _links: Array[Vector3i] = [] # (a, b, longitud en mm)
var _chains: Array[PackedInt32Array] = []
var _pin_l := 0
var _pin_r := 0
var _pin_pocket := 0
var _yoke := 0
var _mesh := ImmediateMesh.new()
var _cable: MeshInstance3D
var _bud_l: MeshInstance3D
var _bud_r: MeshInstance3D
var _ready_sim := false


func _ready() -> void:
	top_level = true
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.96, 0.96)
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cable = MeshInstance3D.new()
	_cable.mesh = _mesh
	_cable.material_override = mat
	_cable.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_cable)
	var bud := SphereMesh.new()
	bud.radius = 0.026
	bud.height = 0.04
	bud.radial_segments = 8
	bud.rings = 4
	_bud_l = MeshInstance3D.new()
	_bud_l.mesh = bud
	_bud_l.material_override = mat
	add_child(_bud_l)
	_bud_r = MeshInstance3D.new()
	_bud_r.mesh = bud
	_bud_r.material_override = mat
	add_child(_bud_r)
	_build_topology()


## Cuerdas: oreja izq -> Y, oreja der -> Y, Y -> bolsillo.
func _build_topology() -> void:
	var n_ear := 9
	var n_down := 12
	_p.resize(0)
	_pin_l = _add_point()
	var chain_l := PackedInt32Array([_pin_l])
	for i in n_ear - 1:
		chain_l.append(_add_point())
	_yoke = _add_point()
	chain_l.append(_yoke)
	_pin_r = _add_point()
	var chain_r := PackedInt32Array([_pin_r])
	for i in n_ear - 1:
		chain_r.append(_add_point())
	chain_r.append(_yoke)
	var chain_d := PackedInt32Array([_yoke])
	for i in n_down - 1:
		chain_d.append(_add_point())
	_pin_pocket = _add_point()
	chain_d.append(_pin_pocket)
	_chains = [chain_l, chain_r, chain_d]
	for ch in _chains:
		for i in ch.size() - 1:
			_links.append(Vector3i(ch[i], ch[i + 1], int(SEG * 1000.0)))
	_prev = _p.duplicate()


func _add_point() -> int:
	_p.append(Vector3.ZERO)
	return _p.size() - 1


func _anchor(bone: int, offset: Vector3) -> Vector3:
	var sk := rig.skeleton
	return sk.global_transform * (sk.get_bone_global_pose(bone) * offset)


## Llamar cada paso de física después de posar el esqueleto.
func step(delta: float) -> void:
	if rig == null or rig.skeleton == null:
		return
	var ear_l := _anchor(CharacterRig.HEAD, EAR_L)
	var ear_r := _anchor(CharacterRig.HEAD, EAR_R)
	var pocket := _anchor(CharacterRig.HIPS, POCKET)
	# Primera vez o teletransporte (reaparecer): colocar los cables en reposo
	if not _ready_sim or _p[_pin_l].distance_to(ear_l) > 1.0:
		var fwd := (rig.skeleton.global_transform.basis * rig.skeleton.get_bone_global_pose(CharacterRig.CHEST).basis * Vector3(0, 0, 1)).normalized()
		_reset(ear_l, ear_r, pocket, fwd)
	var dt2 := delta * delta
	for i in _p.size():
		var cur := _p[i]
		_p[i] = cur + (cur - _prev[i]) * DAMPING + GRAVITY * dt2
		_prev[i] = cur
	var hips := _anchor(CharacterRig.HIPS, Vector3.ZERO)
	var neck := _anchor(CharacterRig.NECK, Vector3.ZERO)
	var head := _anchor(CharacterRig.HEAD, Vector3(0.0, 0.17, 0.0))
	for it in ITERATIONS:
		_p[_pin_l] = ear_l
		_p[_pin_r] = ear_r
		_p[_pin_pocket] = pocket
		for l in _links:
			var a := _p[l.x]
			var b := _p[l.y]
			var d := b - a
			var dist := d.length()
			if dist < 0.00001:
				continue
			var corr := d * (0.5 * (dist - l.z / 1000.0) / dist)
			_p[l.x] = a + corr
			_p[l.y] = b - corr
		for i in _p.size():
			_p[i] = _push_out(_p[i], hips, neck, head)
	_p[_pin_l] = ear_l
	_p[_pin_r] = ear_r
	_p[_pin_pocket] = pocket
	_bud_l.global_position = ear_l
	_bud_r.global_position = ear_r
	_draw()


func _reset(ear_l: Vector3, ear_r: Vector3, pocket: Vector3, fwd: Vector3) -> void:
	# El cable cae por delante del pecho
	var chest := (ear_l + ear_r) * 0.5 + (pocket - (ear_l + ear_r) * 0.5) * 0.45 + fwd * 0.26
	for ch in _chains:
		var a: Vector3 = ear_l if ch[0] == _pin_l else (ear_r if ch[0] == _pin_r else chest)
		var b: Vector3 = chest if ch[ch.size() - 1] == _yoke else pocket
		for i in ch.size():
			_p[ch[i]] = a.lerp(b, float(i) / (ch.size() - 1))
	_prev = _p.duplicate()
	_ready_sim = true


## Los cables no atraviesan el tronco (cápsula caderas-cuello) ni la cabeza.
func _push_out(q: Vector3, a: Vector3, b: Vector3, head: Vector3) -> Vector3:
	var ab := b - a
	var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	var c := a + ab * t
	var d := q - c
	if d.length() < BODY_RADIUS:
		q = c + d.normalized() * BODY_RADIUS
	var dh := q - head
	if dh.length() < HEAD_RADIUS:
		q = head + dh.normalized() * HEAD_RADIUS
	return q


func _draw() -> void:
	_mesh.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var eye := cam.global_position
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for ch in _chains:
		for i in ch.size() - 1:
			var a := _p[ch[i]]
			var b := _p[ch[i + 1]]
			var dir := b - a
			var side := dir.cross(eye - a).normalized() * WIDTH * 0.5
			var n := (eye - a).normalized()
			for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
				_mesh.surface_set_normal(n)
				_mesh.surface_add_vertex(v)
	_mesh.surface_end()

class_name CharacterRig
extends Node3D
## Personaje low-poly del kit "Creative Character" con un esqueleto hecho por código.
## Los modelos vienen sin rig: tools/build_character.gd calcula los pesos de cada
## vértice según su distancia a los huesos de BONES y guarda la malla ya preparada
## (assets/character/skater_<id>.res). Aquí se monta el Skeleton3D y se posa a
## partir de posiciones de articulaciones calculadas con IK (SkaterModel).
##
## Espacio del modelo: mira a +Z, Y arriba, la izquierda del personaje es +X.

const MESH_PATH := "res://assets/character/skater_%s.res"
const TEXTURE := preload("res://assets/character/Textures_4.png")

## Personaje (lo genera tools/build_character.gd): camiseta oversize blanca, pantalón
## ancho negro y zapatillas. Cada pieza: [nombre OBJ, recolor ("", "white", "black"),
## cuánto se hincha hacia fuera (m), cuánto baja el dobladillo (m)].
const OUTFIT_ID := "skater"
const OUTFIT_PARTS := [
	["Body_010", "", 0.0, 0.0],
	["Male_emotion_happy_002", "", 0.0, 0.0],
	["Hairstyle_male_010", "", 0.0, 0.0],
	["T_Shirt_009", "white", 0.03, 0.07],
	["Pants_010", "black", 0.035, 0.0],
	["Shoe_Sneakers_009", "", 0.0, 0.0],
]

## [nombre, padre, articulación, punta, radio]. La punta define el segmento del hueso
## (para los pesos y para saber hacia dónde apunta en reposo).
const BONES := [
	["hips", -1, Vector3(0.0, 0.80, -0.02), Vector3(0.0, 0.95, -0.02), 0.17],
	["spine", 0, Vector3(0.0, 0.95, -0.02), Vector3(0.0, 1.12, -0.02), 0.17],
	["chest", 1, Vector3(0.0, 1.12, -0.02), Vector3(0.0, 1.38, -0.02), 0.2],
	["neck", 2, Vector3(0.0, 1.38, -0.02), Vector3(0.0, 1.47, -0.01), 0.08],
	["head", 3, Vector3(0.0, 1.47, -0.01), Vector3(0.0, 1.83, 0.0), 0.2],
	["thigh_l", 0, Vector3(0.10, 0.78, -0.01), Vector3(0.10, 0.47, 0.0), 0.09],
	["shin_l", 5, Vector3(0.10, 0.47, 0.0), Vector3(0.10, 0.11, -0.02), 0.08],
	["foot_l", 6, Vector3(0.10, 0.11, -0.02), Vector3(0.10, 0.03, 0.16), 0.08],
	["thigh_r", 0, Vector3(-0.10, 0.78, -0.01), Vector3(-0.10, 0.47, 0.0), 0.09],
	["shin_r", 8, Vector3(-0.10, 0.47, 0.0), Vector3(-0.10, 0.11, -0.02), 0.08],
	["foot_r", 9, Vector3(-0.10, 0.11, -0.02), Vector3(-0.10, 0.03, 0.16), 0.08],
	["upperarm_l", 2, Vector3(0.17, 1.33, -0.02), Vector3(0.38, 1.20, -0.02), 0.06],
	["forearm_l", 11, Vector3(0.38, 1.20, -0.02), Vector3(0.58, 1.06, -0.02), 0.055],
	["hand_l", 12, Vector3(0.58, 1.06, -0.02), Vector3(0.72, 0.95, -0.02), 0.05],
	["upperarm_r", 2, Vector3(-0.17, 1.33, -0.02), Vector3(-0.38, 1.20, -0.02), 0.06],
	["forearm_r", 14, Vector3(-0.38, 1.20, -0.02), Vector3(-0.58, 1.06, -0.02), 0.055],
	["hand_r", 15, Vector3(-0.58, 1.06, -0.02), Vector3(-0.72, 0.95, -0.02), 0.05],
]
enum { HIPS, SPINE, CHEST, NECK, HEAD, THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R,
	UPPERARM_L, FOREARM_L, HAND_L, UPPERARM_R, FOREARM_R, HAND_R }

var skeleton: Skeleton3D
var _globals: Array[Transform3D] = []


func _ready() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	for i in BONES.size():
		var b: Array = BONES[i]
		skeleton.add_bone(b[0])
		var parent: int = b[1]
		skeleton.set_bone_parent(i, parent)
		var origin: Vector3 = b[2]
		if parent >= 0:
			origin -= BONES[parent][2]
		skeleton.set_bone_rest(i, Transform3D(Basis(), origin))
	skeleton.reset_bone_poses()
	_globals.resize(BONES.size())
	for i in BONES.size():
		_globals[i] = Transform3D(Basis(), BONES[i][2])


## Carga el personaje elegido (cambia la malla sin rehacer el esqueleto).
func set_outfit(id: String) -> void:
	for c in skeleton.get_children():
		c.queue_free()
	var mesh: Mesh = load(MESH_PATH % id)
	if mesh == null:
		push_error("Falta %s: ejecuta tools/build_character.gd" % (MESH_PATH % id))
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = TEXTURE
	mat.roughness = 0.9
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mi.material_override = mat
	skeleton.add_child(mi)
	mi.skin = skeleton.create_skin_from_rest_transforms()
	mi.skeleton = mi.get_path_to(skeleton)


static func rest(bone: int) -> Vector3:
	return BONES[bone][2]


static func tip(bone: int) -> Vector3:
	return BONES[bone][3]


static func length(bone: int) -> float:
	return rest(bone).distance_to(tip(bone))


# ---------------------------------------------------------------- posado

## Fija la transformación global (en espacio del esqueleto) de un hueso de tronco:
## la articulación va a `origin` y el hueso gira con `basis`.
func set_global(bone: int, origin: Vector3, basis: Basis) -> void:
	_globals[bone] = Transform3D(basis, origin)


## Orienta un hueso de extremidad para que vaya de `a` a `b`. `bend` indica hacia
## dónde se dobla la articulación (rodilla hacia delante, codo hacia atrás) y
## `rest_bend` es esa misma dirección en la pose de reposo.
func aim(bone: int, a: Vector3, b: Vector3, bend: Vector3, rest_bend: Vector3) -> void:
	var rd := (tip(bone) - rest(bone)).normalized()
	var dd := b - a
	if dd.length() < 0.0001:
		return
	dd = dd.normalized()
	var basis := _frame(dd, bend) * _frame(rd, rest_bend).inverse()
	_globals[bone] = Transform3D(basis, a)


## Aplica las transformaciones globales al esqueleto (convierte a poses locales).
func apply() -> void:
	for i in BONES.size():
		var parent: int = BONES[i][1]
		var local := _globals[i] if parent < 0 else _globals[parent].affine_inverse() * _globals[i]
		skeleton.set_bone_pose_position(i, local.origin)
		skeleton.set_bone_pose_rotation(i, local.basis.get_rotation_quaternion())


func global_of(bone: int) -> Transform3D:
	return _globals[bone]


static func _frame(dir: Vector3, ref: Vector3) -> Basis:
	var y := dir.normalized()
	var x := ref - y * ref.dot(y)
	if x.length() < 0.0001:
		x = y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


# ---------------------------------------------------------------- pesos (herramienta)

## Pesos de piel para un vértice en reposo: hasta 4 huesos más cercanos según la
## distancia a su segmento dividida por su grosor, con reglas para que no se
## mezclen zonas que no se tocan (brazos con caderas, piernas entre sí...).
static func weights_for(p: Vector3) -> Array:
	var scores: Array = []
	for i in BONES.size():
		if not _allowed(i, p):
			continue
		var a: Vector3 = BONES[i][2]
		var b: Vector3 = BONES[i][3]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t) / float(BONES[i][4])
		scores.append([d, i])
	scores.sort_custom(func(x, y): return x[0] < y[0])
	var best: float = scores[0][0]
	var bones := PackedInt32Array()
	var ws := PackedFloat32Array()
	var total := 0.0
	for k in mini(4, scores.size()):
		var d: float = scores[k][0]
		var w := 0.0 if d > best + 0.6 else 1.0 / pow(d + 0.15, 4.0)
		bones.append(scores[k][1])
		ws.append(w)
		total += w
	while bones.size() < 4:
		bones.append(0)
		ws.append(0.0)
	for k in 4:
		ws[k] = ws[k] / total if total > 0.0 else (1.0 if k == 0 else 0.0)
	return [bones, ws]


static func _allowed(bone: int, p: Vector3) -> bool:
	match bone:
		THIGH_L, SHIN_L, FOOT_L:
			return p.x > -0.02 and p.y < 0.84
		THIGH_R, SHIN_R, FOOT_R:
			return p.x < 0.02 and p.y < 0.84
		UPPERARM_L, FOREARM_L, HAND_L:
			return p.x > 0.13 and p.y > 0.85
		UPPERARM_R, FOREARM_R, HAND_R:
			return p.x < -0.13 and p.y > 0.85
		NECK, HEAD:
			return p.y > 1.3
		HIPS, SPINE, CHEST:
			return p.y > 0.68 and absf(p.x) < 0.3
	return true

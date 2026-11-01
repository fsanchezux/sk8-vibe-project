class_name SkidMarks
extends MultiMeshInstance3D
## Marcas de goma que dejan las ruedas al derrapar (reverts). Cada tramo es un
## rectángulo plano sobre el suelo; se desvanecen poco a poco y se reutilizan.

const MAX_MARKS := 900
const LIFE := 12.0
const COLOR := Color(0.22, 0.16, 0.18)

var _born := PackedFloat32Array()
var _alpha := PackedFloat32Array()
var _next := 0
var _time := 0.0
var _fade_t := 0.0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.0, 1.0)
	mm.mesh = plane
	mm.instance_count = MAX_MARKS
	multimesh = mm
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 1.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_born.resize(MAX_MARKS)
	_alpha.resize(MAX_MARKS)
	var hidden := Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0, -100, 0))
	for i in MAX_MARKS:
		mm.set_instance_transform(i, hidden)
		mm.set_instance_color(i, Color(COLOR, 0.0))


## Añade un tramo de marca de a a b sobre una superficie con normal n.
func add_mark(a: Vector3, b: Vector3, n: Vector3, width: float, strength: float) -> void:
	var dir := b - a
	if dir.length() < 0.005:
		return
	var side := n.cross(dir).normalized() * width
	var t := Transform3D(Basis(side, n, dir), (a + b) * 0.5 + n * 0.012)
	var i := _next
	_next = (_next + 1) % MAX_MARKS
	multimesh.set_instance_transform(i, t)
	_born[i] = _time
	_alpha[i] = clampf(strength, 0.0, 1.0) * 0.55
	multimesh.set_instance_color(i, Color(COLOR, _alpha[i]))


func _process(delta: float) -> void:
	_time += delta
	_fade_t += delta
	if _fade_t < 0.3:
		return
	_fade_t = 0.0
	for i in MAX_MARKS:
		if _alpha[i] <= 0.0:
			continue
		var k := 1.0 - (_time - _born[i]) / LIFE
		if k <= 0.0:
			_alpha[i] = 0.0
			multimesh.set_instance_color(i, Color(COLOR, 0.0))
		else:
			multimesh.set_instance_color(i, Color(COLOR, _alpha[i] * minf(k * 2.0, 1.0)))

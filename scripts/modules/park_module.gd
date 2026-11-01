@tool
class_name ParkModule
extends Node3D
## Base de los módulos del mapa: piezas sueltas que se arrastran al nodo "Modules" de
## scenes/main.tscn y se mueven / rotan en el editor de Godot (@tool: se ven en el editor).
##
## Cada módulo dibuja su propia malla (_build) y, al arrancar el juego, el skatepark le
## pide su física con register(): añade al park sus formas (suelo) y sus rails (grinds),
## así lo que se ve es lo que se pisa.
##
## Reglas al colocarlos:
##  - Mueve en X/Z y rota solo en Y; la escala en 1 (las medidas son parámetros del
##    Inspector, no la escala). Y es la altura de la base: 0 en el fondo del park, o la
##    altura del deck o rellano sobre el que se apoya la pieza.
##  - El eje X local es la dirección de la pieza (u); el eje Z, el ancho.

const PAINTED := preload("res://shaders/painted.gdshader")

static var _painted: ShaderMaterial

var _st: SurfaceTool
var _rebuild_queued := false


func _ready() -> void:
	_rebuild()


## Pide reconstruir la malla (los parámetros del Inspector lo llaman al cambiar).
func queue_rebuild() -> void:
	if not is_node_ready() or _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	var old := get_node_or_null("Mesh")
	if old:
		remove_child(old)
		old.queue_free()
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_build()
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = _st.commit()
	mi.material_override = _material()
	add_child(mi)


## Dibuja la malla con _quad / _quad_out. Cada módulo lo implementa.
func _build() -> void:
	pass


## Añade al park la física del módulo (park.shapes y park.rails). Cada módulo lo implementa.
func register(_park: Object) -> void:
	pass


# ---------------------------------------------------------------- ayudas de física

## Origen (X, Z) y dirección (eje X local) del módulo en el mundo.
func _origin() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func _dir() -> Vector2:
	var x := global_transform.basis.x
	return Vector2(x.x, x.z).normalized()


## Punto del módulo en el mundo: u a lo largo, v a lo ancho, y de altura.
func _world(u: float, v: float, y: float) -> Vector3:
	return global_transform * Vector3(u, y, v)


# ---------------------------------------------------------------- ayudas de malla

## Mismo material que el resto del park: color por vértice con textura de pintura.
static func _material() -> ShaderMaterial:
	if _painted == null:
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.02
		noise.fractal_octaves = 4
		var tex := NoiseTexture2D.new()
		tex.width = 256
		tex.height = 256
		tex.seamless = true
		tex.noise = noise
		tex.generate_mipmaps = true
		_painted = ShaderMaterial.new()
		_painted.shader = PAINTED
		_painted.set_shader_parameter("brush", tex)
	return _painted


static func _hash2(x: float, y: float) -> float:
	return fposmod(sin(x * 12.9898 + y * 78.233) * 43758.5453, 1.0)


## Triángulo de caras planas; corrige el orden para que la cara mire hacia n.
func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	var cen := (a + b + c) / 3.0
	var cc := col * (0.97 + _hash2(cen.x + cen.y * 3.1, cen.z - cen.y * 1.7) * 0.06)
	cc.a = 1.0
	for p in [a, b, c]:
		_st.set_color(cc)
		_st.set_normal(n)
		_st.add_vertex(p)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(a, b, c, n, col)
	_tri(a, c, d, n, col)


## Cuadrilátero cuya normal sale del lado contrario a `inside` (un punto del lado interior).
func _quad_out(a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3, col: Color) -> void:
	var n := (b - a).cross(d - a).normalized()
	if n.dot((a + b + c + d) * 0.25 - inside) < 0.0:
		n = -n
	_quad(a, b, c, d, n, col)

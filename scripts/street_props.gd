class_name StreetProps
extends Node3D
## Grafitis y mobiliario urbano del skatepark (moodboard: objetos con textura pintada
## y pintadas). Las etiquetas de grafiti se dibujan una vez en un SubViewport con las
## tipografías del proyecto y se proyectan con Decals sobre rampas, ledges, murete y
## suelo. Añade conos, contenedores, cubos de basura y señales con grafitis.

const TAG_WORDS := ["SK8", "VIBE", "DUSK", "CHILL", "ROLL", "LOFI", "FSA", "OLLIE"]
const TAG_COLORS := [Color(1.0, 0.45, 0.75), Color(0.35, 0.9, 1.0), Color(0.65, 1.0, 0.4),
	Color(1.0, 0.62, 0.25), Color(0.72, 0.5, 1.0), Color(1.0, 0.95, 0.85)]
const OUTLINES := [Color(0.12, 0.08, 0.22), Color(0.05, 0.05, 0.08), Color(0.95, 0.95, 1.0)]
const CELL := Vector2i(512, 256)
const COLS := 2
## Capa de render de los objetos que reciben grafitis (el skater queda fuera).
const DECAL_LAYER := 2

const FONT_TAG := preload("res://assets/fonts/ArchivoBlack-Regular.ttf")
const FONT_ROUND := preload("res://assets/fonts/Nunito-Black.ttf")

const C_DUMPSTER := Color(0.2, 0.36, 0.72)
const C_LID := Color(0.16, 0.3, 0.24)
const C_BIN := Color(0.24, 0.46, 0.34)
const C_CONE := Color(1.0, 0.45, 0.15)
const C_WHITE := Color(0.95, 0.93, 0.9)
const C_POLE := Color(0.55, 0.55, 0.6)
const C_SIGN := Color(0.85, 0.2, 0.22)
const C_DARK := Color(0.12, 0.12, 0.14)

var park: Skatepark
var _tags: Array[Texture2D] = []
var _st: SurfaceTool
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 8
	_build_props()
	await _render_tags()
	_place_decals()


# ---------------------------------------------------------------- grafitis

## Dibuja las etiquetas en un SubViewport transparente y las recorta en texturas.
func _render_tags() -> void:
	var rows := int(ceil(TAG_WORDS.size() / float(COLS)))
	var vp := SubViewport.new()
	vp.size = Vector2i(CELL.x * COLS, CELL.y * rows)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	for i in TAG_WORDS.size():
		var cell := Control.new()
		cell.position = Vector2((i % COLS) * CELL.x, (i / COLS) * CELL.y)
		cell.size = Vector2(CELL)
		vp.add_child(cell)
		_draw_tag(cell, TAG_WORDS[i], i)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	if img == null or img.is_empty():
		vp.queue_free()
		return
	img.convert(Image.FORMAT_RGBA8)
	for i in TAG_WORDS.size():
		var region := img.get_region(Rect2i(Vector2i((i % COLS) * CELL.x, (i / COLS) * CELL.y), CELL))
		region.generate_mipmaps()
		_tags.append(ImageTexture.create_from_image(region))
	vp.queue_free()


func _draw_tag(cell: Control, word: String, i: int) -> void:
	var col: Color = TAG_COLORS[i % TAG_COLORS.size()]
	var outline: Color = OUTLINES[i % OUTLINES.size()]
	if outline.get_luminance() > 0.8 and col.get_luminance() > 0.8:
		outline = OUTLINES[0]
	# Chorretones de pintura bajo las letras
	for d in 6:
		var drip := ColorRect.new()
		drip.color = col
		drip.position = Vector2(_rng.randf_range(90, 420), _rng.randf_range(150, 175))
		drip.size = Vector2(_rng.randf_range(4, 8), _rng.randf_range(20, 70))
		cell.add_child(drip)
	var l := Label.new()
	l.text = word
	l.add_theme_font_override("font", FONT_TAG if i % 2 == 0 else FONT_ROUND)
	l.add_theme_font_size_override("font_size", 128 if word.length() <= 4 else 104)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", outline)
	l.add_theme_constant_override("outline_size", 22)
	l.add_theme_color_override("font_shadow_color", Color(outline, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 8)
	l.add_theme_constant_override("shadow_offset_y", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(CELL)
	l.pivot_offset = Vector2(CELL) * 0.5
	l.rotation = _rng.randf_range(-0.16, 0.16)
	cell.add_child(l)
	# Salpicaduras de spray
	for s in 14:
		var dot := ColorRect.new()
		dot.color = Color(col, _rng.randf_range(0.5, 0.9))
		var r := _rng.randf_range(2, 6)
		dot.size = Vector2(r, r)
		dot.position = Vector2(_rng.randf_range(40, 470), _rng.randf_range(30, 230))
		cell.add_child(dot)


func _place_decals() -> void:
	if _tags.is_empty():
		return
	var up := Vector3.UP
	# Normales de las rampas que bajan hacia el este (pendiente = altura / largo)
	var gap_land_n := Vector3(2.0 / 8.0, 1.0, 0.0).normalized()
	var drop_bank_n := Vector3(Skatepark.DECK_H / 7.0, 1.0, 0.0).normalized()
	var box_land_n := Vector3(1.2 / 5.0, 1.0, 0.0).normalized()
	var qp_n := Vector3(-0.59, 1.0, 0.0).normalized()
	var z1: float = Skatepark.LANE_Z[0]
	var z3: float = Skatepark.LANE_Z[2]
	var dh := Skatepark.DECK_H
	var spots := [
		# [centro, normal, ancho, alto]
		[Vector3(Skatepark.LANE_START + 0.02, 1.2, z1 + 2.5), Vector3.RIGHT, 2.4, 1.0],
		[Vector3(0.0, 1.12, z1), gap_land_n, 3.0, 1.5],
		[Vector3(-6.5, 1.2, z3), drop_bank_n, 3.0, 1.5],
		[Vector3(14.0, 0.5, z3), box_land_n, 2.4, 1.2],
		[Vector3(25.2, 0.6, z1), qp_n, 2.6, 1.3],
		[Vector3(25.2, 0.6, z3), qp_n, 2.6, 1.3],
		[Vector3(8.48, 0.6, z3), Vector3.LEFT, 1.6, 0.8],
				[Vector3(12.0, 0.35, 16.99), Vector3.FORWARD, 2.0, 0.7],
		[Vector3(12.0, 0.35, -16.99), Vector3.BACK, 2.0, 0.7],
		[Vector3(-17.0, dh, 8.0), up, 2.4, 1.2],
		[Vector3(-17.0, dh, -8.0), up, 2.4, 1.2],
		[Vector3(14.0, 0.0, -9.0), up, 2.4, 1.2],
		[Vector3(-7.2, 0.0, 0.0), up, 1.6, 1.0],
		# mobiliario
		[Vector3(-19.0, dh + 0.55, 15.27), Vector3.FORWARD, 1.6, 0.8],
		[Vector3(21.5, 0.5, -15.85), Vector3.BACK, 0.55, 0.45],
	]
	for i in spots.size():
		var s: Array = spots[i]
		_decal(s[0], s[1], s[2], s[3], _tags[i % _tags.size()])


func _decal(center: Vector3, n: Vector3, width: float, height: float, tex: Texture2D) -> void:
	var d := Decal.new()
	d.texture_albedo = tex
	d.size = Vector3(width, 0.5, height)
	d.cull_mask = 1 << (DECAL_LAYER - 1)
	d.normal_fade = 0.45
	d.modulate = Color(1, 1, 1, 0.92)
	var y := n.normalized()
	var z := Vector3.DOWN - y * Vector3.DOWN.dot(y)
	if z.length() < 0.1:
		z = Vector3.BACK
	z = z.normalized()
	var x := y.cross(z).normalized()
	d.transform = Transform3D(Basis(x, y, z), center)
	add_child(d)


# ---------------------------------------------------------------- mobiliario

func _build_props() -> void:
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dh := Skatepark.DECK_H
	_dumpster(Vector3(-19.0, dh, 15.8), 0.0)
	_bin(Vector3(21.5, 0.0, -16.2))
	_bin(Vector3(22.3, 0.0, -16.1))
	for p in [Vector3(7.0, 0, 5.0), Vector3(12.0, 0, -5.0), Vector3(17.0, 0, 5.0), Vector3(-12.0, dh, -6.0)]:
		_cone(p)
	_sign(Vector3(22.8, 0.0, 16.4))
	_sign(Vector3(-14.0, dh, 16.4))
	var mi := MeshInstance3D.new()
	mi.mesh = _st.commit()
	mi.material_override = Skatepark.lowpoly_material()
	mi.layers = 1 | (1 << (DECAL_LAYER - 1))
	add_child(mi)


## Contenedor grande con tapa; es sólido (se choca y se puede grindar el canto).
func _dumpster(c: Vector3, yaw: float) -> void:
	var w := 1.9
	var d := 1.05
	var h := 1.1
	var b := Basis(Vector3.UP, yaw)
	_box_tapered(c, b, Vector3(w * 0.92, 0.0, d * 0.88), Vector3(w, h, d), C_DUMPSTER)
	# tapa algo abierta
	var lid := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -0.18)
	_box_tapered(c + b * Vector3(0, h + 0.03, -0.05), lid, Vector3(w * 1.02, 0.0, d * 1.04), Vector3(w * 1.02, 0.06, d * 1.04), C_LID)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box_tapered(c + b * Vector3(sx * w * 0.38, -0.0, sz * d * 0.32), b, Vector3(0.1, 0, 0.1), Vector3(0.1, 0.12, 0.1), C_DARK)
	if park:
		var half := (b * Vector3(w * 0.5, 0, d * 0.5)).abs()
		park.add_solid(Vector2(c.x - half.x, c.z - half.z), Vector2(c.x + half.x, c.z + half.z), c.y + h)


## Cubo de basura con ruedas.
func _bin(c: Vector3) -> void:
	_box_tapered(c, Basis(), Vector3(0.52, 0, 0.6), Vector3(0.6, 0.95, 0.7), C_BIN)
	_box_tapered(c + Vector3(0, 0.95, 0), Basis(), Vector3(0.64, 0, 0.74), Vector3(0.64, 0.05, 0.74), C_BIN.darkened(0.25))
	if park:
		park.add_solid(Vector2(c.x - 0.32, c.z - 0.37), Vector2(c.x + 0.32, c.z + 0.37), c.y + 1.0)


func _cone(c: Vector3) -> void:
	_box_tapered(c, Basis(), Vector3(0.42, 0, 0.42), Vector3(0.42, 0.04, 0.42), C_CONE.darkened(0.2))
	var sides := 6
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		for band in [[0.04, 0.3, 0.16, 0.11, C_CONE], [0.3, 0.42, 0.11, 0.085, C_WHITE], [0.42, 0.68, 0.085, 0.02, C_CONE]]:
			var y0: float = band[0]
			var y1: float = band[1]
			var r0: float = band[2]
			var r1: float = band[3]
			var col: Color = band[4]
			var p0 := c + Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p1 := c + Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p2 := c + Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			var p3 := c + Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var n := Vector3(cos((a0 + a1) * 0.5), 0.35, sin((a0 + a1) * 0.5)).normalized()
			_quad(p0, p1, p2, p3, n, col)


## Señal de "prohibido patinar" en su poste.
func _sign(c: Vector3) -> void:
	_box_tapered(c, Basis(), Vector3(0.06, 0, 0.06), Vector3(0.06, 2.3, 0.06), C_POLE)
	var center := c + Vector3(0, 2.0, 0.05)
	var sides := 10
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var r := 0.36
		_tri(center, center + Vector3(cos(a0) * r, sin(a0) * r, 0), center + Vector3(cos(a1) * r, sin(a1) * r, 0), Vector3.BACK, C_SIGN)
		var ri := 0.27
		_tri(center + Vector3(0, 0, 0.005), center + Vector3(cos(a0) * ri, sin(a0) * ri, 0.005), center + Vector3(cos(a1) * ri, sin(a1) * ri, 0.005), Vector3.BACK, C_WHITE)
	_quad(center + Vector3(-0.22, -0.2, 0.01), center + Vector3(-0.17, -0.25, 0.01), center + Vector3(0.22, 0.2, 0.01), center + Vector3(0.17, 0.25, 0.01), Vector3.BACK, C_SIGN)


## Caja que se estrecha hacia abajo (base = tamaño inferior, size = superior).
func _box_tapered(c: Vector3, b: Basis, base: Vector3, size: Vector3, col: Color) -> void:
	var hb := Vector2(base.x, base.z) * 0.5
	var ht := Vector2(size.x, size.z) * 0.5
	var bot := [Vector3(-hb.x, 0, -hb.y), Vector3(hb.x, 0, -hb.y), Vector3(hb.x, 0, hb.y), Vector3(-hb.x, 0, hb.y)]
	var top := [Vector3(-ht.x, size.y, -ht.y), Vector3(ht.x, size.y, -ht.y), Vector3(ht.x, size.y, ht.y), Vector3(-ht.x, size.y, ht.y)]
	for i in 4:
		bot[i] = c + b * bot[i]
		top[i] = c + b * top[i]
	_quad(top[0], top[1], top[2], top[3], b * Vector3.UP, col)
	var normals := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
	for i in 4:
		var j := (i + 1) % 4
		_quad(bot[i], bot[j], top[j], top[i], b * normals[i], col)


func _tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		var t := b
		b = c
		c = t
	for p in [a, b, c]:
		_st.set_color(col)
		_st.set_normal(n)
		_st.add_vertex(p)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	_tri(a, b, c, n, col)
	_tri(a, c, d, n, col)

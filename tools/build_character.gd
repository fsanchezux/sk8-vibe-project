extends SceneTree
## Monta el personaje a partir de los OBJ del kit (assets/character/src) y lo guarda
## como malla con pesos de piel lista para el esqueleto de CharacterRig.
## Las prendas se pueden recolorear (apuntando las UV al blanco o al negro de la
## paleta), hinchar hacia fuera (ropa oversize) y alargar el dobladillo.
##
## Ejecutar desde la carpeta del proyecto:
##   godot --headless --path . -s tools/build_character.gd

const SRC := "res://assets/character/src/"


func _initialize() -> void:
	var swatches := _find_swatches()
	var pos := PackedVector3Array()
	var nor := PackedVector3Array()
	var uv := PackedVector2Array()
	for part in CharacterRig.OUTFIT_PARTS:
		var d := ObjLoader.load_obj(SRC + String(part[0]) + ".obj")
		var p: PackedVector3Array = d["pos"]
		var n: PackedVector3Array = d["normal"]
		var u: PackedVector2Array = d["uv"]
		var recolor: String = part[1]
		var inflate: float = part[2]
		var hem: float = part[3]
		if inflate > 0.0 or hem > 0.0:
			_loosen(p, n, inflate, hem)
		if recolor != "":
			var target: Vector2 = swatches[recolor]
			for i in u.size():
				u[i] = target
		pos.append_array(p)
		nor.append_array(n)
		uv.append_array(u)
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	bones.resize(pos.size() * 4)
	weights.resize(pos.size() * 4)
	for i in pos.size():
		var bw: Array = CharacterRig.weights_for(pos[i])
		var b: PackedInt32Array = bw[0]
		var w: PackedFloat32Array = bw[1]
		for k in 4:
			bones[i * 4 + k] = b[k]
			weights[i * 4 + k] = w[k]
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pos
	arr[Mesh.ARRAY_NORMAL] = nor
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var path := CharacterRig.MESH_PATH % CharacterRig.OUTFIT_ID
	var err := ResourceSaver.save(mesh, path)
	print("%s: %d vértices -> %s (%s)" % [CharacterRig.OUTFIT_ID, pos.size(), path, error_string(err)])
	quit()


## Ropa holgada: empuja cada vértice hacia fuera por su normal (más abajo, en los bajos
## del pantalón y el dobladillo de la camiseta) y baja la parte inferior de la prenda.
func _loosen(p: PackedVector3Array, n: PackedVector3Array, inflate: float, hem: float) -> void:
	var y_min := INF
	var y_max := -INF
	for v in p:
		y_min = minf(y_min, v.y)
		y_max = maxf(y_max, v.y)
	var span := maxf(y_max - y_min, 0.001)
	for i in p.size():
		var k := 1.0 - (p[i].y - y_min) / span # 1 abajo, 0 arriba
		var amount := inflate * (0.6 + 0.8 * k)
		var out := Vector3(n[i].x, n[i].y * 0.3, n[i].z)
		p[i] += out * amount
		p[i].y -= hem * k * k


## Busca en la textura-paleta el píxel más blanco y el más negro (columna de grises).
func _find_swatches() -> Dictionary:
	var img: Image = (load("res://assets/character/Textures_4.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var best_w := -1.0
	var best_b := 2.0
	var white := Vector2(0.9, 0.02)
	var black := Vector2(0.9, 0.48)
	var w := img.get_width()
	var h := img.get_height()
	for y in range(0, h / 2, 4):
		for x in range(int(w * 0.82), int(w * 0.95), 4):
			var c := img.get_pixel(x, y)
			var sat := maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
			if sat > 0.08:
				continue
			var l := c.get_luminance()
			if l > best_w:
				best_w = l
				white = Vector2((x + 0.5) / w, (y + 0.5) / h)
			if l < best_b:
				best_b = l
				black = Vector2((x + 0.5) / w, (y + 0.5) / h)
	print("blanco %s (%.2f)  negro %s (%.2f)" % [white, best_w, black, best_b])
	return {"white": white, "black": black}

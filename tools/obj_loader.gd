class_name ObjLoader
extends RefCounted
## Lector mínimo de OBJ (v, vt, vn, f). Devuelve los triángulos ya desindexados:
## {"pos": PackedVector3Array, "uv": PackedVector2Array, "normal": PackedVector3Array}.
## Lo usa tools/build_character.gd para montar el personaje.


static func load_obj(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("No se puede abrir %s" % path)
		return {}
	var vs: Array[Vector3] = []
	var vts: Array[Vector2] = []
	var vns: Array[Vector3] = []
	var pos := PackedVector3Array()
	var uv := PackedVector2Array()
	var nor := PackedVector3Array()
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line[0] == "#":
			continue
		var parts := line.split(" ", false)
		match parts[0]:
			"v":
				vs.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
			"vt":
				vts.append(Vector2(parts[1].to_float(), 1.0 - parts[2].to_float()))
			"vn":
				vns.append(Vector3(parts[1].to_float(), parts[2].to_float(), parts[3].to_float()))
			"f":
				var corners: Array[PackedInt32Array] = []
				for i in range(1, parts.size()):
					var idx := parts[i].split("/")
					var c := PackedInt32Array([idx[0].to_int() - 1, -1, -1])
					if idx.size() > 1 and idx[1] != "":
						c[1] = idx[1].to_int() - 1
					if idx.size() > 2 and idx[2] != "":
						c[2] = idx[2].to_int() - 1
					corners.append(c)
				# Abanico de triángulos. Godot usa orden horario para la cara frontal,
				# el OBJ antihorario: se invierte el orden.
				for i in range(1, corners.size() - 1):
					for c in [corners[0], corners[i + 1], corners[i]]:
						pos.append(vs[c[0]])
						uv.append(vts[c[1]] if c[1] >= 0 else Vector2.ZERO)
						nor.append(vns[c[2]] if c[2] >= 0 else Vector3.UP)
	return {"pos": pos, "uv": uv, "normal": nor}

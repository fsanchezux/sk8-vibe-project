extends SceneTree
## Exporta los sonidos sintetizados de SkaterAudio a assets/audio/sfx/*.wav para
## poder editarlos (Audacity, etc.). Sobrescribe los que ya existan.
##
## Ejecutar desde la carpeta del proyecto:
##   godot --headless --path . -s tools/export_sfx.gd

const OUT := "res://assets/audio/sfx/"


func _initialize() -> void:
	var a := SkaterAudio.new()
	a._rng.seed = 7
	var sounds := {
		"pop": a._make_pop(),
		"catch": a._make_click(),
		"land": a._make_land(),
		"roll": a._make_roll(),
		"grind": a._make_grind(),
		"skid": a._make_skid(),
		"celebrate": a._make_celebrate(),
		"scrape": a._make_scrape(),
	}
	for sfx_name in sounds:
		var path: String = OUT + sfx_name + ".wav"
		var err: int = (sounds[sfx_name] as AudioStreamWAV).save_to_wav(path)
		print("%s -> %s" % [path, "ok" if err == OK else "error %d" % err])
	a.free()
	quit()

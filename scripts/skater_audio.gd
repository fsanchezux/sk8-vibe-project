class_name SkaterAudio
extends Node
## Sonidos del skater: pop del tail, "clac" al planchar el truco, aterrizaje,
## rodadura, grind, derrape, celebración y tail arrastrando.
## Cada sonido se busca como archivo en assets/audio/sfx/<nombre>.wav (o .ogg/.mp3)
## y, si no existe, se sintetiza por código. Para cambiar uno basta con sustituir el
## archivo (ver assets/audio/README.md).

const RATE := 22050
const SFX_DIR := "res://assets/audio/sfx/"
const SFX_EXT := ["wav", "ogg", "mp3"]

var _pop: AudioStreamPlayer
var _catch: AudioStreamPlayer
var _land: AudioStreamPlayer
var _roll: AudioStreamPlayer
var _grind: AudioStreamPlayer
var _skid: AudioStreamPlayer
var _celebrate: AudioStreamPlayer
var _scrape: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	_pop = _player(_sfx("pop", _make_pop(), false), -2.0)
	_catch = _player(_sfx("catch", _make_click(), false), -6.0)
	_land = _player(_sfx("land", _make_land(), false), 0.0)
	_roll = _player(_sfx("roll", _make_roll(), true), -80.0)
	_grind = _player(_sfx("grind", _make_grind(), true), -80.0)
	_skid = _player(_sfx("skid", _make_skid(), false), -4.0)
	_celebrate = _player(_sfx("celebrate", _make_celebrate(), false), -5.0)
	_scrape = _player(_sfx("scrape", _make_scrape(), true), -80.0)
	_scrape.play()
	_roll.play()
	_grind.play()


func pop(power: float) -> void:
	_pop.pitch_scale = randf_range(0.95, 1.08)
	_pop.volume_db = lerpf(-8.0, -1.0, power)
	_pop.play()


func catch_board() -> void:
	_catch.pitch_scale = randf_range(1.1, 1.25)
	_catch.play()


func land(strength: float) -> void:
	_land.pitch_scale = randf_range(0.92, 1.05)
	_land.volume_db = lerpf(-12.0, 0.0, clampf(strength, 0.0, 1.0))
	_land.play()


## Derrape de las ruedas en un revert.
func skid(strength: float) -> void:
	_skid.pitch_scale = randf_range(0.94, 1.06)
	_skid.volume_db = lerpf(-20.0, -9.0, clampf(strength, 0.0, 1.0))
	_skid.play()


## Truco caído con combo x2 o más: campanitas que suben de tono con el multiplicador.
func celebrate(level: int) -> void:
	_celebrate.pitch_scale = minf(1.0 + (level - 3) * 0.06, 1.5)
	_celebrate.volume_db = minf(-17.0 + level * 0.6, -11.0)
	_celebrate.play()


## Tail arrastrando al frenar (velocidad, 0 = en silencio).
func scrape(speed: float) -> void:
	var k := clampf(speed / 8.0, 0.0, 1.0) if speed > 0.6 else 0.0
	_scrape.volume_db = linear_to_db(maxf(k * 0.7, 0.0001))
	_scrape.pitch_scale = 0.8 + k * 0.4


func bail() -> void:
	_land.pitch_scale = 0.7
	_land.volume_db = 0.0
	_land.play()


## Llamar cada frame. rolling/grinding: velocidad (0 si no está en ese estado).
func update(rolling: float, grinding: float) -> void:
	var r := clampf(rolling / 12.0, 0.0, 1.0)
	_roll.volume_db = linear_to_db(maxf(r * 0.55, 0.0001))
	_roll.pitch_scale = 0.75 + r * 0.6
	var g := clampf(grinding / 6.0, 0.25, 1.0) if grinding > 0.0 else 0.0
	_grind.volume_db = linear_to_db(maxf(g * 0.6, 0.0001))
	_grind.pitch_scale = 0.85 + g * 0.3


## Archivo de assets/audio/sfx/ si existe; si no, el sonido sintetizado.
func _sfx(sfx_name: String, fallback: AudioStreamWAV, loop: bool) -> AudioStream:
	for ext in SFX_EXT:
		var path: String = SFX_DIR + sfx_name + "." + ext
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path) as AudioStream
		if stream == null:
			continue
		if loop:
			_set_loop(stream)
		return stream
	return fallback


func _set_loop(stream: AudioStream) -> void:
	if stream is AudioStreamWAV:
		var w := stream as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	elif stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _player(stream: AudioStream, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	return p


# ---------------------------------------------------------------- síntesis

func _make_pop() -> AudioStreamWAV:
	# Chasquido de madera contra el suelo: ruido agudo muy corto + golpe grave.
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		hp = 0.7 * (hp + noise - prev)
		prev = noise
		var crack := hp * exp(-t * 70.0) * 0.9
		var knock := sin(TAU * 950.0 * t) * exp(-t * 90.0) * 0.5
		var thump := sin(TAU * 140.0 * t) * exp(-t * 28.0) * 0.6
		s[i] = crack + knock + thump
	return _wav(s, false)


func _make_click() -> AudioStreamWAV:
	# "Clac" seco de los pies atrapando la tabla.
	var n := int(RATE * 0.08)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		s[i] = (noise * 0.5 + sin(TAU * 1700.0 * t) * 0.5) * exp(-t * 110.0)
	return _wav(s, false)


func _make_land() -> AudioStreamWAV:
	# Las cuatro ruedas y la tabla golpeando: golpe grave + chasquido + traqueteo.
	var n := int(RATE * 0.32)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.25
		var thump := sin(TAU * (75.0 - t * 60.0) * t) * exp(-t * 16.0) * 0.9
		var slap := lp * exp(-t * 30.0) * 0.9
		var crack := noise * exp(-t * 120.0) * 0.4
		var rattle := sin(TAU * 420.0 * t) * exp(-maxf(t - 0.03, 0.0) * 35.0) * (0.15 if t > 0.03 else 0.0)
		s[i] = thump + slap + crack + rattle
	return _wav(s, false)


func _make_roll() -> AudioStreamWAV:
	# Rodadura sobre hormigón: ruido grave con el "tac" de las juntas.
	var n := RATE
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.08
		lp2 += (lp - lp2) * 0.3
		var joint := sin(TAU * 4.0 * t)
		var tick := maxf(joint, 0.0) ** 30.0 * noise * 0.4
		s[i] = lp2 * 2.2 + tick
	return _wav(_crossfade(s, 800), true)


func _make_grind() -> AudioStreamWAV:
	# Metal rascando: ruido de banda media + parciales metálicos que fluctúan.
	var n := int(RATE * 0.8)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp_a := 0.0
	var lp_b := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		lp_a += (noise - lp_a) * 0.5
		lp_b += (noise - lp_b) * 0.08
		var band := lp_a - lp_b
		var wob := 0.6 + 0.4 * sin(TAU * 13.0 * t) * sin(TAU * 3.0 * t)
		var metal := (sin(TAU * 1830.0 * t) * 0.3 + sin(TAU * 2740.0 * t) * 0.2 + sin(TAU * 4110.0 * t) * 0.1) * wob
		s[i] = band * 0.8 + metal * 0.5
	return _wav(_crossfade(s, 800), true)


func _make_skid() -> AudioStreamWAV:
	# Ruedas deslizando de lado sobre el hormigón: un "shhh" suave y apagado con el
	# grano del uretano rozando, sin chirrido. Una tirada de _rng por muestra, como
	# antes, para no cambiar los sonidos que se generan después.
	var n := int(RATE * 0.6)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rumble := 0.0
	var grain := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := minf(t / 0.05, 1.0) * exp(-t * 4.0) * (1.0 - smoothstep(0.42, 0.6, t))
		var noise := _rng.randf_range(-1.0, 1.0)
		# Banda media-grave (sin agudos): el siseo del deslizamiento
		lp += (noise - lp) * 0.18
		lp2 += (lp - lp2) * 0.02
		var hiss := lp - lp2
		# Fondo grave de la tabla vibrando
		rumble += (noise - rumble) * 0.008
		# Grano irregular de las ruedas al rozar (va frenando)
		grain += TAU * (52.0 - t * 30.0) / RATE
		var rough := 0.7 + 0.3 * sin(grain) * sin(grain * 0.37)
		s[i] = (hiss * 0.9 * rough + rumble * 2.0) * env
	return _wav(s, false)


func _make_celebrate() -> AudioStreamWAV:
	# Arpegio pentatónico de campanas (do, mi, sol, la, do) con un brillo de fondo.
	var notes := [523.25, 659.25, 783.99, 880.0, 1046.5]
	var n := int(RATE * 0.9)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in notes.size():
		var f0: float = notes[k]
		var start := int(RATE * 0.045 * k)
		for i in range(start, n):
			var t := float(i - start) / RATE
			var env := exp(-t * 5.5) * minf(t / 0.004, 1.0)
			var bell := sin(TAU * f0 * t) + 0.35 * sin(TAU * f0 * 2.76 * t) * exp(-t * 9.0) + 0.15 * sin(TAU * f0 * 5.4 * t) * exp(-t * 14.0)
			s[i] += bell * env * 0.22
	var hp := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		hp = 0.6 * (hp + noise - prev)
		prev = noise
		s[i] += hp * 0.06 * exp(-t * 4.0) * minf(t / 0.08, 1.0)
		# Golpe grave al inicio (da cuerpo) y destello agudo al final del arpegio
		s[i] += sin(TAU * 110.0 * t) * exp(-t * 14.0) * 0.28
		var tw := t - 0.2
		if tw > 0.0:
			s[i] += sin(TAU * 2093.0 * tw) * exp(-tw * 7.0) * minf(tw / 0.003, 1.0) * 0.07
	return _wav(s, false)


func _make_scrape() -> AudioStreamWAV:
	# Madera y lija rascando el suelo: ruido áspero de banda media con algo de traqueteo.
	var n := int(RATE * 0.7)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * 0.3
		lp2 += (lp - lp2) * 0.04
		var chatter := 0.7 + 0.3 * sin(TAU * 31.0 * t)
		s[i] = (lp - lp2) * 1.6 * chatter
	return _wav(_crossfade(s, 600), true)


## Funde el final con el principio para que el bucle no haga clic.
func _crossfade(s: PackedFloat32Array, len_cf: int) -> PackedFloat32Array:
	var n := s.size()
	var out := s.slice(0, n - len_cf)
	for i in len_cf:
		var k := float(i) / len_cf
		out[i] = s[i] * k + s[n - len_cf + i] * (1.0 - k)
	return out


func _wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w

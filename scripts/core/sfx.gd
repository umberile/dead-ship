extends Node
## Autoload `Sfx`: procedural sound library and playback helpers.
##
## Two buses are created at boot:
##   World - everything that happens in the ship. Runs through a low-pass that
##           follows ambient pressure, so a vacuum sounds dull and distant and
##           the ship "gets its voice back" as it repressurises.
##   Suit  - HUD and suit sounds, unaffected by the environment.

const BUS_WORLD := &"World"
const BUS_SUIT := &"Suit"

var _lib := {}
var _lowpass: AudioEffectLowPassFilter
var _world_bus := -1
var _pressure := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_build_library()
	set_ambient_pressure(101.3)


func _setup_buses() -> void:
	for bus_name in [BUS_WORLD, BUS_SUIT]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")
	_world_bus = AudioServer.get_bus_index(BUS_WORLD)
	if AudioServer.get_bus_effect_count(_world_bus) == 0:
		_lowpass = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(_world_bus, _lowpass)
	else:
		_lowpass = AudioServer.get_bus_effect(_world_bus, 0) as AudioEffectLowPassFilter


## Muffles world audio in thin atmosphere. 0 kPa is not fully silent: sound
## still reaches the player through the suit and hull contact.
func set_ambient_pressure(kpa: float) -> void:
	if absf(kpa - _pressure) < 0.25:
		return
	_pressure = kpa
	var t := clampf(kpa / 101.3, 0.0, 1.0)
	_lowpass.cutoff_hz = 320.0 * pow(18000.0 / 320.0, t)
	AudioServer.set_bus_volume_db(_world_bus, lerpf(-7.0, 0.0, t))


func has(id: StringName) -> bool:
	return _lib.has(id)


## One-shot positional sound in the ship.
func play_at(id: StringName, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _lib.has(id):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _lib[id]
	p.bus = BUS_WORLD
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.unit_size = 3.5
	p.max_distance = 45.0
	add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()


## One-shot non-positional sound (HUD / suit).
func play_ui(id: StringName, volume_db := 0.0, pitch := 1.0) -> void:
	if not _lib.has(id):
		return
	var p := AudioStreamPlayer.new()
	p.stream = _lib[id]
	p.bus = BUS_SUIT
	p.volume_db = volume_db
	p.pitch_scale = pitch
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


## Creates (but does not start) a positional looping player under `parent`.
func make_loop(id: StringName, parent: Node3D, volume_db := 0.0, unit_size := 3.5) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = _lib.get(id)
	p.bus = BUS_WORLD
	p.volume_db = volume_db
	p.unit_size = unit_size
	p.max_distance = 45.0
	parent.add_child(p)
	return p


## Creates (but does not start) a non-positional looping player on the Suit bus.
func make_ui_loop(id: StringName, parent: Node, volume_db := 0.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _lib.get(id)
	p.bus = BUS_SUIT
	p.volume_db = volume_db
	parent.add_child(p)
	return p


# --- Library ---------------------------------------------------------------

func _add(id: StringName, b: PackedFloat32Array, loop := false, peak := 0.85) -> void:
	AudioSynth.normalize(b, peak)
	_lib[id] = AudioSynth.to_stream(b, loop)


func _build_library() -> void:
	AudioSynth.reseed(4417)
	var b: PackedFloat32Array

	# Switches, levers, latches.
	b = AudioSynth.buffer(0.05)
	AudioSynth.add_noise(b, 0.8, 90.0, 0.7, 0.2)
	AudioSynth.add_tone(b, 2100.0, 0.4, 120.0)
	_add(&"click", b, false, 0.7)

	b = AudioSynth.buffer(0.3)
	AudioSynth.add_tone(b, 95.0, 1.0, 16.0, 60.0)
	AudioSynth.add_noise(b, 0.6, 30.0, 0.25)
	AudioSynth.add_tone(b, 640.0, 0.15, 40.0)
	_add(&"clunk", b)

	b = AudioSynth.buffer(0.07)
	AudioSynth.add_noise(b, 0.7, 70.0, 0.4, 0.1)
	AudioSynth.add_tone(b, 900.0, 0.3, 90.0)
	_add(&"ratchet", b, false, 0.6)

	# Deposit / reject.
	b = AudioSynth.buffer(0.4)
	AudioSynth.add_tone(b, 80.0, 1.0, 11.0, 44.0)
	AudioSynth.add_noise(b, 0.5, 22.0, 0.15)
	_add(&"thunk", b)

	b = AudioSynth.buffer(0.34)
	AudioSynth.add_saw(b, 110.0, 0.5)
	AudioSynth.add_saw(b, 113.0, 0.4)
	AudioSynth.modulate(b, 5.9, 1.0)
	AudioSynth.fade(b, 0.005, 0.03)
	_add(&"buzz", b, false, 0.55)

	# Carrying.
	b = AudioSynth.buffer(0.09)
	AudioSynth.add_noise(b, 0.6, 50.0, 0.3)
	AudioSynth.add_tone(b, 420.0, 0.3, 60.0, 620.0)
	_add(&"pickup", b, false, 0.5)

	b = AudioSynth.buffer(0.24)
	AudioSynth.add_noise(b, 1.0, 0.0, 0.18, 0.02)
	AudioSynth.fade(b, 0.06, 0.16)
	_add(&"whoosh", b, false, 0.6)

	b = AudioSynth.buffer(0.35)
	AudioSynth.add_tone(b, 523.0, 0.5, 22.0)
	AudioSynth.add_tone(b, 1187.0, 0.35, 30.0)
	AudioSynth.add_tone(b, 1931.0, 0.2, 40.0)
	AudioSynth.add_tone(b, 140.0, 0.6, 35.0)
	AudioSynth.add_noise(b, 0.5, 80.0, 0.6)
	_add(&"impact", b, false, 0.8)

	b = AudioSynth.buffer(0.14)
	AudioSynth.add_tone(b, 70.0, 1.0, 40.0, 50.0)
	AudioSynth.add_noise(b, 0.35, 60.0, 0.2)
	AudioSynth.add_tone(b, 310.0, 0.1, 50.0)
	_add(&"footstep", b, false, 0.6)

	# Electrical.
	b = AudioSynth.buffer(0.2)
	AudioSynth.add_crackle(b, 1.0, 900.0, 0.35)
	AudioSynth.add_noise(b, 0.4, 25.0, 0.9, 0.5)
	AudioSynth.fade(b, 0.0, 0.1)
	_add(&"spark", b, false, 0.75)

	b = AudioSynth.buffer(1.0)
	AudioSynth.add_saw(b, 100.0, 0.35)
	AudioSynth.add_saw(b, 200.0, 0.15)
	AudioSynth.add_crackle(b, 0.7, 240.0, 0.4)
	AudioSynth.modulate(b, 30.0, 0.5)
	_add(&"zap_loop", b, true, 0.6)

	b = AudioSynth.buffer(2.0)
	AudioSynth.add_tone(b, 55.0, 0.8)
	AudioSynth.add_tone(b, 110.0, 0.4)
	AudioSynth.add_tone(b, 165.5, 0.18)
	AudioSynth.add_tone(b, 220.0, 0.08)
	AudioSynth.modulate(b, 0.5, 0.2)
	_add(&"hum_loop", b, true, 0.7)

	b = AudioSynth.buffer(2.6)
	AudioSynth.add_tone(b, 28.0, 0.7, 0.0, 110.0)
	AudioSynth.add_saw(b, 30.0, 0.18, 0.0, 120.0)
	AudioSynth.add_tone(b, 56.0, 0.3, 0.0, 220.0)
	AudioSynth.add_noise(b, 0.12, 0.0, 0.1)
	AudioSynth.fade(b, 0.3, 0.5)
	_add(&"power_up", b)

	b = AudioSynth.buffer(1.4)
	AudioSynth.add_tone(b, 110.0, 0.7, 1.5, 24.0)
	AudioSynth.add_saw(b, 120.0, 0.15, 2.0, 26.0)
	AudioSynth.fade(b, 0.01, 0.5)
	_add(&"power_down", b)

	# Tools.
	b = AudioSynth.buffer(0.9)
	AudioSynth.add_noise(b, 1.0, 0.0, 0.5, 0.12)
	AudioSynth.modulate(b, 5.0, 0.75)
	b = AudioSynth.loopable(b, 0.1)
	_add(&"scrub_loop", b, true, 0.6)

	b = AudioSynth.buffer(1.3)
	AudioSynth.add_noise(b, 0.7, 0.0, 0.85, 0.35)
	AudioSynth.add_crackle(b, 0.6, 420.0, 0.5)
	AudioSynth.add_saw(b, 60.0, 0.12)
	b = AudioSynth.loopable(b, 0.1)
	_add(&"seal_loop", b, true, 0.6)

	# Atmosphere and machinery.
	b = AudioSynth.buffer(1.7)
	AudioSynth.add_noise(b, 1.0, 0.0, 0.35, 0.03)
	b = AudioSynth.loopable(b, 0.2)
	_add(&"hiss_loop", b, true, 0.6)

	b = AudioSynth.buffer(1.7)
	AudioSynth.add_noise(b, 0.8, 0.0, 0.06)
	AudioSynth.add_tone(b, 117.5, 0.1)
	b = AudioSynth.loopable(b, 0.2)
	AudioSynth.modulate(b, 4.0, 0.15)
	_add(&"fan_loop", b, true, 0.6)

	b = AudioSynth.buffer(2.0)
	AudioSynth.add_tone(b, 38.0, 0.9)
	AudioSynth.add_tone(b, 76.0, 0.3)
	AudioSynth.add_tone(b, 114.5, 0.1)
	AudioSynth.modulate(b, 1.5, 0.45)
	_add(&"grav_loop", b, true, 0.75)

	b = AudioSynth.buffer(0.6)
	AudioSynth.add_saw(b, 70.0, 0.5)
	AudioSynth.add_noise(b, 0.4, 0.0, 0.2)
	AudioSynth.modulate(b, 20.0, 0.4)
	_add(&"door_loop", b, true, 0.55)

	b = AudioSynth.buffer(0.8)
	AudioSynth.add_noise(b, 1.0, 0.0, 0.6, 0.2)
	b = AudioSynth.loopable(b, 0.1)
	_add(&"thruster_loop", b, true, 0.5)

	b = AudioSynth.buffer(4.0)
	AudioSynth.add_noise(b, 0.5, 0.0, 0.03)
	AudioSynth.modulate(b, 0.25, 0.8)
	AudioSynth.add_tone(b, 46.0, 0.12)
	_add(&"suit_loop", b, true, 0.5)

	# Feedback.
	b = AudioSynth.buffer(0.6)
	var part := AudioSynth.buffer(0.6)
	AudioSynth.add_tone(b, 880.0, 0.6, 9.0)
	AudioSynth.add_tone(b, 1760.0, 0.15, 12.0)
	AudioSynth.add_tone(part, 1318.5, 0.6, 7.0)
	for i in part.size() - 2600:
		b[i + 2600] += part[i]
	_add(&"chime", b, false, 0.6)

	b = AudioSynth.buffer(1.8)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for k in notes.size():
		part = AudioSynth.buffer(1.8 - k * 0.16)
		AudioSynth.add_tone(part, notes[k], 0.5, 2.6)
		AudioSynth.add_tone(part, notes[k] * 2.0, 0.12, 4.0)
		var off := int(k * 0.16 * AudioSynth.RATE)
		for i in part.size():
			b[i + off] += part[i]
	AudioSynth.fade(b, 0.004, 0.3)
	_add(&"complete", b, false, 0.7)

	b = AudioSynth.buffer(0.45)
	for k in 5:
		part = AudioSynth.buffer(0.2)
		AudioSynth.add_tone(part, 2200.0 + k * 410.0, 0.5, 26.0)
		var off := int(k * 0.05 * AudioSynth.RATE)
		for i in part.size():
			b[i + off] += part[i]
	_add(&"sparkle", b, false, 0.5)

	b = AudioSynth.buffer(0.55)
	AudioSynth.add_tone(b, 1900.0, 0.7, 7.0, 950.0)
	AudioSynth.add_tone(b, 950.0, 0.2, 9.0)
	_add(&"scan", b, false, 0.45)

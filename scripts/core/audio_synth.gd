class_name AudioSynth
## Tiny additive/noise synthesiser used to build placeholder sound effects at
## boot, so the prototype ships with no audio files at all.

const RATE := 22050

static var _rng := RandomNumberGenerator.new()


static func reseed(value: int) -> void:
	_rng.seed = value


static func buffer(seconds: float) -> PackedFloat32Array:
	var b := PackedFloat32Array()
	b.resize(int(seconds * RATE))
	return b


## Adds a sine. `freq_end` >= 0 sweeps linearly to that frequency; `decay` is an
## exponential falloff rate per second.
static func add_tone(b: PackedFloat32Array, freq: float, amp: float, decay := 0.0, freq_end := -1.0) -> void:
	var n := b.size()
	var f1 := freq if freq_end < 0.0 else freq_end
	var phase := 0.0
	for i in n:
		var f := lerpf(freq, f1, float(i) / n)
		phase += TAU * f / RATE
		var env := exp(-decay * i / RATE) if decay > 0.0 else 1.0
		b[i] += sin(phase) * amp * env


## Adds a buzzy sawtooth (same sweep/decay semantics as add_tone).
static func add_saw(b: PackedFloat32Array, freq: float, amp: float, decay := 0.0, freq_end := -1.0) -> void:
	var n := b.size()
	var f1 := freq if freq_end < 0.0 else freq_end
	var phase := 0.0
	for i in n:
		var f := lerpf(freq, f1, float(i) / n)
		phase = fmod(phase + f / RATE, 1.0)
		var env := exp(-decay * i / RATE) if decay > 0.0 else 1.0
		b[i] += (phase * 2.0 - 1.0) * amp * env


## Adds filtered white noise. `lp` is a one-pole low-pass coefficient (1 = off,
## small = darker); `hp` > 0 subtracts a slower low-pass to thin the low end.
static func add_noise(b: PackedFloat32Array, amp: float, decay := 0.0, lp := 1.0, hp := 0.0) -> void:
	var y := 0.0
	var z := 0.0
	for i in b.size():
		y += lp * (_rng.randf_range(-1.0, 1.0) - y)
		var o := y
		if hp > 0.0:
			z += hp * (y - z)
			o = y - z
		var env := exp(-decay * i / RATE) if decay > 0.0 else 1.0
		b[i] += o * amp * env


## Adds sparse random clicks, `rate` per second on average.
static func add_crackle(b: PackedFloat32Array, amp: float, rate: float, ring := 0.55) -> void:
	var c := 0.0
	var p := rate / RATE
	for i in b.size():
		c *= ring
		if _rng.randf() < p:
			c = _rng.randf_range(-1.0, 1.0)
		b[i] += c * amp


## Tremolo: multiplies by a raised sine between (1 - depth) and 1.
static func modulate(b: PackedFloat32Array, freq: float, depth: float) -> void:
	for i in b.size():
		b[i] *= 1.0 - depth * (0.5 + 0.5 * sin(TAU * freq * i / RATE))


static func fade(b: PackedFloat32Array, in_s: float, out_s: float) -> void:
	var n := b.size()
	var a := int(in_s * RATE)
	var r := int(out_s * RATE)
	for i in mini(a, n):
		b[i] *= float(i) / a
	for i in mini(r, n):
		b[n - 1 - i] *= float(i) / r


static func normalize(b: PackedFloat32Array, peak := 0.9) -> void:
	var m := 0.0001
	for v in b:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in b.size():
		b[i] *= k


## Cross-fades the tail into the head so a noise bed loops without a click.
static func loopable(b: PackedFloat32Array, xfade_s: float) -> PackedFloat32Array:
	var x := int(xfade_s * RATE)
	var n := b.size() - x
	var out := b.slice(0, n)
	for i in x:
		var t := float(i) / x
		out[i] = b[i] * t + b[n + i] * (1.0 - t)
	return out


static func to_stream(b: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(b.size() * 2)
	for i in b.size():
		bytes.encode_s16(i * 2, int(clampf(b[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = b.size()
	return s

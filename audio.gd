class_name GameAudio
extends Node
# Code-spawned SFX, same spirit as everything else in Astryx: rapid laser fire
# (pooled so shots overlap), a "crush" boom on alien death, and a three-part
# engine voice (start -> seamless loop -> stop) that the ship drives every frame.

const FIRE_VOICES := 8          # round-robin players so rapid shots overlap cleanly
const FIRE_DB := -19.0          # bullet fire — gentle/soft
const EXPLOSION_DB := -3.0

# --- Engine voice ---
# Mix intent: the engine is present and has weight, but the music still leads.
# Cruise sits just above the bgm (≈ -24 dB) so you clearly feel the engine; Shift
# opens it up into a powerful roar. Gunfire still punches over everything.
const ENGINE_LOOP_DB := -19.0   # cruise at full throttle — clearly audible
const ENGINE_QUIET_DB := -30.0  # barely on the gas — quiet idle
const ENGINE_BOOST_DB := 8.0    # Shift = powerful: a big, deep surge of body
const ENGINE_OFF_DB := -60.0    # effectively silent (loop fades here, then pauses)
const ENGINE_TRANS_DB := -15.0  # the one-shot start/stop "whoosh"
# Pitch shapes the character. Normal flight sits LOW/deep; Shift revs it UP into a
# faster, higher note (and we smooth harder so it glides in rather than snapping).
const ENGINE_PITCH_IDLE := 0.82
const ENGINE_PITCH_FULL := 0.92
const ENGINE_PITCH_BOOST := 1.10
# Slow eases so the engine swells in/out gently — never a sudden, jarring change.
const ENGINE_SMOOTH := 4.5      # normal ease toward target volume/pitch (per second)
const ENGINE_SMOOTH_BOOST := 2.5  # gentler ease while boosting -> "even smoother"
# Continuous-drive arc — the longer you hold a run, the more the mix moves from
# engine to music. This same clock (drive_time()) also gates the bgm fade-in:
#   0 .. MUSIC_IN_TIME (8s)   engine only, no music
#   MUSIC_IN_TIME ..          music fades in (handled in main._update_music)
#   DUCK_START..DUCK_FULL     engine recedes so the music leads
# The clock climbs while driving and unwinds when you ease off (no hard reset, so a
# brief coast doesn't restart the whole arc).
const MUSIC_IN_TIME := 8.0          # music only after this many seconds of steady drive
const DRIVE_MAX := 20.0             # clock cap (seconds)
const DRIVE_DECAY := 2.0            # how fast the clock unwinds when you let off
const ENGINE_SPOOL_TIME := 12.0     # pitch spools up to its cruise note over this long
const ENGINE_SUSTAIN_PITCH := 0.12  # pitch climbed at full cruise (×pitch_mul per ship)
const ENGINE_DUCK_START := 12.0     # engine starts receding (music takes over) at...
const ENGINE_DUCK_FULL := 15.0      # ...and is fully ducked by here
const ENGINE_SUSTAIN_DUCK := 7.0    # dB the engine drops once fully ducked

var _fire: Array[AudioStreamPlayer] = []
var _fire_i := 0
var _explosion: AudioStreamPlayer

# Per-ship loop streams (distinct timbre per hull, see tools/gen_engine_audio.py);
# falls back to the shared engine_loop.ogg for any hull without a dedicated file.
const SHIP_LOOPS := ["Lyra", "Stella", "Raptor", "Vela"]

var _eng_loop: AudioStreamPlayer
var _eng_start: AudioStreamPlayer
var _eng_stop: AudioStreamPlayer
var _eng_on := false            # is the engine currently "running" (loop active)?
var _eng_streams := {}          # ship name -> looping AudioStream
var _eng_default: AudioStream   # shared fallback loop
var _eng_ship := ""             # which ship's loop is currently loaded into _eng_loop
var _eng_sustain := 0.0         # seconds of continuous driving (drives cruise settle)


func _ready() -> void:
	var fire_stream := load("res://sfx_fire.wav") as AudioStream
	for i in FIRE_VOICES:
		var p := AudioStreamPlayer.new()
		p.stream = fire_stream
		p.volume_db = FIRE_DB
		add_child(p)
		_fire.append(p)

	_explosion = AudioStreamPlayer.new()
	_explosion.stream = load("res://sfx_explosion.mp3") as AudioStream
	_explosion.volume_db = EXPLOSION_DB
	add_child(_explosion)

	# Engine: a looping body bookended by one-shot start/stop transients.
	_eng_default = _load_loop("res://engine_loop.ogg")
	for ship_name in SHIP_LOOPS:
		var path := "res://engine_loop_%s.ogg" % ship_name.to_lower()
		var s := _load_loop(path)
		if s != null:
			_eng_streams[ship_name] = s
	_eng_loop = AudioStreamPlayer.new()
	_eng_loop.stream = _eng_default
	_eng_loop.volume_db = ENGINE_OFF_DB
	add_child(_eng_loop)

	_eng_start = AudioStreamPlayer.new()
	_eng_start.stream = load("res://engine_start.ogg") as AudioStream
	_eng_start.volume_db = ENGINE_TRANS_DB
	add_child(_eng_start)

	_eng_stop = AudioStreamPlayer.new()
	_eng_stop.stream = load("res://engine_stop.ogg") as AudioStream
	_eng_stop.volume_db = ENGINE_TRANS_DB
	add_child(_eng_stop)


# Load an OGG and flag it as looping (no-op / null if the file is missing).
func _load_loop(path: String) -> AudioStream:
	if not ResourceLoader.exists(path):
		return null
	var s := load(path) as AudioStream
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true   # seamless continuous loop
	return s


# Swap in the loop voice for the given ship (only does work when it changes).
func _select_ship_loop(ship_name: String) -> void:
	if ship_name == _eng_ship:
		return
	_eng_ship = ship_name
	var s: AudioStream = _eng_streams.get(ship_name, _eng_default)
	_eng_loop.stream = s
	if _eng_on:
		_eng_loop.play()   # restart on the new voice; volume/pitch carry over


# Engine voice, driven by the ship every frame.
#   ship_name : which hull (selects its distinct loop voice)
#   thrusting : is the player on the gas (any thrust input)?
#   intensity : 0..1 throttle (how hard) — shapes cruise volume + pitch
#   boost     : Shift held — louder, revved up higher/faster, eased in smoothly
#   pitch_mul : per-ship pitch nudge layered on top of the distinct loop
# Plays a one-shot "start" whoosh on the rising edge, a "stop" whoosh on release,
# and crossfades the continuous loop in between.
func update_engine(ship_name: String, thrusting: bool, intensity: float, boost: bool, pitch_mul: float, delta: float) -> void:
	_select_ship_loop(ship_name)
	intensity = clampf(intensity, 0.0, 1.0)

	if thrusting and not _eng_on:
		_eng_on = true
		_eng_start.pitch_scale = pitch_mul
		_eng_start.play()
		if not _eng_loop.playing:
			_eng_loop.play()
	elif not thrusting and _eng_on:
		_eng_on = false
		_eng_stop.pitch_scale = pitch_mul
		_eng_stop.play()

	# Continuous-drive clock: climbs while driving, unwinds when you ease off.
	if _eng_on:
		_eng_sustain = minf(_eng_sustain + delta, DRIVE_MAX)
	else:
		_eng_sustain = maxf(_eng_sustain - delta * DRIVE_DECAY, 0.0)
	# Pitch spools up over the first ~12s; volume ducks only across the 12..15s window.
	var spool := smoothstep(0.0, ENGINE_SPOOL_TIME, _eng_sustain)
	var duck := smoothstep(ENGINE_DUCK_START, ENGINE_DUCK_FULL, _eng_sustain)

	# Targets: silent when off; otherwise volume tracks throttle, boost adds punch.
	var target_db := ENGINE_OFF_DB
	var target_pitch := ENGINE_PITCH_IDLE
	if _eng_on:
		target_db = lerpf(ENGINE_QUIET_DB, ENGINE_LOOP_DB, intensity)
		target_pitch = lerpf(ENGINE_PITCH_IDLE, ENGINE_PITCH_FULL, intensity)
		if boost:
			target_db += ENGINE_BOOST_DB
			target_pitch = ENGINE_PITCH_BOOST   # revved up — faster, higher
		else:
			# Settled cruise: recede under the music, and spool the pitch up a touch.
			target_db -= ENGINE_SUSTAIN_DUCK * duck
			target_pitch += ENGINE_SUSTAIN_PITCH * spool
	target_pitch *= pitch_mul

	# Ease toward the targets; boost uses a gentler rate for that smooth swell.
	var rate := ENGINE_SMOOTH_BOOST if boost else ENGINE_SMOOTH
	var k := clampf(rate * delta, 0.0, 1.0)
	_eng_loop.volume_db = lerpf(_eng_loop.volume_db, target_db, k)
	_eng_loop.pitch_scale = lerpf(_eng_loop.pitch_scale, target_pitch, k)

	# Once fully faded out and idle, pause the loop to save a voice.
	if not _eng_on and _eng_loop.playing and _eng_loop.volume_db <= ENGINE_OFF_DB + 1.0:
		_eng_loop.stop()


# Seconds of continuous driving so far (0 when stopped/docked). Main reads this to
# gate the bgm fade-in; the engine reads it for the cruise spool/duck.
func drive_time() -> float:
	return _eng_sustain


# Hard-silence the engine immediately (docked / wormhole transit). Also clears the
# drive clock, so the music + cruise arc restart fresh next time you fly out.
func engine_off() -> void:
	_eng_on = false
	_eng_sustain = 0.0
	_eng_loop.volume_db = ENGINE_OFF_DB
	if _eng_loop.playing:
		_eng_loop.stop()


# A laser shot — round-robins voices so rapid shots never cut each other off.
func play_fire() -> void:
	var p := _fire[_fire_i]
	_fire_i = (_fire_i + 1) % _fire.size()
	p.pitch_scale = randf_range(0.82, 0.92)   # lower pitch reads softer/gentler
	p.play()


# Alien destroyed — the "crush" boom.
func play_explosion() -> void:
	_explosion.pitch_scale = randf_range(0.9, 1.06)
	_explosion.play()

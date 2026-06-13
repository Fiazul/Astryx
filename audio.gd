class_name GameAudio
extends Node
# Code-spawned SFX, same spirit as everything else in Astryx: rapid laser fire
# (pooled so shots overlap) and a "crush" boom on alien death.
# (Engine SFX was removed — flight is silent on the engine side now.)

const FIRE_VOICES := 8          # round-robin players so rapid shots overlap cleanly
const FIRE_DB := -19.0          # bullet fire — gentle/soft
const EXPLOSION_DB := -3.0

var _fire: Array[AudioStreamPlayer] = []
var _fire_i := 0
var _explosion: AudioStreamPlayer


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

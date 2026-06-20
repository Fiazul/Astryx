class_name MusicDirector
extends Node
# Two-track music state machine (lobby ⇄ ship), spawned by main (Phase 3 extraction from
# main.gd). Cross-fades the LOCAL / in-system "lobby" track and the INTERSTELLAR "ship" track
# with an engine-only GAP between them. Which one is "up" depends purely on game state, fed in
# each frame by main: `update(delta, interstellar, hull_name)`. Owns its two AudioStreamPlayers
# and ducks the engine (GameAudio autoload) under the ship track.

var _music: AudioStreamPlayer          # the SHIP / interstellar track
var _music_default: AudioStream        # the shared bgm every hull flies to
var _music_hani: AudioStream           # HaniNebula's dedicated theme (null if missing)
var _music_track := ""                 # which ship stream is loaded: "default" | "hani"
var _music_lobby: AudioStreamPlayer    # the LOBBY / local track (bgm_lobby.ogg)

const MUSIC_DB := -13.0    # ship-track level once faded in
const LOBBY_DB := -18.0    # lobby-track level — a comfortable backdrop the engine sits over
const MUSIC_OFF_DB := -60.0  # silent end of either fade
const MUSIC_GAP := 1.8       # engine-only silence between the two tracks (seconds)
const WANT_DWELL := 0.4      # boundary debounce before committing a track switch
const MUSIC_FADE_OUT := 0.6  # lobby-track fade-out
const SHIP_FADE_OUT := 0.6   # ship-track fade-out
const MUSIC_FADE_IN := 0.7   # incoming fade speed — slow, cinematic swell
const SHIP_ENGINE_DUCK_DB := 10.0  # dB the engine recedes once the interstellar ship music is up
# These hulls share the dedicated interstellar theme (bgm_hani.ogg); every other ship the default.
const THEMED_HULLS := ["HaniNebula", "Raptor 2 Neo", "Vela Iron Pulse", "Lyra"]

var _cur_track := "lobby"          # "lobby" | "ship"
var _xfade_phase := "fadein"       # start by swelling the lobby track in at launch
var _gap_t := 0.0                  # remaining engine-only gap (seconds)
var _want_dwell := 0.0             # how long the wanted track has differed from _cur_track


func _ready() -> void:
	# OGG Vorbis, not MP3: MP3 padding leaves an audible loop gap; Vorbis loops seamlessly.
	_music_default = _load_music("res://assets/bgm.ogg")
	if _music_default == null:
		return
	# HaniNebula gets her own dedicated interstellar theme; everyone else shares bgm.ogg.
	_music_hani = _load_music("res://assets/bgm_hani.ogg")
	_music = AudioStreamPlayer.new()
	_music.stream = _music_default
	_music_track = "default"
	_music.volume_db = MUSIC_OFF_DB
	_music.bus = "Master"
	# PROCESS_MODE_ALWAYS: keep playing through a paused tree (map / quest log / settings / codex)
	# so opening an overlay never cuts the music.
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.play()
	_music.stream_paused = true

	# Lobby / local track — same seamless-loop + always-process treatment.
	var lobby := _load_music("res://assets/bgm_lobby.ogg")
	if lobby != null:
		_music_lobby = AudioStreamPlayer.new()
		_music_lobby.stream = lobby
		_music_lobby.volume_db = MUSIC_OFF_DB
		_music_lobby.bus = "Master"
		_music_lobby.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_music_lobby)
		_music_lobby.play()
		# You start LOCAL (in-system) → the state machine swells the lobby track in.
		_music_lobby.stream_paused = false


# Driven from main._process. interstellar = is the ship out in open/FTL space; hull_name = the
# equipped hull (decides the ship theme). Cross-fades with an engine-only gap at the boundary.
func update(delta: float, interstellar: bool, hull_name: String) -> void:
	if _music == null or _music_lobby == null:
		return
	# Keep the ship track on the equipped hull's stream, but only swap while it's silent so the
	# change is never an audible cut (HaniNebula flies to her own theme, others share bgm).
	var track := _desired_track(hull_name)
	if track != _music_track \
		and (_music.stream_paused or _music.volume_db <= MUSIC_OFF_DB + 1.0):
		_music_track = track
		_music.stream = _music_hani if track == "hani" else _music_default

	var want := "ship" if interstellar else "lobby"
	# Debounce the zone boundary: the interstellar flag can flicker right at a zone edge, so only
	# treat a differing want as real once it has persisted for WANT_DWELL.
	if want != _cur_track:
		_want_dwell += delta
	else:
		_want_dwell = 0.0

	match _xfade_phase:
		"steady":
			_fade_track(_cur_track, _target_db_for(_cur_track), MUSIC_FADE_IN, delta)
			if want != _cur_track and _want_dwell >= WANT_DWELL:
				_xfade_phase = "fadeout"
		"fadeout":
			# If the player ducked back before we finished, just swell the current track again.
			if want == _cur_track:
				_xfade_phase = "fadein"
			else:
				var out_rate := SHIP_FADE_OUT if _cur_track == "ship" else MUSIC_FADE_OUT
				_fade_track(_cur_track, MUSIC_OFF_DB, out_rate, delta)
				if _player_for(_cur_track).volume_db <= MUSIC_OFF_DB + 1.0:
					_player_for(_cur_track).stream_paused = true
					_gap_t = MUSIC_GAP
					_xfade_phase = "gap"
		"gap":
			# Both tracks silent — only the engine is heard across this brief window.
			_gap_t -= delta
			if _gap_t <= 0.0:
				_cur_track = want   # commit to whatever's wanted now (handles a flip mid-gap)
				_ready_track(_cur_track)
				_xfade_phase = "fadein"
		"fadein":
			if want != _cur_track and _want_dwell >= WANT_DWELL:
				_xfade_phase = "fadeout"
			else:
				_fade_track(_cur_track, _target_db_for(_cur_track), MUSIC_FADE_IN, delta)
				if _player_for(_cur_track).volume_db >= _target_db_for(_cur_track) - 0.5:
					_xfade_phase = "steady"

	# Duck the engine under the interstellar ship music, scaled by how present that track is
	# (0 when silent — incl. the engine-only gap — full once it's faded in).
	var ship_presence := clampf(inverse_lerp(MUSIC_OFF_DB, MUSIC_DB, _music.volume_db), 0.0, 1.0)
	GameAudio.set_engine_duck(SHIP_ENGINE_DUCK_DB * ship_presence)


# Which bgm the equipped hull should fly to (falls back to default if the hani track is missing).
func _desired_track(hull_name: String) -> String:
	return "hani" if (_music_hani != null and hull_name in THEMED_HULLS) else "default"


func _player_for(track: String) -> AudioStreamPlayer:
	return _music if track == "ship" else _music_lobby


func _target_db_for(track: String) -> float:
	return MUSIC_DB if track == "ship" else LOBBY_DB


# Unpause/restart a track from silence so it can fade in cleanly.
func _ready_track(track: String) -> void:
	var p := _player_for(track)
	p.volume_db = MUSIC_OFF_DB
	if not p.playing:
		p.play()
	p.stream_paused = false


# Ease a track's volume toward a target; unpause it if it needs to be heard.
func _fade_track(track: String, target_db: float, rate: float, delta: float) -> void:
	var p := _player_for(track)
	if target_db > MUSIC_OFF_DB and p.stream_paused:
		p.stream_paused = false
		if not p.playing:
			p.play()
	p.volume_db = lerpf(p.volume_db, target_db, clampf(rate * delta, 0.0, 1.0))


# Load a bgm track and flag it as a seamless loop (null if the file is missing).
func _load_music(path: String) -> AudioStream:
	var stream := load(path)
	if stream == null:
		return null
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true   # seamless loop, no gap
	return stream

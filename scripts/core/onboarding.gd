class_name Onboarding
extends Node
# The GETTING STARTED beginner quest — a tiny staged guide that teaches the core loop using
# actions the player already performs (Phase 3 extraction from main.gd). Each step shows one tip;
# doing the thing advances to the next; past the last it never shows again. Persisted progress
# lives in the GameState autoload (onboarding_step / onboarding_done); this owns the step list +
# the per-frame update loop. Holds a `main` ref for the game context it observes (combat / ship /
# hud) and for persistence.

var main   # set by main right after construction

var _ob_done_toast := false   # so the "quest complete" toast fires only once
var _ob_kills_base := 0       # combat.kills snapshot when (re)started → "clear swarm"
var _ob_boss_base := 0        # guardian-bosses-beaten snapshot when (re)started → "beat a guardian"
var _map_seen := false        # latched when the star map is first opened
var _log_seen := false        # latched when the mission log is first opened

# Order: core loop → travel → combat. Surfaced as the pinned top quest in the J log + on-screen tip.
var _onboard := [
	{ "id": "thrust", "title": "Take the helm",
		"tip": "Hold  W  to thrust  ·  steer with the mouse, A/D strafe, Space/Ctrl up·down" },
	{ "id": "scan", "title": "Scan a world",
		"tip": "Aim at a planet or star and hold  V  to survey it" },
	{ "id": "claim", "title": "Claim your coins",
		"tip": "Press  G  to claim your reward coins" },
	{ "id": "map", "title": "Read the star map",
		"tip": "Press  M  for the Star Map — the wormhole network · pick a star, Navigate" },
	{ "id": "log", "title": "Open the mission log",
		"tip": "Press  J  for the MISSION LOG — every star, planet & moon is a mission" },
	{ "id": "wormhole", "title": "Ride a wormhole",
		"tip": "Fly into a glowing  wormhole  and press  F  — it links to a neighbouring star" },
	{ "id": "dock", "title": "Dock at a station",
		"tip": "Approach a platform/station and press  F  to dock (swap & customise ships)" },
	{ "id": "teleport_net", "title": "Use the teleport network",
		"tip": "While docked, open the  TELEPORT NETWORK  (bottom-centre) to fast-travel" },
	{ "id": "fire", "title": "Open fire",
		"tip": "Left-click to fire — line a hostile up in the crosshair" },
	{ "id": "swarm", "title": "Clear the hostiles",
		"tip": "Destroy enemy ships — thin out a swarm (3 kills)" },
	{ "id": "boss", "title": "Beat a guardian",
		"tip": "A guarded world's boss is SHIELDED until its swarm is dead — clear them, then beat the boss to capture the world" },
]


# Spawned after the profile is loaded (GameState is populated by then): if the quest was already
# finished, pre-arm the toast latch so the "complete" toast doesn't re-fire on boot.
func _ready() -> void:
	_ob_done_toast = GameState.onboarding_done.has("boss")


# Called by StarMap when the map is first opened (the map pauses the tree, so main._process
# can't observe map._open itself — the map notifies us instead).
func notify_map_opened() -> void:
	_map_seen = true
	note("map")

# Latched by QuestLog the first time the mission log is opened (drives the final onboarding tip).
func notify_log_opened() -> void:
	_log_seen = true
	note("log")


# Latch a beginner-quest step done (event-driven, so a restart can re-arm each one).
func note(id: String) -> void:
	GameState.onboarding_done[id] = true


# Restart the GETTING STARTED quest from step 1 — re-arms every step (counters re-baseline).
func restart() -> void:
	GameState.onboarding_done.clear()
	GameState.onboarding_step = 0
	_ob_done_toast = false
	_ob_kills_base = main.combat.kills
	_ob_boss_base = main.combat.guardian_bosses_beaten
	main._save_profile()
	main.hud.toast = "✦  GETTING STARTED — quest restarted."
	main.hud.toast_t = 2.5


# Snapshot for the J-log questline: each step's title/tip/done plus the current index.
func state() -> Dictionary:
	var steps := []
	for i in _onboard.size():
		var s = _onboard[i]
		steps.append({ "title": s.title, "tip": s.tip,
			"done": GameState.onboarding_done.get(s.id, false), "current": i == GameState.onboarding_step })
	return { "steps": steps, "step": GameState.onboarding_step, "total": _onboard.size(),
		"complete": GameState.onboarding_step >= _onboard.size() }


# The id of the step currently being asked of the player ("" once complete). Read by main's
# objective arrow so the final "ride a wormhole" step can point straight at the gate.
func current_step_id() -> String:
	if GameState.onboarding_step < _onboard.size():
		return _onboard[GameState.onboarding_step].id
	return ""


# Driven from main._process: latch action-counted steps, advance past completed ones, show the tip.
func update() -> void:
	var ship = main.ship
	var combat = main.combat
	var hud = main.hud
	if ship.transiting:
		hud.set_tip("")
		return
	# Live latches for the action-counted steps (re-armed on restart via the baselines).
	if ship.velocity.length() > 30.0:
		note("thrust")
	if combat.kills - _ob_kills_base >= 3:
		note("swarm")
	if combat.guardian_bosses_beaten - _ob_boss_base >= 1:
		note("boss")
	# Advance past every completed step (persist as it moves).
	var advanced := false
	while GameState.onboarding_step < _onboard.size() and GameState.onboarding_done.get(_onboard[GameState.onboarding_step].id, false):
		GameState.onboarding_step += 1
		advanced = true
	if advanced:
		main._save_profile()
	if GameState.onboarding_step >= _onboard.size():
		if not _ob_done_toast:
			_ob_done_toast = true
			hud.toast = "✦  GETTING STARTED complete. The dark is yours to chart, pilot."
			hud.toast_t = 4.0
		hud.set_tip("")
		return
	hud.set_tip("◈  GETTING STARTED  ·  " + _onboard[GameState.onboarding_step].tip)

# Autoload singleton (registered as `GameState` in project.godot).
# The player's persisted profile + economy. Phase 2 of the restructure (ADR-0001) extracts
# this state out of main.gd one cohesive slice at a time.
#
# Persistence note: main._save_profile / _load_profile stay the SINGLE writer of profile.cfg
# and read/write these fields, until the final Phase 2 slice moves persistence into
# GameState.save()/load(). One writer avoids profile-clobber during the transition.
extends Node

# --- Economy (Phase 2a) ---
var coins := 0                 # player currency
var claimed := {}              # body name -> true once its capture reward is claimed

# --- Discovery / navigation (Phase 2b) ---
var visited := {}              # system id -> true once reached (= DISCOVERED → free fast-travel)
var nav_unlocked := {}         # star id -> true: navigation unlocked (paid / chest-dropped)
var wormholes_found := {}      # star id -> true: this star's wormhole found by radar in the hub

# --- Onboarding progress (Phase 2c) — persisted; the UPDATE loop stays in main ---
var onboarding_step := 0       # first-run guided tips: which step the player is on
var onboarding_done := {}      # set of completed beginner-quest step ids (event-latched)

const CAPTURE_REWARD := 100
const ARRIVAL_REWARD := 150    # coins granted the FIRST time you reach a new system
const NAV_COST := 40           # coins to buy a navigator (map Navigate / Auto-pilot)
const NAV_UNLOCK_BASE := 80    # base coin cost to unlock navigation to a LOCKED star…
const NAV_UNLOCK_PER_LY := 9   # …plus this per light-year of real distance (far = pricey)

func add_coins(n: int) -> void:
	coins += n

# Claimable = captured (discovered) but not yet claimed.
func can_claim(body_name: String) -> bool:
	return Codex.is_discovered(body_name) and not claimed.has(body_name)

# Pure economy: grant the per-mission bounty once. Returns the bounty (0 if not claimable).
# main wraps this to add the onboarding note + persistence.
func claim_reward(body_name: String) -> int:
	if not can_claim(body_name):
		return 0
	var bounty := MissionDB.reward(body_name)
	coins += bounty
	claimed[body_name] = true
	return bounty

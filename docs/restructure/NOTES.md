# Astryx Restructure — Living Notes

> Working log for the codebase modularization. Started 2026-06-20 (on the restored full
> v0.11.5 working tree, base commit `d07f23e`). Updated as decisions land. Decisions that are
> hard to reverse graduate into `docs/adr/`. This file is the scratch/everything log.

## Why we're doing this (the actual pain)

Stated by the owner, verbatim intent:
- `main.gd` is **too big** (2093 lines) — a god-object orchestrator.
- Several files are **too large to work with** — even for an AI agent:
  `main.gd` 2093 · `ship.gd` 1626 · `hud.gd` 1449 · `combat.gd` 1352.
- File **names are inconsistent / weird**.
- Goal: **super easy to scale and for people (and Claude) to contribute.**

## Goal (locked)

- **Unit of contribution = BOTH**, equally:
  1. **Content** — adding ships / star systems / planets / missions / codex facts should be a
     drop-in, data-driven act.
  2. **Features** — adding whole subsystems should have clear module boundaries to slot into.
- Therefore: a **content/data layer** (registries, drop-in) **and** a **decoupled systems
  layer** (no god-object).

## Decisions locked

| # | Decision | Notes |
|---|----------|-------|
| D1 | **Target paradigm = code-spawned + autoloads** | Keep building the world from code (project identity). Promote global services/DBs (`SystemDB`, `MissionDB`, `PlanetData`, `GameAudio`, `Codex`, `Ephemeris`) to Godot **autoload singletons** so any module reaches them without `main.gd` plumbing. NOT going full scene-idiomatic (too risky for a working game). NOT staying pure hand-wired (keeps the manual-wiring pain). |
| D2 | **Approach = incremental + parse-check** | Tiny steps, commit after each, verify with `godot --headless --check-only` + agent spot-read. Owner playtests at milestones. No automated smoke/behavior test (accepted risk). Game must stay runnable & have a safe stopping point at every step. |
| D3 | **Folder layout = by domain/feature** | `scripts/{core,autoload,flight,world,travel,combat,ui}/`. autoload/ holds the global services/DBs (D1). `game_state.gd` to be extracted from main.gd into core/. Safe to move (class_name = no import-path breakage). |
| D4 | **Naming = file = snake_case(class_name)** | Rename FILES to match their class; classes untouched (low risk). Mismatches to fix: `systems.gd→system_db.gd`, `missions.gd→mission_db.gd`, `map.gd→star_map.gd`, `audio.gd→game_audio.gd`, `settings.gd→settings_menu.gd`, `minimap.gd→mini_map.gd`, `touch.gd→touch_controls.gd`. `props.gd` kept. ~20 others already match. |
| D5 | **Split rule = responsibility seams (deep modules)** | Extract a concern only where it has a narrow interface. Line count is a smell to investigate, not a hard cap. No mechanical "chop at N lines." |

## CRITICAL: path-based refs that do NOT follow class_name (must hand-fix on move)

- `main.gd:396` — `load("res://scripts/touch.gd").new()` → update to new path (`flight/touch_controls.gd`).
- `hud.gd:260` — `load("res://scripts/crosshair.gd").new()` → update to new path (`ui/crosshair.gd`).
- `scenes/Main.tscn` — `ext_resource path="res://scripts/main.gd"` (uid-backed `uid://cuawipd10uicq`;
  self-heals when the editor reopens, but update the path string anyway).
- **Every `.gd` has a sibling `.gd.uid`** — `git mv` BOTH together or Godot regenerates UIDs and
  breaks `.tscn` links. Open the editor once after moves to let it reimport/heal paths.
- `hud.gd:27` loads `res://shaders/hud_text.gdshader` (shader, unaffected — there's a `shaders/` dir).
- All static DB calls already global: `SystemDB.portals()`, `MissionDB.reward()` are STATIC — those
  classes may NOT need autoloading at all (just stop instantiating). True autoload candidates are the
  STATEFUL nodes currently `.new()`'d + ref-passed: `Ephemeris`, `GameAudio`, `Codex`, `PlanetData`,
  `PlanetInfo`. (Per-module check needed in Phase 1.)

## Orphan / cleanup found

- `./Main.tscn` (repo root) = **stale orphan**: scriptless Node3D, uid `uid://84k2rihwnbwf`, NOT the
  boot scene (project boots `res://scenes/Main.tscn`). Delete in Phase 0 (git-recoverable).

## Proposed phase order (incremental, each = own commit + parse-check + playtest)

- **Phase 0 — Mechanical reorg (near-zero risk):** make `scripts/{core,autoload,flight,world,travel,combat,ui}/`;
  `git mv` each `.gd` + its `.uid` into place with D4 renames; fix the 2 `load()` paths + Main.tscn path;
  delete orphan root `Main.tscn`. Open editor once → playtest → commit. *Immediate navigability win.*
- **Phase 1 — Autoloads:** register stateful services as autoloads; delete their `.new()/add_child` +
  ref-passing from `main.gd`; switch call sites to the singleton. (Medium risk — init order matters.)
- **Phase 2 — Extract `GameState`** from `main.gd` (coins/claimed/visited/nav_unlocked + profile save/load).
- **Phase 3 — Decompose the big-4 by responsibility seams**, one file per commit, biggest pain first
  (`main.gd` → travel-controller + onboarding; `combat.gd` → waves/boss/bullets; `hud.gd` → panel groups;
  `ship.gd` → flight vs visuals). Playtest each.

## Naming inconsistencies found (the "weird names")

File name ≠ class it holds — fixable:
- `systems.gd` → `class SystemDB`
- `map.gd` → `class StarMap`
- `missions.gd` → `class MissionDB`
- `audio.gd` → `class GameAudio`
- `tutor.gd` → `class Tutor`
- `props.gd` → vague ("props" = stations/platforms/probes)

## Current architecture (facts, from code)

- **29 scripts**, flat in `scripts/`, no sub-folders. 13.6k lines total.
- **Every module has a global `class_name`** → modules find each other by type, NO `preload`
  path deps → **moving files between folders will NOT break imports.** (Big enabler.)
- **Almost no signals** (6 signals / 6 emits in 13.6k lines). Wiring is **direct method calls
  on held references**, not events.
- **`main.gd` is the spider**: holds refs to ship/hud/combat/planets/wormhole/codex/audio,
  owns game state (coins, claimed, visited, nav-unlocked…), and runs the loop. Inside
  `main.gd`: 151 `ship.` calls, 117 `hud.` calls, 38 `combat.`, 33 `planets.`.

## Open questions (the grilling queue)

- Q-A: Approach — **incremental & always-running** vs big-bang? (recommend incremental)
- Q-B: **Naming convention** — what scheme fixes the "weird names"?
- Q-C: **Folder taxonomy** — how do we group the 29+ files?
- Q-D: **Decomposition principle** — how do we split main.gd / ship.gd / hud.gd / combat.gd?
- Q-E: **Ordering** — what's the safe sequence (autoloads first? split main.gd first?).
- Q-F: **Verification** — how do we prove we didn't break the game at each step?

## Phase 0 execution log (DONE 2026-06-20, branch `restructure`)

- Moved all 29 `.gd` **+ their `.gd.uid`** into `core/autoload/flight/world/travel/combat/ui/`
  with the D4 renames. Fixed the 2 `load()` paths (`main.gd`, `hud.gd`), `scenes/Main.tscn`
  script path, and `BUILD-ANDROID.md` prose path. Deleted orphan root `Main.tscn`.
- **GOTCHA (important for any future file move):** Godot caches the global class→path map in
  `.godot/global_script_class_cache.cfg`. After moving files it's STALE → `--check-only` floods
  "Class X hides a global script class" / "Could not find script for class Y". **Fix: run
  `godot --headless --import` once** to rebuild the registry (or open the editor). Not a real error.
- After rebuild: **28/29 scripts parse clean.** The 1 residual (`touch_controls.gd`:
  "Cannot infer the type of 'hit'") is **pre-existing** (present in baseline `touch.gd`) and only
  an isolated-`--check-only` artifact — `_button_at()` has no declared return type. Whole-project
  import accepts it. **Candidate trivial cleanup later:** annotate `_button_at()`'s return type.

## Phase 1 execution log (IN PROGRESS, branch `restructure`)

- **GameAudio ✅ DONE** (pilot). Registered `[autoload] GameAudio="*res://scripts/autoload/game_audio.gd"`;
  dropped `class_name GameAudio`; consumers (`ship`, `combat`, `tutor`, `main`) now self-source via
  `@onready var audio := GameAudio` instead of main-injection. Removed main's `.new()/add_child` +
  `ship.audio=`/`combat.audio=`/`tutor.audio=` wiring. **All ~25 `audio.x()` call sites unchanged**
  (alias kept) → near-zero behavior risk. `main.audio` external accessors (quest_log/planet_info/
  star_map) still work because main keeps `audio` as an alias to the autoload.
- **VERIFICATION METHOD CHANGED:** once an autoload exists, `godot --headless --check-only --script X`
  gives FALSE "Identifier not found: GameAudio" — isolated compile has no autoload globals. **Use a
  headless boot instead:** `timeout 30 godot --headless --quit-after 120` and grep for
  `SCRIPT ERROR|Compile Error|Failed to load`. GameAudio passed (clean boot, exit 0).
- **Codex / PlanetData / Ephemeris ✅ DONE** (same pattern). Registered all in `[autoload]`; dropped
  their `class_name`; consumers self-source (`@onready var codex := Codex`, etc.); removed main's
  `.new()/add_child` + every injection (`hud.codex=`, `planet_info.data=`/`.codex=`, `codex_panel.codex=`,
  `quest_log.codex=`, `planets.eph=`). No `is/as` or type-annotation uses of the dropped names existed.
- **Phase 1 COMPLETE.** 4 autoloads: `Ephemeris`, `PlanetData`, `Codex`, `GameAudio`. `SystemDB`/
  `MissionDB` left as-is (already global static classes — no autoload needed). `main.gd` 2093 → 2079.
  Verified by clean headless boot (exit 0, no script errors). **Owner playtest pending before Phase 2.**
- Future cleanup (low priority): the kept `audio`/`eph`/`codex`/`data` aliases could migrate to direct
  `GameAudio.x()` / `Ephemeris.x()` global calls; redundant `if audio != null` guards can go.

## Phase 2 — extract GameState (autoload), INCREMENTAL slices

Decision: GameState is an **autoload**. Bite size = **incremental slices** (safer; only boot +
manual playtest as checks). **Refinement:** persistence stays the SINGLE writer in
main._save_profile/_load_profile (reading/writing GameState fields) until the FINAL slice, when
it moves into GameState.save()/load() — avoids profile.cfg clobber mid-transition.

- **2a ✅ DONE** (`2185434`) — economy: `coins`, `claimed` + consts (CAPTURE/ARRIVAL_REWARD,
  NAV_COST, NAV_UNLOCK_*) + pure `can_claim`/`claim_reward`/`add_coins` → GameState. main keeps thin
  `can_claim`/`claim_reward` wrappers (onboarding note + save side-effects). External callers untouched.
  Clean boot; completeness grep clean. NOTE: `CAPTURE_REWARD` is defined-but-unused (was already
  unused in main) — leave for now.
- **2b ✅ DONE** (`<next>`) — `visited`/`nav_unlocked`/`wormholes_found` dicts → GameState. main's
  query/mutation methods (`is_visited`, `star_state`, `unlock_nav`, `grant_nav_location`,
  `is_teleport_unlocked`) kept in main, now reading `GameState.visited` etc. No external refs to the
  vars; external method callers (star_map/map_chart/quest_log/platform_teleport) untouched. Clean boot.
  **LESSON:** `replace_all` is literal substring, NOT word-boundary — `_visited` is a substring of
  `is_visited`, so the bulk rename mangled `func is_visited` → `func isGameState.visited` (caught +
  fixed). Always grep for `[a-zA-Z]GameState\.` after a token replace_all.
- **2c ✅ DONE** — persisted onboarding fields (`onboarding_step`, `_ob`→`onboarding_done`) → GameState.
  Transient controller vars (`_ob_done_toast`, `_ob_kills_base/_boss_base`, `_onboard` steps array,
  `_fresh_game`, `_map_seen`) stay in main. Used `_ob.` / `_ob[` scoped replaces to dodge the `_ob_*`
  substring trap.
- **2d ✅ DONE** — `_loaded_custom`→`GameState.customization`; persistence consolidated: GameState owns
  `load_from(cfg)`/`save_into(cfg)`/`reset()`, main keeps the ConfigFile orchestration + its session keys
  (active_quest, system, pos, ship_index). **CATCH:** autoloads SURVIVE `reload_current_scene()`, so
  `reset_progress`/no-save now calls `GameState.reset()` to clear stale in-memory state (the old code
  relied on main being recreated). Clean boot.
- **PHASE 2 COMPLETE.** GameState autoload owns all persisted profile state. main.gd 2079 → 2049.
  Reminder: state-extraction gives small line savings; **Phase 3 (decompose by responsibility seam)** is
  the real main.gd/file-size relief.
- **Playtest checklist (2c/2d):** ship customization persists across restart; onboarding/beginner-quest
  progress persists & doesn't re-trigger; **Reset Progress** (Settings) truly wipes coins/visited/codex
  (the autoload-reset path); plus the 2a coin checks.
- **Playtest checklist for 2a:** claim a capture reward (G panel), buy a navigator / chart a lane
  (coin spend), arrive at a NEW system (+150 bonus), and confirm **coins persist across a restart**
  (the save/load path now round-trips through GameState).

## Phase 3 — decompose big files by responsibility seam (the real size relief)

Order: pilot with the cleanest self-contained seam, then bigger ones. Verify each by headless boot.

- **3a ✅ DONE — MusicDirector** (`<next>`). Lifted the two-track lobby⇄ship music state machine out of
  main.gd into `core/music_director.gd` (163 lines, `class_name MusicDirector`, spawned by main).
  Narrow interface: `update(delta, interstellar, hull_name)`; main keeps `_is_interstellar()` and calls
  it each frame. Director ducks the engine via the GameAudio autoload directly. **main.gd 2049 → 1878
  (−171 lines)** — the first real size win (Phase 1+2 barely moved it). Clean boot.
  - Folder note: put in `core/` (spawned by main). Audio is now split `autoload/game_audio` (SFX) +
    `core/music_director` (music) — could justify a future `scripts/audio/` grouping.
- **Candidate next seams** (from the main.gd map): Nav/Tab-targeting controller (~400 lines, higher
  coupling), onboarding controller (~80 lines, state already in GameState), teleport ritual. Plus the
  other big files: ship.gd (1626), hud.gd (1449), combat.gd (1352).
- **Playtest (3a):** music still cross-fades lobby⇄ship when flying out to open space / back; HaniNebula
  & Raptor 2 Neo still get the dedicated theme; engine ducks under the ship track.

## ⚠ KNOWN ISSUES / regressions to investigate (do NOT lose these)

- **"Buying navigation option seems missing"** (reported by owner after 2a playtest, 2026-06-20).
  The buy/chart-a-lane nav option appears absent. **SUSPECT: possibly introduced by Phase 2a** —
  2a edited the exact nav-economy path (`nav_cost`, `unlock_nav`, `buy_navigator` now read
  `GameState.coins`/`GameState.NAV_*`). Could also be pre-existing (the restored v0.11.5 baseline
  was WIP).
  - **Where to look:** the "CHART LANE — %d coins" button in `ui/star_map.gd` (~line 345, calls
    `main.nav_cost(sys)`); the button only shows when `main.star_state(id) == "locked"`
    (`core/main.gd`), which depends on `_nav_unlocked` / `is_visited` / wormhole-found state.
    Also `main.buy_navigator()` (map Navigate / autopilot) and `start_autopilot`.
  - **Bisect:** compare against `407e32c` (pre-2a) — `git stash` then
    `git checkout 407e32c` and see if the option is present there. If yes → 2a caused it; if no →
    pre-existing in the v0.11.5 baseline.
  - **Status:** deferred per owner ("keep a note and move on"). Verify before merging `restructure`.

## Confusions / things to flag (owner asked me to surface these)

- `CLAUDE.FILE` at repo root — unusual name; purpose unknown. (low priority)
- Both `.claude/skills/` and `.agents/skills/` carry a `think-before-building` copy —
  duplication, probably harness scaffolding, not game. (low priority)
- Need to confirm `scenes/` folder contents (only `Main.tscn` referenced so far).

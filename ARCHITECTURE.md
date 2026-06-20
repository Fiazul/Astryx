# Astryx — Architecture & Module Map

> What every file does, at a glance. The game is **code-spawned**: `scenes/Main.tscn` is a
> one-node stub; `core/main.gd` builds the whole world at runtime. See
> [`docs/adr/0001`](docs/adr/0001-modular-code-spawned-plus-autoloads.md) for the why, and
> [`docs/restructure/NOTES.md`](docs/restructure/NOTES.md) for the in-progress modularization.

## How it fits together

`core/main.gd` is the orchestrator: in `_ready()` it `.new()`s + `add_child`s every subsystem and
drives them each frame in `_process()`. Globally-shared services are **autoloads** (reachable from
any module by name, no wiring): `GameState`, `Ephemeris`, `Codex`, `PlanetData`, `GameAudio`, plus
the static `SystemDB` / `MissionDB` data classes.

## Folders

### `core/` — orchestration & cross-cutting state
| File | Responsibility |
|---|---|
| `main.gd` | Orchestrator: spawns the world, owns the game loop, input, travel/teleport, nav-targeting |
| `game_state.gd` | **Autoload.** The persisted player profile + economy (coins, claimed, visited, nav, onboarding, customization) + `load_from`/`save_into`/`reset` |
| `music_director.gd` | Two-track lobby⇄ship music state machine; `update(delta, interstellar, hull)` |
| `onboarding.gd` | The GETTING STARTED beginner quest (step list + advance loop); progress persists in `GameState` |

### `autoload/` — globally-reachable services & data
| File | Responsibility |
|---|---|
| `ephemeris.gd` | **Autoload.** Real Sun/planet positions (live JPL Horizons + cache), floating-origin |
| `codex.gd` | **Autoload.** Which bodies the player has scanned/discovered (persisted) |
| `planet_data.gd` | **Autoload.** Real planet fact-sheets for the Details panel |
| `system_db.gd` | Static `SystemDB`: the ~50 real star systems, portals, coords |
| `mission_db.gd` | Static `MissionDB`: per-body missions (title/story/bounty) |
| `game_audio.gd` | **Autoload.** Code-generated SFX + the per-ship engine voice |

### `flight/` — the ship
| File | Responsibility |
|---|---|
| `ship.gd` | Flight physics, visuals (boosters/streaks), warp, autopilot, customization |
| `ship_mesh.gd` | Mesh/material build helpers for the hulls |
| `touch_controls.gd` | Mobile touch-control overlay (`--touch` to test on desktop) |

### `world/` — the space around you
| File | Responsibility |
|---|---|
| `planet_system.gd` | Real bodies as dot→LOD, gravity wells, floating-origin |
| `starfield.gd` | Baked real-catalogue star backdrop |
| `galaxy_model.gd` | Milky Way backdrop + the Sgr A* core jump |
| `props.gd` | Stations, platforms, drifting landmarks |

### `travel/` — getting around
| File | Responsibility |
|---|---|
| `wormhole.gd` | The portal graph (MST + BFS routing) + the transit sequence |
| `navigator.gd` | On-screen nav markers + the always-on arrow to the nearest objective |
| `platform_teleport.gd` | The docked fast-travel console between unlocked stations |

### `combat/`
| File | Responsibility |
|---|---|
| `combat.gd` | Dogfight: hitscan bolts, alien AI, named bosses, finite guardian waves |
| `combat_fx.gd` | `CombatFX`: transient combat visuals (booms/sparks/flashes) + bolt/flash materials |
| `enemy_factory.gd` | `EnemyFactory`: loads/normalizes/paints the monster GLBs + packs each into a unit dict |

### `ui/`
| File | Responsibility |
|---|---|
| `hud.gd` | The main HUD (readouts, tip/quest banners, layout editor) |
| `mini_map.gd` | Corner radar (ship-relative blips) |
| `crosshair.gd` | The aiming reticle |
| `star_map.gd` | The zoomable star map (M) |
| `map_chart.gd` | Star-map drawing/projection |
| `settings_menu.gd` | Settings overlay (audio, reset progress…) |
| `codex_panel.gd` | The Codex logbook (L) |
| `planet_info.gd` | The Details panel (G) |
| `quest_log.gd` | The Mission Log (J) |
| `reward_card.gd` | The capture-celebration payout card |
| `tutor.gd` | Small non-blocking tip notifications |

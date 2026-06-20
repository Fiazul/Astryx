# Modularize via domain folders + autoloads, incrementally

**Status:** accepted · 2026-06-20

Astryx grew into 29 flat `scripts/*.gd` files wired by a 2093-line `main.gd` god-object that
hand-`.new()`s every subsystem and drives them by direct method calls (151 `ship.` / 117 `hud.`
calls in `main.gd` alone; only 6 signals in 13.6k lines). To make the project scalable and
contributor-friendly (both **content** — ships/systems/missions — and **features** — new
subsystems), we will reorganize it **without** abandoning its defining trait: the world is
spawned from code, not composed in the Godot scene editor.

## Decision

1. **Keep the code-spawned paradigm.** `main.gd` still builds the world at runtime. We do **not**
   convert subsystems to `.tscn` scenes.
2. **Promote stateful global services to Godot autoloads** (`Ephemeris`, `Codex`, `PlanetData`,
   `GameAudio`, plus the static `SystemDB` / `MissionDB` data classes) so any module reaches them
   without `main.gd` plumbing or ref-passing. This is the one idiomatic concession we adopt.
3. **Group files by domain/feature**: `scripts/{core,autoload,flight,world,travel,combat,ui}/`.
   Safe because every module declares a global `class_name` — moving files does not break
   type references (the few path-based `load()`s and the boot scene's script path are the
   only hand-fixes).
4. **Name files `snake_case(class_name)`** to end the file/class mismatches.
5. **Split god-files only along responsibility seams** (deep modules with narrow interfaces),
   not by a mechanical line budget.
6. **Execute incrementally** — tiny steps, `godot --headless --check-only` after each, owner
   playtests at milestones; the game stays runnable with a safe stopping point throughout.

## Considered options

- **Stay pure code-spawned, no autoloads** — `main.gd` splits into hand-wired sub-orchestrators
  that keep passing refs. Rejected: preserves the manual-wiring pain we're trying to kill.
- **Go scene-idiomatic** — convert subsystems to `.tscn` + autoloads, compose in the editor.
  Most contributor-familiar, but a large, risky rewrite of a working 13.6k-line game and a break
  from the project's code-spawned identity. Rejected for risk.

## Consequences

- Autoload init order becomes load-bearing (Phase 1 must verify nothing reads a service before
  it's ready). Today `main.gd` controls that order explicitly; autoloads move it to project config.
- `scripts/autoload/` mixes true Godot autoloads (stateful nodes) with static `class_name` data
  classes (`SystemDB`, `MissionDB`) that need no registration — the folder means "globally
  reachable services & data," not strictly "registered autoloads."
- Big-file decomposition (Phase 3) is deferred and per-file; the plan is reversible at every phase.

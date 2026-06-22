# Astryx — Experiment Handoff: SCALE & AWE

> Branch: `experiment/scale-and-awe` · forked from `main` @ v0.11.5.
> **Experimental — not merged.** This is the in-progress "blow the scale up so the
> world overwhelms you" pass. Pick-up doc for the next session.
> Project: `/home/fiazul/Desktop/Astryx` · Godot 4.6.2 / GDScript.

## The vision (what this branch is for)
Right now you open looking at an Earth that reads as a *model* — small enough to take
in at a glance. The goal of this pass is **awe**: you should open floating just off a
**giant** Earth that fills the view, like looking down from a station, the rest of the
system spread out huge around you. Scale first, polish after.

## What's done so far (this commit)
All in `scripts/autoload/ephemeris.gd` + `scripts/core/main.gd`, tagged `AWE PASS` in
the code comments so they're easy to find / revert:

- **Earth blown up 30×** — `radius` 5.6 → **170**. It now dominates the opening view.
- **Moon scaled with Earth (30×)** — `radius` 1.6 → **48**, `orbit_r` 16 → **480**, so
  it still clears the much larger Earth instead of being swallowed.
- **Start position pushed out** — `START_POS` moved to ~**240u** out (≈1.4× Earth's new
  170u radius), **same look-direction** as before, so you open floating just off the
  giant Earth.

## ⚠️ Known artifact (the reason this is still experimental)
The rest of Sol is **still at the old scale**. The Sun sits only ~130u from origin, which
is now **inside** Earth's 170u radius — so at the open you're looking *away* from the Sun
and it's hidden. This is expected and temporary.

## ⭐ NEXT PLAN (to finish the pass)
1. **Spread Sol out to match.** Rescale `AU_TO_UNITS` (the Sol-step scale in
   `ephemeris.gd`) so planet *positions* grow with the new body sizes — push the Sun and
   the other planets far enough out that the Sun clears Earth's 170u radius and reads as a
   distant bright disc again.
2. **Decide: scale every body 30×, or just Earth?** Earth is 30× but Mercury/Venus/etc.
   are still old-scale. Either bring them up to match (consistent giant-world feel) or
   keep Earth as a deliberate hero body — make the call and apply consistently.
3. **Re-tune gravity / slow-zones / orbit radii** for the new distances (`planet_system.gd`
   zone radii, `MOONS.orbit_r` for the other moons, star-gravity reach).
4. **Re-check travel/warp timing** — bigger distances may change how long in-system hops
   feel; verify `UNITS_PER_LY` and per-hull warp still read well.
5. **Get a screenshot.** This is a purely visual pass — confirm the "awe" actually lands
   on a real GPU before declaring done (see workflow below).

## Verification workflow (assistant can't see a live GPU)
- **Parse check on a COPY** (never `--import` the real tree):
  `cp -r . /tmp/c && rm -rf /tmp/c/.godot && godot --headless --path /tmp/c --import`,
  then grep stderr for errors.
- **Run:** `DISPLAY=:1 /home/fiazul/Desktop/Godot_v4.6.2-stable_linux.x86_64 --path /home/fiazul/Desktop/Astryx`.
- Visual changes need the user's eyes — screenshot before calling it done.

## To revert / abandon
All changes are tagged `AWE PASS` in `ephemeris.gd` and `main.gd`. Search for that string
to find every touched value, or just drop this branch — `main` is untouched.

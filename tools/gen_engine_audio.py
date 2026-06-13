"""Generate Astryx engine SFX as Godot-friendly OGG Vorbis.

Produces a shared start/stop whoosh plus a DISTINCT continuous loop per hull, so
each ship in the fleet has its own engine voice:

  Lyra   - neutral starter (the original 55 Hz reference tone)
  Stella - warm, dependable mid (a touch lower, rounder harmonics)
  Raptor - dangerous low growl (deepest, rough harmonics + harder breathing)
  Vela   - sleek FTL whine (highest, bright, smooth)

Each per-ship voice = base frequency + a harmonic mix + a tremolo "breathing"
rate. ship.gd then layers a small per-ship pitch_scale and a boost-deepening on
top of these, so the result is both timbre- and pitch-distinct.

Run from the project root (writes the .ogg files next to the .gd scripts):
    python3 tools/gen_engine_audio.py
"""

import numpy as np
import soundfile as sf

SAMPLE_RATE = 44100
BASE_FREQ = 55.0          # Lyra reference fundamental (unchanged from the original)

# Per-ship engine voice.
#   base     : fundamental frequency (Hz) — lower = deeper/heavier
#   harmonics: amplitude of harmonics 1..4 (1 = fundamental) — shapes timbre
#   tremolo  : (rate_hz, depth) of the slow amplitude "breathing"
SHIP_VOICES = {
    "lyra": {
        "base": 55.0,
        "harmonics": [0.50, 0.22, 0.10, 0.05],
        "tremolo": (4.0, 0.08),
    },
    "stella": {
        # Warm + dependable: a little lower, fuller 2nd harmonic, gentle breathing.
        "base": 48.0,
        "harmonics": [0.50, 0.30, 0.12, 0.05],
        "tremolo": (3.2, 0.06),
    },
    "raptor": {
        # Dangerous growl: deepest fundamental, strong upper harmonics, harder,
        # faster breathing so it reads as menacing/rough.
        "base": 40.0,
        "harmonics": [0.52, 0.28, 0.18, 0.12],
        "tremolo": (6.5, 0.12),
    },
    "vela": {
        # Sleek FTL whine: highest base, bright high harmonics, very smooth breathing.
        "base": 78.0,
        "harmonics": [0.42, 0.26, 0.16, 0.10],
        "tremolo": (2.5, 0.04),
    },
}


def generate_smooth_loop(voice: dict, duration: float = 4.0) -> np.ndarray:
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    base = voice["base"]

    # Stacked sine harmonics only — no triangle/square waves to avoid harshness.
    wave = np.zeros_like(t)
    for i, amp in enumerate(voice["harmonics"], start=1):
        wave += amp * np.sin(2 * np.pi * base * i * t)

    # Slow amplitude modulation — mimics natural engine "breathing".
    trem_rate, trem_depth = voice["tremolo"]
    tremolo = 1.0 - trem_depth * np.sin(2 * np.pi * trem_rate * t)
    wave *= tremolo

    # Normalise so every ship sits at a consistent peak before crossfading.
    peak = np.max(np.abs(wave))
    if peak > 0:
        wave *= 0.9 / peak

    # Crossfade ends to guarantee a seamless loop (no click at the boundary).
    fade_len = int(SAMPLE_RATE * 0.05)
    fade_in = np.linspace(0, 1, fade_len)
    fade_out = np.linspace(1, 0, fade_len)
    wave[:fade_len] *= fade_in
    wave[-fade_len:] *= fade_out
    return wave.astype(np.float32)


def generate_startup(duration: float = 1.5) -> np.ndarray:
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    pitch_ramp = np.geomspace(10, BASE_FREQ, len(t))
    phase = 2 * np.pi * np.cumsum(pitch_ramp) / SAMPLE_RATE
    volume_envelope = np.linspace(0.0, 1.0, len(t))
    return (0.7 * np.sin(phase) * volume_envelope).astype(np.float32)


def generate_shutdown(duration: float = 2.0) -> np.ndarray:
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration), endpoint=False)
    pitch_ramp = np.linspace(BASE_FREQ, 5, len(t))
    phase = 2 * np.pi * np.cumsum(pitch_ramp) / SAMPLE_RATE
    volume_envelope = np.geomspace(1.0, 0.001, len(t))
    return (0.7 * np.sin(phase) * volume_envelope).astype(np.float32)


def main() -> None:
    # Shared transients (start/stop whoosh) + the generic loop (fallback voice).
    sf.write("engine_loop.ogg", generate_smooth_loop(SHIP_VOICES["lyra"]),
             SAMPLE_RATE, format="OGG", subtype="VORBIS")
    sf.write("engine_start.ogg", generate_startup(),
             SAMPLE_RATE, format="OGG", subtype="VORBIS")
    sf.write("engine_stop.ogg", generate_shutdown(),
             SAMPLE_RATE, format="OGG", subtype="VORBIS")

    # Per-ship distinct loops.
    for name, voice in SHIP_VOICES.items():
        sf.write("engine_loop_%s.ogg" % name, generate_smooth_loop(voice),
                 SAMPLE_RATE, format="OGG", subtype="VORBIS")

    print("Godot-friendly .ogg engine assets generated (shared + per-ship loops).")


if __name__ == "__main__":
    main()

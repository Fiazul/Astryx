"""Astryx — REAL booster sound prototyper.

The old engine voice (tools/gen_engine_audio.py) is pure stacked sine harmonics,
so it reads as a synth *drone*, not a booster. A real rocket/jet booster is mostly
broadband EXHAUST NOISE (the rush/roar) shaped by a filter, sitting on top of a low
tonal RUMBLE (the weight/power), with a slow BREATHING swell so it feels alive.

This script builds exactly that and writes a click-free, seamlessly-looping WAV you
can audition on repeat. Tune the values in the TUNE block, re-run, and listen. Once
you like it we port the same recipe into tools/gen_engine_audio.py per ship.

Deps: numpy only (WAV written via the stdlib `wave` module — no soundfile/scipy).
Run from the project root:
    python3 tools/gen_booster.py
Then play  tools/booster_preview.wav  on loop.
"""

import os
import wave
import numpy as np

SAMPLE_RATE = 44100
# Always write next to this script, no matter what directory you run it from.
OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "booster_preview.wav")

# ======================= TUNE THESE =======================
# Each value says which way to push it. Re-run after every change.

DURATION       = 4.0      # loop length (seconds). Longer = more variation before it repeats.
SEED           = 5        # noise texture. Change to ANY int if you hear an odd whistle/resonance.

# --- ROAR : the exhaust rush. This is the "real booster" body. -------------
ROAR_LEVEL     = .78     # loudness of the rush. The headline of the sound.
ROAR_CENTER_HZ = 150.0    # where the rush sits.  LOWER = deeper/heavier   HIGHER = airier/thinner
ROAR_WIDTH     = 1.4      # spread in octaves.    WIDER = fuller/richer     NARROW = focused/tonal
ROAR_TOP_HZ    = 2.0   # comfort ceiling.      LOWER = softer/darker/comfier   HIGHER = brighter/sharper/hissier
ROAR_FLOOR_HZ  = 70.0     # roar fades out below this (keeps it clear of the rumble).

# --- RUMBLE : low tonal body underneath. The weight/power. -----------------
RUMBLE_LEVEL   = 0.25     # MORE = heavier/throatier   LESS = pure airy rush
RUMBLE_HZ      = 0.0     # pitch of the body.  LOWER = bigger/deeper engine
RUMBLE_HARMS   = [1.0, 0.55, 0.28, 0.12]   # harmonic richness (1st..nth). More entries = throatier.

# --- BREATHING : slow swell so it isn't a static wall. ---------------------
BREATH_RATE_HZ = 0.4      # swell speed. COMFORTABLE = slow (0.3-0.7). Faster = busier/anxious.
BREATH_DEPTH   = 0.12     # swell amount. 0 = dead steady, 0.3 = strong pulsing.

# --- COMFORT / OUTPUT ------------------------------------------------------
SOFTNESS       = 0.65     # extra high smoothing. 0 = raw, 1 = muffled. RAISE if it sounds hissy/harsh.
HP_HZ          = 28.0     # subsonic high-pass: removes INAUDIBLE <HP_HZ rumble/DC that just wastes
                          # headroom & pumps speakers. 0 = off. Lower (e.g. 12) to keep more deep sub-bass.
PEAK           = 0.70     # output level (0..1). Headroom; lower = quieter file.
# ==========================================================


def _snap(freq_hz: float, fundamental: float) -> float:
    """Snap a frequency to a whole number of cycles over the loop, so the buffer
    repeats with zero discontinuity (perfectly seamless loop, no crossfade hack)."""
    return max(round(freq_hz / fundamental), 1) * fundamental


def build_booster() -> np.ndarray:
    n = int(SAMPLE_RATE * DURATION)
    t = np.arange(n) / SAMPLE_RATE
    fundamental = 1.0 / DURATION          # smallest loop-safe frequency step

    # --- ROAR: white noise shaped in the frequency domain. iFFT of a spectrum is
    # inherently periodic over the buffer, so it loops seamlessly with no clicks. ---
    rng = np.random.default_rng(SEED)
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE)
    f = np.maximum(freqs, 1e-6)

    # Gaussian bump in octaves around the centre = the rush's colour.
    bump = np.exp(-0.5 * (np.log2(f / ROAR_CENTER_HZ) / (ROAR_WIDTH * 0.5)) ** 2)
    low_roll = 1.0 / (1.0 + (ROAR_FLOOR_HZ / f) ** 4)          # fade below the floor
    high_roll = 1.0 / (1.0 + (f / ROAR_TOP_HZ) ** (2.0 + 4.0 * SOFTNESS))  # comfort ceiling
    env = bump * low_roll * high_roll
    roar = np.fft.irfft(spec * env, n=n)
    roar /= (np.max(np.abs(roar)) + 1e-9)

    # --- RUMBLE: a few sine harmonics, each snapped to a loop-safe frequency. ---
    rumble = np.zeros(n)
    for i, amp in enumerate(RUMBLE_HARMS, start=1):
        fi = _snap(RUMBLE_HZ * i, fundamental)
        rumble += amp * np.sin(2 * np.pi * fi * t)
    rumble /= (np.max(np.abs(rumble)) + 1e-9)

    mix = ROAR_LEVEL * roar + RUMBLE_LEVEL * rumble

    # --- BREATHING: slow amplitude swell, also snapped so it loops cleanly. ---
    br = _snap(BREATH_RATE_HZ, fundamental)
    breath = 1.0 - BREATH_DEPTH * (0.5 - 0.5 * np.cos(2 * np.pi * br * t))
    mix *= breath

    # --- SUBSONIC HIGH-PASS: strip the inaudible <HP_HZ DC/rumble that only wastes
    # headroom and pumps speakers. Done in the freq domain so the loop stays seamless. ---
    if HP_HZ > 0.0:
        M = np.fft.rfft(mix)
        fh = np.maximum(np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE), 1e-6)
        M *= 1.0 / (1.0 + (HP_HZ / fh) ** 4)
        mix = np.fft.irfft(M, n=n)

    mix *= PEAK / (np.max(np.abs(mix)) + 1e-9)
    return mix.astype(np.float32)


def write_wav(path: str, data: np.ndarray) -> None:
    pcm = np.clip(data, -1.0, 1.0)
    pcm = (pcm * 32767.0).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SAMPLE_RATE)
        w.writeframes(pcm.tobytes())


def main() -> None:
    write_wav(OUT_PATH, build_booster())
    print("Wrote %s  (%.1fs seamless loop, %d Hz)" % (OUT_PATH, DURATION, SAMPLE_RATE))
    print("Play it ON LOOP, then nudge the TUNE block and re-run.")
    print("Quick guide:")
    print("  too thin/whiny      -> lower ROAR_CENTER_HZ, raise RUMBLE_LEVEL")
    print("  too harsh/hissy     -> lower ROAR_TOP_HZ, raise SOFTNESS")
    print("  not powerful enough -> lower RUMBLE_HZ, raise RUMBLE_LEVEL")
    print("  too 'pulsing'       -> lower BREATH_DEPTH (or BREATH_RATE_HZ)")
    print("  sounds like a tone  -> raise ROAR_WIDTH, raise ROAR_LEVEL vs RUMBLE_LEVEL")


if __name__ == "__main__":
    main()

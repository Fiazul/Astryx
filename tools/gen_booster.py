"""Astryx — REAL booster sound prototyper (v2, fidelity pass).

A real rocket/jet booster is mostly broadband EXHAUST NOISE (the rush/roar) shaped by
a filter, sitting on a low tonal RUMBLE (the weight/power), with a slow BREATHING swell
so it feels alive. The previous recipe collapsed the whole thing into a narrow band of
sub-300 Hz noise (ROAR_TOP_HZ was effectively 2 Hz, RUMBLE_HZ was 0) — it had the deep
character we wanted but read as muffled and low-fi once normalised up.

v2 keeps that same deep, heavy, comfortable character (the low-mid BODY still dominates)
but rebuilds it for quality:
  * ROAR is now two layers — a deep BODY (the heart) + a faint, gently-rolled AIR layer
    (the realistic exhaust texture, kept subtle so it stays dark/comfortable).
  * RUMBLE is a real audible tone again (defined low-end weight, not strangled to DC).
  * Soft SATURATION adds harmonic power/warmth without harsh clipping.
  * TPDF DITHER on output kills the quantisation grit that plagued the low-level content.
Everything still loops seamlessly (freq-domain synthesis + loop-snapped tones), click-free.

Deps: numpy only (WAV via the stdlib `wave` module).
Run from the project root:
    python3 tools/gen_booster.py
Then play  tools/booster_preview.wav  on loop. Tune the TUNE block, re-run, listen.
Once you like it we port the same recipe into tools/gen_engine_audio.py per ship.
"""

import os
import wave
import numpy as np

SAMPLE_RATE = 44100
# Always write next to this script, no matter what directory you run it from.
OUT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "booster_preview.wav")

# ======================= TUNE THESE =======================
# Each value says which way to push it. Re-run after every change.

DURATION       = 6.0      # loop length (seconds). Longer = more variation before it repeats.
SEED           = 5        # noise texture. Change to ANY int if you hear an odd whistle/resonance.

# --- ROAR · BODY : the deep exhaust rush. The heart of the sound (keep it dominant). ----
BODY_LEVEL     = 0.80     # loudness of the deep rush. The headline.
BODY_CENTER_HZ = 140.0    # where the body sits.  LOWER = deeper/heavier   HIGHER = airier/thinner
BODY_WIDTH     = 1.7      # spread in octaves.    WIDER = fuller/richer     NARROW = focused/tonal
BODY_FLOOR_HZ  = 55.0     # body fades out below this (keeps it clear of the rumble).
BODY_TOP_HZ    = 900.0    # body's own ceiling — keeps the heart in the low-mids.

# --- ROAR · AIR : faint high exhaust texture so it isn't muffled. KEEP SUBTLE/comfy. ----
AIR_LEVEL      = 0.12     # loudness of the airy texture. RAISE = brighter/hissier, LOWER = darker.
AIR_CENTER_HZ  = 1600.0   # where the air sits.
AIR_WIDTH      = 2.2      # spread in octaves (broad, gentle).
AIR_TOP_HZ     = 4200.0   # comfort ceiling. LOWER = softer/darker/comfier  HIGHER = brighter/sharper.

# --- RUMBLE : low tonal body underneath. The weight/power. -----------------
RUMBLE_LEVEL   = 0.30     # MORE = heavier/throatier   LESS = pure airy rush
RUMBLE_HZ      = 46.0     # pitch of the body.  LOWER = bigger/deeper engine
RUMBLE_HARMS   = [1.0, 0.6, 0.32, 0.16, 0.08]   # harmonic richness (1st..nth). More = throatier.

# --- BREATHING : slow swell so it isn't a static wall. ---------------------
BREATH_RATE_HZ = 0.35     # swell speed. COMFORTABLE = slow (0.3-0.7). Faster = busier/anxious.
BREATH_DEPTH   = 0.14     # swell amount. 0 = dead steady, 0.3 = strong pulsing.

# --- POWER / COMFORT / OUTPUT ----------------------------------------------
SATURATION     = 1.6      # soft tanh drive for harmonic power. 1.0 = clean, 2.5 = gritty/loud.
SOFTNESS       = 0.55     # extra high smoothing on AIR. 0 = raw, 1 = muffled. RAISE if hissy/harsh.
HP_HZ          = 25.0     # subsonic high-pass: strips INAUDIBLE <HP_HZ DC/rumble that wastes
                          # headroom & pumps speakers. 0 = off. Lower (e.g. 12) to keep deep sub-bass.
DITHER         = 1.0      # TPDF dither (LSBs) before 16-bit quantise. ~1.0 hides quantisation grit.
PEAK           = 0.85     # output level (0..1). Headroom; lower = quieter file.
# ==========================================================


def _snap(freq_hz: float, fundamental: float) -> float:
    """Snap a frequency to a whole number of cycles over the loop, so the buffer
    repeats with zero discontinuity (perfectly seamless loop, no crossfade hack)."""
    return max(round(freq_hz / fundamental), 1) * fundamental


def _shaped_noise(spec, freqs, center, width, floor_hz, top_hz, soft) -> np.ndarray:
    """A band of seamless noise: a Gaussian bump (in octaves) around `center`, fading
    below `floor_hz` and rolled off above `top_hz`. `spec` is a shared white spectrum so
    the layers stay phase-coherent (no comb artefacts when summed)."""
    n = (len(freqs) - 1) * 2
    f = np.maximum(freqs, 1e-6)
    bump = np.exp(-0.5 * (np.log2(f / center) / (width * 0.5)) ** 2)
    low_roll = 1.0 / (1.0 + (floor_hz / f) ** 4) if floor_hz > 0 else 1.0
    high_roll = 1.0 / (1.0 + (f / top_hz) ** (2.0 + 4.0 * soft))
    band = np.fft.irfft(spec * bump * low_roll * high_roll, n=n)
    return band / (np.max(np.abs(band)) + 1e-9)


def build_booster() -> np.ndarray:
    n = int(SAMPLE_RATE * DURATION)
    t = np.arange(n) / SAMPLE_RATE
    fundamental = 1.0 / DURATION          # smallest loop-safe frequency step

    # --- ROAR: white noise shaped in the frequency domain. iFFT of a spectrum is
    # inherently periodic over the buffer, so it loops seamlessly with no clicks. The
    # BODY and AIR layers share one spectrum so their phases line up cleanly. ---
    rng = np.random.default_rng(SEED)
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE)

    body = _shaped_noise(spec, freqs, BODY_CENTER_HZ, BODY_WIDTH, BODY_FLOOR_HZ, BODY_TOP_HZ, 0.0)
    air  = _shaped_noise(spec, freqs, AIR_CENTER_HZ, AIR_WIDTH, 0.0, AIR_TOP_HZ, SOFTNESS)

    # --- RUMBLE: a few sine harmonics, each snapped to a loop-safe frequency. ---
    rumble = np.zeros(n)
    for i, amp in enumerate(RUMBLE_HARMS, start=1):
        fi = _snap(RUMBLE_HZ * i, fundamental)
        rumble += amp * np.sin(2 * np.pi * fi * t)
    rumble /= (np.max(np.abs(rumble)) + 1e-9)

    mix = BODY_LEVEL * body + AIR_LEVEL * air + RUMBLE_LEVEL * rumble

    # --- BREATHING: slow amplitude swell, also snapped so it loops cleanly. ---
    br = _snap(BREATH_RATE_HZ, fundamental)
    breath = 1.0 - BREATH_DEPTH * (0.5 - 0.5 * np.cos(2 * np.pi * br * t))
    mix *= breath

    # --- SATURATION: soft tanh drive adds harmonic power/warmth (a real engine isn't a
    # pure linear sum). Periodic in -> periodic out, so the loop stays seamless. ---
    if SATURATION > 1.0:
        mix = np.tanh(SATURATION * mix / (np.max(np.abs(mix)) + 1e-9))

    # --- SUBSONIC HIGH-PASS: strip inaudible <HP_HZ DC/rumble that only wastes headroom
    # and pumps speakers. Done in the freq domain so the loop stays seamless. ---
    if HP_HZ > 0.0:
        M = np.fft.rfft(mix)
        fh = np.maximum(np.fft.rfftfreq(n, 1.0 / SAMPLE_RATE), 1e-6)
        M *= 1.0 / (1.0 + (HP_HZ / fh) ** 4)
        mix = np.fft.irfft(M, n=n)

    mix *= PEAK / (np.max(np.abs(mix)) + 1e-9)
    return mix.astype(np.float32)


def write_wav(path: str, data: np.ndarray) -> None:
    # TPDF dither: triangular noise at ~1 LSB masks 16-bit quantisation distortion, which
    # is what made the low-level deep content sound gritty/cheap before.
    scaled = data * 32767.0
    if DITHER > 0.0:
        rng = np.random.default_rng(SEED + 1)
        scaled = scaled + DITHER * (rng.random(len(data)) - rng.random(len(data)))
    pcm = np.clip(np.round(scaled), -32768, 32767).astype("<i2")
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
    print("  too muffled/dull    -> raise AIR_LEVEL or AIR_TOP_HZ")
    print("  too bright/hissy    -> lower AIR_LEVEL or AIR_TOP_HZ, raise SOFTNESS")
    print("  not heavy enough    -> lower RUMBLE_HZ/BODY_CENTER_HZ, raise RUMBLE_LEVEL/BODY_LEVEL")
    print("  not powerful enough -> raise SATURATION (watch for grit)")
    print("  too 'pulsing'       -> lower BREATH_DEPTH (or BREATH_RATE_HZ)")
    print("  sounds like a tone  -> raise BODY_WIDTH, raise BODY_LEVEL vs RUMBLE_LEVEL")


if __name__ == "__main__":
    main()

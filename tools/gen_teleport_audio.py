#!/usr/bin/env python3
# Generator for the TELEPORT "voooouuu" whoosh -> assets/teleport.wav
# A long, SUSTAINED rising drone (≈6s) so it can play across the whole teleport ritual
# while the game fades its VOLUME in then out (see main._update_teleport). The pitch
# climbs with a vibrato wobble (the "voooouuu" warble) over a detuned tonal body + an
# airy low-passed noise layer. Amplitude is kept steady (only tiny anti-click fades at
# the very ends) so the in-game volume bell does the fade-in/fade-out cleanly.
import math, struct, wave, os, random

SR = 44100
DUR = 11.0                 # longer than the teleport ritual so the fade-out never cuts to silence
N = int(SR * DUR)
random.seed(7)

samples = []
lp = 0.0   # one-pole low-pass state for the airy whoosh layer
for i in range(N):
    t = i / SR
    p = t / DUR
    rise = p ** 0.7                       # pitch climbs across the whole drone
    freq = 110.0 + 360.0 * rise           # GENTLE upward sweep (stays low/warm, not piercing)
    freq += 16.0 * math.sin(2 * math.pi * 2.8 * t)    # shallow, slow vibrato -> soft warble
    tone = math.sin(2 * math.pi * freq * t)
    tone += 0.6 * math.sin(2 * math.pi * freq * 0.5 * t)   # stronger sub-octave -> warmer body
    tone += 0.08 * math.sin(2 * math.pi * freq * 1.5 * t)  # faint fifth (was the harsh shimmer)
    tone *= 0.5
    noise = random.uniform(-1.0, 1.0)
    cutoff = 0.025 + 0.07 * rise          # darker filter -> the air stays soft, not hissy
    lp += cutoff * (noise - lp)
    air = lp * 0.7
    # Steady amplitude; longer 150ms anti-click ramps soften the on/off edges.
    edge = min(1.0, t / 0.15, (DUR - t) / 0.15)
    samples.append((tone * 0.7 + air * 0.28) * edge)

peak = max(abs(x) for x in samples) or 1.0
gain = 0.72 / peak
data = b"".join(struct.pack("<h", int(max(-1, min(1, x * gain)) * 32767)) for x in samples)
out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "teleport.wav"))
with wave.open(out, "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes(data)
print("wrote", out, "(%.0fms)" % (DUR * 1000))

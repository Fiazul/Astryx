#!/usr/bin/env python3
# Draws TAB_TARGETING.png — a diagram of how Tab picks a target: a ray from the nose through
# the crosshair, extended to infinity; whatever sits nearest that LINE (smallest angle) wins.
import os, math
from PIL import Image, ImageDraw, ImageFont

W, H = 1500, 900
img = Image.new("RGB", (W, H), (7, 8, 15))
d = ImageDraw.Draw(img)
def font(s, bold=True):
    p = "/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if bold else "")
    try: return ImageFont.truetype(p, s)
    except Exception: return ImageFont.load_default()
f_title, f_h, f, f_s = font(36), font(20), font(17, False), font(14, False)

import random; random.seed(2)
for _ in range(400):
    d.point((random.randint(0, W), random.randint(0, H)), fill=(34, 38, 54))

ship = (170, 470)          # nose origin
ang = math.radians(-6)     # the ray points slightly up-right
dx, dy = math.cos(ang), math.sin(ang)
# The aim ray (extended) + the narrow ±7° "on the line" beam.
end = (ship[0] + dx * 1180, ship[1] + dy * 1180)
for sgn in (1, -1):
    ca = ang + sgn * math.radians(7)
    ce = (ship[0] + math.cos(ca) * 1180, ship[1] + math.sin(ca) * 1180)
    d.line([ship, ce], fill=(40, 70, 95), width=1)
# dashed ray
steps = 90
for i in range(steps):
    if i % 2 == 0:
        a = (ship[0] + dx * (i / steps) * 1180, ship[1] + dy * (i / steps) * 1180)
        b = (ship[0] + dx * ((i + 1) / steps) * 1180, ship[1] + dy * ((i + 1) / steps) * 1180)
        d.line([a, b], fill=(95, 190, 240), width=3)
d.text((end[0] - 250, end[1] - 36), "aim ray → ∞", font=f_h, fill=(150, 210, 245))

# Ship + nose triangle.
d.polygon([(ship[0]-22, ship[1]-14), (ship[0]-22, ship[1]+14), (ship[0]+18, ship[1])], fill=(220, 210, 120))
d.text((ship[0]-70, ship[1]+22), "YOUR SHIP", font=f_s, fill=(200, 200, 160))
d.text((ship[0]-70, ship[1]+40), "(nose → ray)", font=f_s, fill=(150, 150, 130))

def pt_on_ray(t): return (ship[0] + dx * t, ship[1] + dy * t)
def dot(p, r, col, outline=None):
    d.ellipse([p[0]-r, p[1]-r, p[0]+r, p[1]+r], fill=col, outline=outline, width=2)

# A: far star, dead on the ray → TAB TARGET.
A = pt_on_ray(1000); A = (A[0], A[1]-6)
dot(A, 18, (90, 220, 130), (220, 255, 230))
d.text((A[0]-30, A[1]-54), "★ FAR STAR", font=f_h, fill=(150, 240, 180))
d.text((A[0]-40, A[1]+24), "on the line → TAB TARGET ✓", font=f, fill=(150, 240, 180))

# B: near planet, OFF to the side → ignored (big angle, even though close to the ship).
B = (ship[0] + 250, ship[1] + 210)
dot(B, 13, (230, 110, 100), (255, 200, 195))
d.text((B[0]-20, B[1]+18), "near planet, OFF the line", font=f, fill=(235, 150, 140))
d.text((B[0]-20, B[1]+38), "ignored ✗ (big angle)", font=f, fill=(235, 150, 140))
# angle wedge from ship to B
d.line([ship, B], fill=(120, 70, 70), width=1)

# C: object just inside the cone but farther off the ray than A → loses to A.
C = pt_on_ray(620); C = (C[0]+30, C[1]+95)
dot(C, 11, (150, 160, 185), (210, 215, 230))
d.text((C[0]+16, C[1]-6), "inside cone but farther", font=f_s, fill=(160, 170, 190))
d.text((C[0]+16, C[1]+12), "off the line → loses to ★", font=f_s, fill=(160, 170, 190))

# Title + takeaway.
d.text((50, 30), "ASTRYX — HOW  TAB  TARGETING WORKS", font=f_title, fill=(220, 240, 255))
d.text((52, 78), "Tab steps through the 4 closest to the aim RAY (1st→2nd→3rd→4th→loop) — smallest ANGLE off the line, not nearest to you.",
        font=f_h, fill=(150, 180, 205))
ly = H - 70
d.text((52, ly), "• Ahead on the ray   • Within reach (star ~30 ly · planet ~0.3–2 ly · probe ~0.3 ly)   • Within a NARROW ~7° of the line",
        font=f, fill=(170, 185, 205))
d.text((52, ly + 26), "• Closest-to-the-line first; Tab cycles · move cursor to re-rank   • Unscanned targets read 'Unknown Planet/Star' until you scan (V)",
        font=f, fill=(170, 185, 205))

out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "TAB_TARGETING.png"))
img.save(out)
print("wrote", out)

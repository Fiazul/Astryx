#!/usr/bin/env python3
# Renders the wormhole network (from /tmp/wh_graph.json) to WORMHOLE_NETWORK.png as a clean
# SCHEMATIC: Earth at the centre, the 5 hubs in a ring (all linked to Earth + to each other),
# and every star fanned out as a spoke off its hub. Not spatially exact — it's a topology map,
# which is the point: it shows the ≤3-hop hub structure at a glance.
import json, os, math, random
from PIL import Image, ImageDraw, ImageFont

W, H = 1500, 1050
CX, CY = W / 2, H / 2 + 20
R_HUB = 330          # hub ring radius
R_SPOKE = 150        # how far spokes sit beyond their hub
g = json.load(open("/tmp/wh_graph.json"))
nodes = {n["id"]: n for n in g["nodes"]}
earth = g["earth"]
hub_ids = [n["id"] for n in g["nodes"] if n["hub"]]

# Map each spoke to its hub (the hub endpoint of its edge). Interstellar hangs off Earth.
hub_of, earth_sat = {}, []
for a, b in g["edges"]:
    na, nb = nodes[a], nodes[b]
    if na["hub"] and not (nb["hub"] or nb["earth"]):
        hub_of[b] = a
    elif nb["hub"] and not (na["hub"] or na["earth"]):
        hub_of[a] = b
    elif na["earth"] and not (nb["hub"] or nb["earth"]):
        earth_sat.append(b)
    elif nb["earth"] and not (na["hub"] or na["earth"]):
        earth_sat.append(a)

pos = { earth: (CX, CY) }
hub_angle = {}
for i, h in enumerate(hub_ids):
    a = -math.pi / 2 + i * 2 * math.pi / len(hub_ids)
    hub_angle[h] = a
    pos[h] = (CX + R_HUB * math.cos(a), CY + R_HUB * math.sin(a))
for i, s in enumerate(earth_sat):
    pos[s] = (CX + 70 * math.cos(i), CY + 70 * math.sin(i))
# Fan each hub's spokes outward (away from centre), 1–2 rows so ~10 fit cleanly.
for h in hub_ids:
    sp = [s for s, hh in hub_of.items() if hh == h]
    base = hub_angle[h]
    for i, s in enumerate(sp):
        row = i % 2
        idx = i // 2
        cnt = (len(sp) + 1) // 2
        spread = 1.15
        off = ((idx / max(cnt - 1, 1)) - 0.5) * spread if cnt > 1 else 0.0
        ang = base + off
        r = R_SPOKE + row * 56
        hx, hy = pos[h]
        pos[s] = (hx + r * math.cos(ang), hy + r * math.sin(ang))

img = Image.new("RGB", (W, H), (6, 7, 14))
d = ImageDraw.Draw(img)
def font(sz):
    try: return ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", sz)
    except Exception: return ImageFont.load_default()
f_title, f_hub, f_small, f_leg = font(36), font(18), font(11), font(16)

random.seed(1)
for _ in range(500):
    d.point((random.randint(0, W), random.randint(0, H)), fill=(38, 42, 58))

def is_core(a, b):
    na, nb = nodes[a], nodes[b]
    return (na["earth"] or na["hub"]) and (nb["earth"] or nb["hub"])
for a, b in g["edges"]:
    if a not in pos or b not in pos:
        continue
    pa, pb = pos[a], pos[b]
    if is_core(a, b):
        d.line([pa, pb], fill=(95, 185, 235), width=3)
    else:
        d.line([pa, pb], fill=(52, 66, 86), width=1)

for n in g["nodes"]:
    if n["id"] not in pos:
        continue
    x, y = pos[n["id"]]
    if n["earth"]:
        d.ellipse([x-15, y-15, x+15, y+15], fill=(255, 215, 90), outline=(255, 255, 255), width=2)
        d.text((x-18, y+18), "EARTH", font=f_hub, fill=(255, 230, 140))
    elif n["hub"]:
        d.ellipse([x-12, y-12, x+12, y+12], fill=(80, 210, 255), outline=(225, 250, 255), width=2)
        d.text((x+15, y-8), n["name"], font=f_hub, fill=(175, 238, 255))
    else:
        d.ellipse([x-3, y-3, x+3, y+3], fill=(160, 170, 190))
        d.text((x+5, y-5), n["name"], font=f_small, fill=(120, 132, 150))

d.text((50, 26), "ASTRYX — WORMHOLE NETWORK", font=f_title, fill=(220, 240, 255))
d.text((52, 70), "5 hubs, each linked to Earth and to each other.  Earth→anywhere ≤ 2 hops, any→any ≤ 3.",
        font=f_leg, fill=(150, 175, 200))
ly = H - 48
d.ellipse([50, ly, 68, ly+18], fill=(255, 215, 90)); d.text((76, ly), "Earth", font=f_leg, fill=(200, 210, 225))
d.ellipse([200, ly, 218, ly+18], fill=(80, 210, 255)); d.text((226, ly), "Hub", font=f_leg, fill=(200, 210, 225))
d.ellipse([330, ly+6, 336, ly+12], fill=(160, 170, 190)); d.text((346, ly), "Star / system", font=f_leg, fill=(200, 210, 225))
d.line([510, ly+9, 560, ly+9], fill=(95, 185, 235), width=3); d.text((568, ly), "Hub lane", font=f_leg, fill=(200, 210, 225))

out = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "WORMHOLE_NETWORK.png"))
img.save(out)
print("wrote", out)

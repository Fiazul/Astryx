#!/usr/bin/env python3
"""
Compute REAL geocentric positions of the Sun + 8 planets for a given date,
from JPL's low-precision Keplerian elements (valid 1800-2050), and place a
set of REAL nearby stars from catalog RA/Dec/distance.

Earth is the anchor at (0,0,0) — coordinates are geocentric (what NASA RA/Dec
are measured from). Output is given in raw AU/ly (the real truth) AND mapped
to scene units so the dev can verify before anything is baked in.

Frame: ICRS / J2000 equatorial, right-handed. Scene mapping (Godot, Y-up):
    scene.x = eq.x , scene.y = eq.z (celestial north = up) , scene.z = eq.y
"""
import math

DEG = math.pi / 180.0
AU_PER_LY = 63241.077
LY_PER_AU = 1.0 / AU_PER_LY
OBLIQUITY = 23.43928 * DEG  # J2000 mean obliquity of the ecliptic

# --- Date -------------------------------------------------------------------
# 2026-06-12 00:00 TT
def julian_day(y, m, d):
    if m <= 2:
        y -= 1; m += 12
    A = y // 100
    B = 2 - A + A // 4
    return int(365.25 * (y + 4716)) + int(30.6001 * (m + 1)) + d + B - 1524.5

JD = julian_day(2026, 6, 12)
T = (JD - 2451545.0) / 36525.0  # Julian centuries since J2000

# --- JPL Keplerian elements (J2000) + rates per century ---------------------
# a(AU) e I(deg) L(deg) longPeri(deg) longNode(deg)
ELEMENTS = {
    "Mercury": ([0.38709927, 0.20563593, 7.00497902, 252.25032350, 77.45779628, 48.33076593],
                [0.00000037, 0.00001906, -0.00594749, 149472.67411175, 0.16047689, -0.12534081]),
    "Venus":   ([0.72333566, 0.00677672, 3.39467605, 181.97909950, 131.60246718, 76.67984255],
                [0.00000390, -0.00004107, -0.00078890, 58517.81538729, 0.00268329, -0.27769418]),
    "Earth":   ([1.00000261, 0.01671123, -0.00001531, 100.46457166, 102.93768193, 0.0],
                [0.00000562, -0.00004392, -0.01294668, 35999.37244981, 0.32327364, 0.0]),
    "Mars":    ([1.52371034, 0.09339410, 1.84969142, -4.55343205, -23.94362959, 49.55953891],
                [0.00001847, 0.00007882, -0.00813131, 19140.30268499, 0.44441088, -0.29257343]),
    "Jupiter": ([5.20288700, 0.04838624, 1.30439695, 34.39644051, 14.72847983, 100.47390909],
                [-0.00011607, -0.00013253, -0.00183714, 3034.74612775, 0.21252668, 0.20469106]),
    "Saturn":  ([9.53667594, 0.05386179, 2.48599187, 49.95424423, 92.59887831, 113.66242448],
                [-0.00125060, -0.00050991, 0.00193609, 1222.49362201, -0.41897216, -0.28867794]),
    "Uranus":  ([19.18916464, 0.04725744, 0.77263783, 313.23810451, 170.95427630, 74.01692503],
                [-0.00196176, -0.00004397, -0.00242939, 428.48202785, 0.40805281, 0.04240589]),
    "Neptune": ([30.06992276, 0.00859048, 1.77004347, -55.12002969, 44.96476227, 131.78422574],
                [0.00026291, 0.00005105, 0.00035372, 218.45945325, -0.32241464, -0.00508664]),
}

def kepler(M, e):
    M = math.radians((math.degrees(M) + 180) % 360 - 180)
    E = M + e * math.sin(M)
    for _ in range(40):
        dE = (E - e * math.sin(E) - M) / (1 - e * math.cos(E))
        E -= dE
        if abs(dE) < 1e-12:
            break
    return E

def helio_ecliptic(name):
    el, rt = ELEMENTS[name]
    a  = el[0] + rt[0] * T
    e  = el[1] + rt[1] * T
    I  = (el[2] + rt[2] * T) * DEG
    L  = (el[3] + rt[3] * T) * DEG
    wb = (el[4] + rt[4] * T) * DEG      # longitude of perihelion
    Om = (el[5] + rt[5] * T) * DEG      # longitude of ascending node
    w  = wb - Om                         # argument of perihelion
    M  = L - wb
    E  = kepler(M, e)
    xp = a * (math.cos(E) - e)
    yp = a * math.sqrt(1 - e * e) * math.sin(E)
    cw, sw = math.cos(w), math.sin(w)
    cO, sO = math.cos(Om), math.sin(Om)
    cI, sI = math.cos(I), math.sin(I)
    x = (cw*cO - sw*sO*cI)*xp + (-sw*cO - cw*sO*cI)*yp
    y = (cw*sO + sw*cO*cI)*xp + (-sw*sO + cw*cO*cI)*yp
    z = (sw*sI)*xp + (cw*sI)*yp
    return x, y, z  # ecliptic J2000, AU

def ecl_to_eq(x, y, z):
    co, so = math.cos(OBLIQUITY), math.sin(OBLIQUITY)
    return x, y*co - z*so, y*so + z*co

# Earth heliocentric (ecliptic)
ex, ey, ez = helio_ecliptic("Earth")

bodies = []  # (name, eq_geocentric AU xyz, distance AU)

# Sun: geocentric = -Earth_helio
sx, sy, sz = ecl_to_eq(-ex, -ey, -ez)
bodies.append(("Sun", (sx, sy, sz), math.sqrt(sx*sx+sy*sy+sz*sz)))

for name in ["Mercury","Venus","Mars","Jupiter","Saturn","Uranus","Neptune"]:
    hx, hy, hz = helio_ecliptic(name)
    gx, gy, gz = hx-ex, hy-ey, hz-ez            # geocentric ecliptic
    qx, qy, qz = ecl_to_eq(gx, gy, gz)          # geocentric equatorial
    bodies.append((name, (qx, qy, qz), math.sqrt(qx*qx+qy*qy+qz*qz)))

# --- REAL nearby stars (J2000): RA, Dec, distance(ly) -----------------------
# RA in (h,m,s), Dec in (d,m,s). Catalog values (HYG / SIMBAD).
STARS = [
    ("Proxima Centauri", (14,29,42.9), (-62,40,46), 4.2465),
    ("Alpha Centauri A",  (14,39,36.5), (-60,50,2),  4.3650),
    ("Barnard's Star",    (17,57,48.5), ( 4,41,36),  5.9630),
    ("Wolf 359",          (10,56,29.2), ( 7, 0,53),  7.8560),
    ("Lalande 21185",     (11, 3,20.2), (35,58,12),  8.3070),
    ("Sirius A",          ( 6,45, 8.9), (-16,42,58), 8.6110),
    ("Epsilon Eridani",   ( 3,32,55.8), (-9,27,30),  10.475),
    ("Tau Ceti",          ( 1,44, 4.1), (-15,56,15), 11.912),
]

def hms_to_deg(h, m, s): return (h + m/60 + s/3600) * 15.0
def dms_to_deg(d, m, s):
    sign = -1 if (d < 0 or (d == 0 and (m < 0 or s < 0))) else 1
    return sign * (abs(d) + abs(m)/60 + abs(s)/3600)

stars = []
for name, ra, dec, dist_ly in STARS:
    a = hms_to_deg(*ra) * DEG
    d = dms_to_deg(*dec) * DEG
    dist_au = dist_ly * AU_PER_LY
    x = dist_au * math.cos(d) * math.cos(a)
    y = dist_au * math.cos(d) * math.sin(a)
    z = dist_au * math.sin(d)
    stars.append((name, (x, y, z), dist_au, dist_ly))

# --- Report -----------------------------------------------------------------
print(f"# Date 2026-06-12  (JD {JD:.1f}, T={T:.6f} cy)  | ICRS/J2000 equatorial, geocentric")
print(f"# 1 AU = {LY_PER_AU:.3e} ly ; 1 ly = {AU_PER_LY:.0f} AU\n")

print("== SOLAR SYSTEM (geocentric, Earth at origin) ==")
print(f"{'Body':10} {'dist (AU)':>11} {'dist (ly)':>12}   eq XYZ (AU)")
for name, (x,y,z), dau in bodies:
    print(f"{name:10} {dau:11.5f} {dau*LY_PER_AU:12.3e}   ({x:9.4f},{y:9.4f},{z:9.4f})")

print("\n== NEARBY STARS (real RA/Dec/parallax) ==")
print(f"{'Star':18} {'dist (ly)':>10} {'dist (AU)':>14}   eq XYZ (AU)")
for name, (x,y,z), dau, dly in stars:
    print(f"{name:18} {dly:10.3f} {dau:14.1f}   ({x:12.1f},{y:12.1f},{z:12.1f})")

# --- Scene-unit mapping under each candidate scale --------------------------
def scene_xyz(eq):  # ICRS eq -> Godot Y-up
    x, y, z = eq
    return (x, z, y)

print("\n== SCENE COORDS — candidate scales ==")
for label, unit_per_au in [("A) 1u=0.1AU (solar-system arena)", 10.0),
                           ("B) 1u=0.01ly (canon HUD)", LY_PER_AU*100.0)]:
    print(f"\n-- {label}  [1 AU = {unit_per_au:g} units] --")
    for name, eq, dau in bodies:
        sx, sy, sz = scene_xyz(eq)
        print(f"   {name:10} -> ({sx*unit_per_au:11.4f},{sy*unit_per_au:11.4f},{sz*unit_per_au:11.4f})")
    for name, eq, dau, dly in stars[:3]:
        sx, sy, sz = scene_xyz(eq)
        print(f"   {name:18} -> ({sx*unit_per_au:14.1f},{sy*unit_per_au:14.1f},{sz*unit_per_au:14.1f})")

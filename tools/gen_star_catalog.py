#!/usr/bin/env python3
# Generates the GDScript STAR CATALOGUE rows for systems.gd from the real nearest-star
# table (data: Wikipedia "List of nearest stars", J2000). Binaries collapsed to one
# system (primary). Emits rows with ra_deg/dec_deg (parsed from h:m:s / d:m:s) so the
# game's coord() can build true 3D positions at runtime. Run:  python3 gen_star_catalog.py
#
# Columns: id, display name, distance ly, RA "h m s", Dec "d m s", spectral type.
ROWS = [
    ("alpha_centauri", "Alpha Centauri", 4.34,  "14 39 36.5", "-60 50 02", "G2V"),
    ("barnards_star",  "Barnard's Star", 5.96,  "17 57 48.5", "+04 41 36", "M4.0V"),
    ("luhman_16",      "Luhman 16",      6.51,  "10 49 18.9", "-53 19 10", "L8"),
    ("wolf_359",       "Wolf 359",       7.86,  "10 56 29.2", "+07 00 53", "M6.0V"),
    ("lalande_21185",  "Lalande 21185",  8.30,  "11 03 20.2", "+35 58 12", "M2.0V"),
    ("sirius",         "Sirius",         8.71,  "06 45 08.9", "-16 42 58", "A1V"),
    ("luyten_726-8",   "Luyten 726-8",   8.77,  "01 39 01.3", "-17 57 01", "M5.5V"),
    ("ross_154",       "Ross 154",       9.71,  "18 49 49.4", "-23 50 10", "M3.5V"),
    ("ross_248",       "Ross 248",       10.31, "23 41 54.7", "+44 10 30", "M5.5V"),
    ("epsilon_eridani","Epsilon Eridani",10.47, "03 32 55.8", "-09 27 30", "K2V"),
    ("lacaille_9352",  "Lacaille 9352",  10.72, "23 05 52.0", "-35 51 11", "M0.5V"),
    ("ross_128",       "Ross 128",       11.01, "11 47 44.4", "+00 48 16", "M4.0V"),
    ("ez_aquarii",     "EZ Aquarii",     11.11, "22 38 33.4", "-15 17 57", "M5.0V"),
    ("61_cygni",       "61 Cygni",       11.40, "21 06 53.9", "+38 44 58", "K5.0V"),
    ("procyon",        "Procyon",        11.46, "07 39 18.1", "+05 13 30", "F5IV"),
    ("struve_2398",    "Struve 2398",    11.49, "18 42 46.7", "+59 37 49", "M3.0V"),
    ("groombridge_34", "Groombridge 34", 11.62, "00 18 22.9", "+44 01 23", "M1.5V"),
    ("dx_cancri",      "DX Cancri",      11.68, "08 29 49.5", "+26 46 37", "M6.5V"),
    ("epsilon_indi",   "Epsilon Indi",   11.87, "22 03 21.7", "-56 47 10", "K5V"),
    ("tau_ceti",       "Tau Ceti",       11.91, "01 44 04.1", "-15 56 15", "G8.5V"),
    ("gj_1061",        "GJ 1061",        11.98, "03 35 59.7", "-44 30 45", "M5.5V"),
    ("yz_ceti",        "YZ Ceti",        12.12, "01 12 30.6", "-16 59 56", "M4.5V"),
    ("luytens_star",   "Luyten's Star",  12.35, "07 27 24.5", "+05 13 33", "M3.5V"),
    ("teegardens_star","Teegarden's Star",12.50,"02 53 00.9", "+16 52 53", "M6.5V"),
    ("kapteyns_star",  "Kapteyn's Star", 12.83, "05 11 40.6", "-45 01 06", "M1.5VI"),
    ("lacaille_8760",  "Lacaille 8760",  12.95, "21 17 15.3", "-38 52 03", "M0.0V"),
    ("scr_1845",       "SCR 1845-6357",  13.06, "18 45 05.3", "-63 57 48", "M8.5V"),
    ("kruger_60",      "Kruger 60",      13.07, "22 27 59.5", "+57 41 45", "M3.0V"),
    ("denis_1048",     "DENIS J1048-3956",13.19,"10 48 14.7", "-39 56 06", "M8.5V"),
    ("ross_614",       "Ross 614",       13.36, "06 29 23.4", "-02 48 50", "M4.5V"),
    ("wolf_1061",      "Wolf 1061",      14.05, "16 30 18.1", "-12 39 45", "M3.0V"),
    ("van_maanens_star","Van Maanen's Star",14.07,"00 49 09.9","+05 23 19", "DZ7"),
    ("gliese_1",       "Gliese 1",       14.17, "00 05 24.4", "-37 21 27", "M1.5V"),
    ("tz_arietis",     "TZ Arietis",     14.58, "02 00 13.2", "+13 03 08", "M4.5V"),
    ("wolf_424",       "Wolf 424",       14.60, "12 33 17.2", "+09 01 15", "M5.5V"),
    ("gliese_687",     "Gliese 687",     14.84, "17 36 25.9", "+68 20 21", "M3.0V"),
    ("gliese_674",     "Gliese 674",     14.85, "17 28 39.9", "-46 53 43", "M3.0V"),
    ("lhs_292",        "LHS 292",        14.87, "10 48 12.6", "-11 20 14", "M6.5V"),
    ("gliese_440",     "Gliese 440",     15.12, "11 45 42.9", "-64 50 29", "DQ6"),
    ("gj_1245",        "GJ 1245",        15.20, "19 53 54.2", "+44 24 55", "M5.5V"),
    ("gliese_876",     "Gliese 876",     15.24, "22 53 16.7", "-14 15 49", "M3.5V"),
    ("groombridge_1618","Groombridge 1618",15.89,"10 11 22.1","+49 27 15", "K7.0V"),
    ("gliese_412",     "Gliese 412",     16.00, "11 05 28.6", "+43 31 36", "M1.0V"),
    ("ad_leonis",      "AD Leonis",      16.19, "10 19 36.4", "+19 52 10", "M3.0V"),
    ("gliese_832",     "Gliese 832",     16.20, "21 33 34.0", "-49 00 32", "M1.5V"),
    ("omicron2_eridani","Omicron-2 Eridani",16.33,"04 15 16.3","-07 39 10", "K0.5V"),
]


def hms_to_deg(s):
    h, m, sec = (float(x) for x in s.split())
    return (h + m / 60.0 + sec / 3600.0) * 15.0


def dms_to_deg(s):
    parts = s.split()
    sign = -1.0 if parts[0].startswith("-") else 1.0
    d, m, sec = abs(float(parts[0])), float(parts[1]), float(parts[2])
    return sign * (d + m / 60.0 + sec / 3600.0)


def star_color(sp):
    c = sp[0]
    return {
        "O": (0.60, 0.70, 1.00), "B": (0.70, 0.80, 1.00), "A": (0.95, 0.96, 1.00),
        "F": (1.00, 0.98, 0.92), "G": (1.00, 0.92, 0.65), "K": (1.00, 0.76, 0.42),
        "M": (1.00, 0.50, 0.30), "L": (0.72, 0.34, 0.26), "T": (0.66, 0.30, 0.30),
        "D": (0.86, 0.90, 1.00),
    }.get(c, (1.00, 0.85, 0.50))


def main():
    print("# --- generated by tools/gen_star_catalog.py — real nearest stars (J2000) ---")
    for sid, name, dist, ra, dec, sp in ROWS:
        ra_d = round(hms_to_deg(ra), 3)
        dec_d = round(dms_to_deg(dec), 3)
        r, g, b = star_color(sp)
        print(
            '\t{ "id": "%s", "name": "%s", "ly": %.2f, "ra": %.3f, "dec": %.3f, '
            '"spectral": "%s", "color": Color(%.2f, %.2f, %.2f) },'
            % (sid, name, dist, ra_d, dec_d, sp, r, g, b)
        )


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Parse the Tycho-2 catalogue (CDS I/259, tyc2.dat.NN.gz) into a slim binary the
Godot baker reads:  tools/data/tycho_slim.bin  =  float32 [ra_deg, dec_deg, Vmag, B-V] * N.

Tycho-2 records are pipe-delimited. Fields used (0-based after split on '|'):
   2  mRAdeg  (mean RA J2000)     | fallback 24 = observed RAdeg
   3  mDEdeg  (mean Dec J2000)    | fallback 25 = observed DEdeg
  17  BTmag                        19  VTmag
Johnson transform (ESA/Mamajek):  V = VT - 0.090*(BT-VT) ;  B-V = 0.850*(BT-VT).

Run:  python3 tools/parse_tycho.py
"""
import glob
import gzip
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")
OUT = os.path.join(DATA, "tycho_slim.bin")


def fval(s):
    s = s.strip()
    return float(s) if s else None


def main():
    parts = sorted(glob.glob(os.path.join(DATA, "tyc2.dat.*.gz")))
    if not parts:
        print("No tyc2.dat.*.gz in", DATA)
        return
    out = open(OUT, "wb")
    pack = struct.Struct("<4f").pack
    n = 0
    skipped = 0
    for p in parts:
        with gzip.open(p, "rt") as f:
            for line in f:
                c = line.split("|")
                if len(c) < 26:
                    skipped += 1
                    continue
                ra = fval(c[2])
                dec = fval(c[3])
                if ra is None or dec is None:          # mean pos blank -> observed pos
                    ra = fval(c[24])
                    dec = fval(c[25])
                if ra is None or dec is None:
                    skipped += 1
                    continue
                bt = fval(c[17])
                vt = fval(c[19])
                if vt is None and bt is None:
                    skipped += 1
                    continue
                if vt is None:
                    vt = bt
                if bt is None:
                    bt = vt
                bv = 0.850 * (bt - vt)
                v = vt - 0.090 * (bt - vt)
                out.write(pack(ra, dec, v, bv))
                n += 1
        print("  parsed", os.path.basename(p), "-> running total", n)
    out.close()
    print("DONE. %d stars -> %s (%.1f MB), skipped %d"
          % (n, OUT, os.path.getsize(OUT) / 1e6, skipped))


if __name__ == "__main__":
    main()

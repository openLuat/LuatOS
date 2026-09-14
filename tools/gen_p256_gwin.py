# Generate P-256 fixed-base window table (k*G, k=1..15) in 8x32-bit LE limb format.
# Source A: convert BearSSL ec_p256_m31.c Gwin (30-bit limbs).
# Source B: independent pure-python ECC computation. Cross-check A == B, then emit C.

import re

P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5

def inv(x): return pow(x, P - 2, P)

def add(Pt, Qt):
    if Pt is None: return Qt
    if Qt is None: return Pt
    x1, y1 = Pt; x2, y2 = Qt
    if x1 == x2 and (y1 != y2 or y1 == 0): return None
    if Pt == Qt:
        m = (3 * x1 * x1 - 3) * inv(2 * y1) % P
    else:
        m = (y2 - y1) * inv(x2 - x1) % P
    x3 = (m * m - x1 - x2) % P
    y3 = (m * (x1 - x3) - y1) % P
    return (x3, y3)

def mul(k, Pt):
    R = None
    while k:
        if k & 1: R = add(R, Pt)
        Pt = add(Pt, Pt)
        k >>= 1
    return R

# --- Source B: python ECC ---
py_pts = [None] + [mul(k, (GX, GY)) for k in range(1, 16)]

# --- Source A: BearSSL Gwin (30-bit limbs) ---
import os, sys
BEARSSL_M31 = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("BEARSSL_M31", "ec_p256_m31.c")
src = open(BEARSSL_M31, encoding="utf-8").read()
m = re.search(r"static const uint32_t Gwin\[15\]\[18\] = \{(.*?)\n\};", src, re.S)
body = m.group(1)
rows = re.findall(r"\{([^}]*)\}", body)
assert len(rows) == 15, len(rows)

def limbs30_to_int(vals):
    v = 0
    for i, w in enumerate(vals):
        v |= w << (30 * i)
    return v

bs_pts = []
for r in rows:
    words = [int(x, 16) for x in re.findall(r"0x[0-9A-Fa-f]+", r)]
    assert len(words) == 18
    x = limbs30_to_int(words[:9])
    y = limbs30_to_int(words[9:])
    bs_pts.append((x, y))

# --- cross-check ---
for k in range(1, 16):
    a = bs_pts[k - 1]
    b = py_pts[k]
    assert a == b, f"mismatch at k={k}:\n{a}\n{b}"
print("cross-check OK: BearSSL table == python ECC, k=1..15")

# --- verify on-curve ---
for x, y in py_pts[1:]:
    assert (y * y - (x * x * x - 3 * x + B)) % P == 0
print("on-curve OK")

# --- emit C ---
def limbs32(v):
    return [(v >> (32 * i)) & 0xFFFFFFFF for i in range(8)]

lines = []
lines.append("/*")
lines.append(" * P-256 fixed-base window table: k*G (k = 1..15), affine (X, Y),")
lines.append(" * each coordinate as 8 x 32-bit little-endian limbs.")
lines.append(" *")
lines.append(" * Algorithm and table layout follow BearSSL ec_p256_m31.c (MIT license);")
lines.append(" * values regenerated and cross-checked against an independent pure-python")
lines.append(" * P-256 implementation (tools: gen_p256_gwin.py).")
lines.append(" */")
lines.append('#include "luat_p256.h"')
lines.append("")
lines.append("const uint32_t luat_p256_gwin[15][16] = {")
for k in range(1, 16):
    x, y = py_pts[k]
    wl = limbs32(x) + limbs32(y)
    lines.append("\t{ " + ", ".join(f"0x{w:08X}u" for w in wl) + " },")
lines.append("};")
lines.append("")

out = "\n".join(lines)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "components", "crypto", "p256", "p256_g_table.c")
open(OUT, "w", encoding="utf-8", newline="\n").write(out)
print("written p256_g_table.c")

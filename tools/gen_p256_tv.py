# Generate P-256 test vectors as C header for the standalone harness.
import random

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
    return (x3, (m * (x1 - x3) - y1) % P)

def mul(k, Pt):
    R = None
    while k:
        if k & 1: R = add(R, Pt)
        Pt = add(Pt, Pt)
        k >>= 1
    return R

def h(v): return v.to_bytes(32, 'big').hex()
def pt_hex(Pt): return h(Pt[0]) + h(Pt[1])

random.seed(2026)
G = (GX, GY)

mulg = []   # (k, expected_xy, expect_rc)  rc: 0 ok, -1 error
# edge scalars
edge = [1, 2, 3, 15, 16, 255, N - 1, N - 2, 0xF0F0F0F0, 1 << 128, (1 << 255) + 12345]
for k in edge:
    mulg.append((k, pt_hex(mul(k, G)), 0))
for _ in range(32):
    k = random.randrange(1, N)
    mulg.append((k, pt_hex(mul(k, G)), 0))
# invalid scalars
mulg.append((0, "", -1))
mulg.append((N, "", -1))
mulg.append((N + 1, "", -1))

# variable point mul: random P (via d*G), random k
mulv = []
for _ in range(16):
    d = random.randrange(1, N)
    Pt = mul(d, G)
    k = random.randrange(1, N)
    mulv.append((h(k), pt_hex(Pt), pt_hex(mul(k, Pt)), 0))
# edge: k=1, k=N-1 with P=G
mulv.append((h(1), pt_hex(G), pt_hex(G), 0))
mulv.append((h(N - 1), pt_hex(G), pt_hex(mul(N - 1, G)), 0))
# invalid point (x valid-ish, y not on curve)
bad = bytearray(bytes.fromhex(pt_hex(G)))
bad[63] ^= 1
mulv.append((h(3), bad.hex(), "", -1))
# point with coordinate >= p
bad2 = (P.to_bytes(32, 'big') + GY.to_bytes(32, 'big')).hex()
mulv.append((h(3), bad2, "", -1))

# muladd: (u1, u2, Q, expected)
madd = []
for _ in range(12):
    d = random.randrange(1, N)
    Q = mul(d, G)
    u1 = random.randrange(1, N)
    u2 = random.randrange(1, N)
    R = add(mul(u1, G), mul(u2, Q))
    madd.append((h(u1), h(u2), pt_hex(Q), pt_hex(R), 0))
# u1=0 / u2=0
d = random.randrange(1, N); Q = mul(d, G)
u2 = random.randrange(1, N)
madd.append((h(0), h(u2), pt_hex(Q), pt_hex(mul(u2, Q)), 0))
u1 = random.randrange(1, N)
madd.append((h(u1), h(0), pt_hex(Q), pt_hex(mul(u1, G)), 0))
# result infinity: u1*G = -(u2*Q) → pick Q=G, u2 = N-u1
madd.append((h(5), h(N - 5), pt_hex(G), "", -1))
# P1==P2 case: u1==u2, Q=G → R = 2*u1*G
madd.append((h(7), h(7), pt_hex(G), pt_hex(mul(14, G)), 0))

# ecdh pairs
ecdh = []
for _ in range(4):
    d1 = random.randrange(1, N); d2 = random.randrange(1, N)
    ecdh.append((h(d1), h(d2), pt_hex(mul(d1, mul(d2, G)))))

def emit_arr(name, rows, fmt):
    out = [f"static const tv_{name} {name}[] = {{"]
    for r in rows:
        out.append("    { " + fmt(r) + " },")
    out.append("};")
    return "\n".join(out)

def q(s): return '"' + s + '"'

hdr = []
hdr.append("typedef struct { const char *k; const char *xy; int rc; } tv_mulg;")
hdr.append("typedef struct { const char *k; const char *pt; const char *xy; int rc; } tv_mulv;")
hdr.append("typedef struct { const char *u1; const char *u2; const char *q; const char *xy; int rc; } tv_madd;")
hdr.append("typedef struct { const char *d1; const char *d2; const char *z; } tv_ecdh;")
hdr.append(emit_arr("mulg", mulg, lambda r: f"{q(h(r[0]))}, {q(r[1])}, {r[2]}"))
hdr.append(emit_arr("mulv", mulv, lambda r: f"{q(r[0])}, {q(r[1])}, {q(r[2])}, {r[3]}"))
hdr.append(emit_arr("madd", madd, lambda r: f"{q(r[0])}, {q(r[1])}, {q(r[2])}, {q(r[3])}, {r[4]}"))
hdr.append(emit_arr("ecdh", ecdh, lambda r: f"{q(r[0])}, {q(r[1])}, {q(r[2])}"))
import os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "p256_tv.h")
with open(OUT, "w", newline="\n") as f:
    f.write("\n".join(hdr) + "\n")
print(f"vectors: mulg={len(mulg)} mulv={len(mulv)} madd={len(madd)} ecdh={len(ecdh)} -> {OUT}")

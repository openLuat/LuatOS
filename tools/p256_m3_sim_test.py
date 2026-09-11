# P-256 Thumb-2 汇编内核 (p256_field_armm3.S) 的 unicorn (Cortex-M3) 仿真验证.
#
# 用法:
#   1) arm-none-eabi-gcc 交叉编译 (ASM 模式) 出 flat binary:
#        python tools/p256_m3_sim_test.py --build
#   2) 仿真执行并与纯 python P-256 参考比对:
#        python tools/p256_m3_sim_test.py
#
# 验证内容: fe_add/fe_sub/mul256 汇编原语 + 完整 luat_p256_mul_g/mul/muladd
# (整条 ASM 域路径), 随机 + 边界值, 结果对照独立 python ECC.

import os
import random
import struct
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
P256_DIR = os.path.join(SCRIPT_DIR, "..", "components", "crypto", "p256")
BUILD = os.path.join(SCRIPT_DIR, "build_m3sim")
BIN = os.path.join(BUILD, "m3sim.bin")
SYM = os.path.join(BUILD, "m3sim.sym")

GCC = "arm-none-eabi-gcc"
OBJCOPY = "arm-none-eabi-objcopy"
NM = "arm-none-eabi-nm"
BASE = 0x08000000

# ---------------- python P-256 参考 ----------------
p = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
n = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
b = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
Gx = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
Gy = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5

def pt_add(P, Q):
    if P is None: return Q
    if Q is None: return P
    x1, y1 = P; x2, y2 = Q
    if x1 == x2:
        if (y1 + y2) % p == 0: return None
        lam = (3 * x1 * x1 - 3) * pow(2 * y1, p - 2, p) % p
    else:
        lam = (y2 - y1) * pow(x2 - x1, p - 2, p) % p
    x3 = (lam * lam - x1 - x2) % p
    return (x3, (lam * (x1 - x3) - y1) % p)

def mul(k, P):
    R = None
    while k:
        if k & 1: R = pt_add(R, P)
        P = pt_add(P, P)
        k >>= 1
    return R

def limbs(v, cnt):
    return [(v >> (32 * i)) & 0xFFFFFFFF for i in range(cnt)]

# ---------------- 构建 ----------------
def build():
    os.makedirs(BUILD, exist_ok=True)
    elf = os.path.join(BUILD, "m3sim.elf")
    srcs = [os.path.join(P256_DIR, f) for f in ("p256_ct.c", "p256_g_table.c", "p256_field_armm3.S")]
    srcs.append(os.path.join(SCRIPT_DIR, "m3test_support.c"))
    cmd = [GCC, "-nostdlib", "-ffreestanding", "-O2", "-mcpu=cortex-m3", "-mthumb",
           "-DLUAT_CONF_MBEDTLS_ECP_P256_ASM=1",
           "-I", P256_DIR, "-Ttext", hex(BASE), "-Wl,-e,_start", "-o", elf] + srcs
    subprocess.check_call(cmd)
    subprocess.check_call([OBJCOPY, "-O", "binary", elf, BIN])
    out = subprocess.check_output([NM, elf], text=True)
    syms = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) == 3:
            syms[parts[2]] = int(parts[0], 16)
    with open(SYM, "w") as f:
        for k, v in syms.items():
            f.write(f"{k} {v:#x}\n")
    print("built", elf)

# ---------------- 仿真 ----------------
def run_tests():
    from unicorn import Uc, UC_ARCH_ARM, UC_MODE_THUMB
    from unicorn.arm_const import UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3
    from unicorn.arm_const import UC_ARM_REG_SP, UC_ARM_REG_LR

    code = open(BIN, "rb").read()
    syms = {}
    for line in open(SYM):
        k, v = line.split()
        syms[k] = int(v, 16)

    RAM = 0x20000000
    RAM_SIZE = 0x10000
    RET = 0xF0000000  # 返回哨兵 (LR = RET|1)

    uc = Uc(UC_ARCH_ARM, UC_MODE_THUMB)
    uc.mem_map(BASE, (len(code) + 0xFFF) & ~0xFFF)
    uc.mem_write(BASE, code)
    uc.mem_map(RAM, RAM_SIZE)
    uc.mem_map(RET, 0x1000)

    _ARGREG = (UC_ARM_REG_R0, UC_ARM_REG_R1, UC_ARM_REG_R2, UC_ARM_REG_R3)

    def call(fn, *args):
        """以 Thumb ABI 调用 fn, 返回 r0."""
        uc.reg_write(UC_ARM_REG_SP, RAM + RAM_SIZE - 16)
        for i, a in enumerate(args):
            uc.reg_write(_ARGREG[i], a)
        uc.reg_write(UC_ARM_REG_LR, RET | 1)          # lr = 哨兵
        uc.emu_start(syms[fn] | 1, RET)
        return uc.reg_read(UC_ARM_REG_R0)

    def wr_words(addr, words):
        uc.mem_write(addr, struct.pack(f"<{len(words)}I", *words))

    def rd_words(addr, cnt):
        return list(struct.unpack(f"<{cnt}I", uc.mem_read(addr, 4 * cnt)))

    A = RAM + 0x100
    B = RAM + 0x200
    D = RAM + 0x300
    C = RAM + 0x400
    K = RAM + 0x500
    P = RAM + 0x600
    Q = RAM + 0x700
    OUT = RAM + 0x800

    rng = random.Random(20260908)
    fails = 0

    def check(name, got, exp):
        nonlocal fails
        if got != exp:
            print(f"FAIL {name}: got {got!r} exp {exp!r}")
            fails += 1

    # --- fe_add / fe_sub / mul256 原语 ---
    edge = [0, 1, 2, p - 1, p - 2, p >> 1, 0xFFFFFFFF]
    vals = edge + [rng.randrange(p) for _ in range(200)]
    for i in range(200):
        a = rng.choice(vals)
        bb = rng.choice(vals)
        wr_words(A, limbs(a, 8))
        wr_words(B, limbs(bb, 8))
        call("p256_fe_add_m3", D, A, B)
        check(f"fe_add#{i}", int.from_bytes(struct.pack("<8I", *rd_words(D, 8)), "little"), (a + bb) % p)
        call("p256_fe_sub_m3", D, A, B)
        check(f"fe_sub#{i}", int.from_bytes(struct.pack("<8I", *rd_words(D, 8)), "little"), (a - bb) % p)
        wr_words(C, [0] * 16)
        call("p256_mul256_m3", C, A, B)
        check(f"mul256#{i}", int.from_bytes(struct.pack("<16I", *rd_words(C, 16)), "little"), a * bb)

    # --- 完整标量乘 (ASM 域路径) ---
    scalars = [1, 2, 3, 15, 16, 255, n - 1, n - 2] + [rng.randrange(1, n) for _ in range(40)]
    for i, k in enumerate(scalars):
        R = mul(k, (Gx, Gy))
        uc.mem_write(K, k.to_bytes(32, "big"))
        rc = call("luat_p256_mul_g", OUT, K)
        check(f"mulg_rc#{i}", rc, 0)
        x = int.from_bytes(uc.mem_read(OUT, 32), "big")
        y = int.from_bytes(uc.mem_read(OUT + 32, 32), "big")
        check(f"mulg#{i}", (x, y), R)

        # 变基点: P2 = k2*G, R2 = k*P2
        k2 = rng.randrange(1, n)
        P2 = mul(k2, (Gx, Gy))
        R2 = mul(k, P2)
        uc.mem_write(K, k.to_bytes(32, "big"))
        uc.mem_write(P, P2[0].to_bytes(32, "big") + P2[1].to_bytes(32, "big"))
        rc = call("luat_p256_mul", OUT, K, P)
        check(f"mul_rc#{i}", rc, 0)
        x = int.from_bytes(uc.mem_read(OUT, 32), "big")
        y = int.from_bytes(uc.mem_read(OUT + 32, 32), "big")
        check(f"mul#{i}", (x, y), R2)

        # muladd
        u1, u2 = rng.randrange(1, n), rng.randrange(1, n)
        R3 = pt_add(mul(u1, (Gx, Gy)), mul(u2, P2))
        uc.mem_write(K, u1.to_bytes(32, "big"))
        uc.mem_write(Q, u2.to_bytes(32, "big"))
        rc = call("luat_p256_muladd", OUT, K, Q, P)
        check(f"madd_rc#{i}", rc, 0)
        x = int.from_bytes(uc.mem_read(OUT, 32), "big")
        y = int.from_bytes(uc.mem_read(OUT + 32, 32), "big")
        check(f"madd#{i}", (x, y), R3)

    # --- 非法输入 ---
    uc.mem_write(K, (0).to_bytes(32, "big"))
    check("k=0", call("luat_p256_mul_g", OUT, K), -1 & 0xFFFFFFFF)
    uc.mem_write(K, n.to_bytes(32, "big"))
    check("k=n", call("luat_p256_mul_g", OUT, K), -1 & 0xFFFFFFFF)
    uc.mem_write(K, (1).to_bytes(32, "big"))
    bad = bytearray(Gx.to_bytes(32, "big") + Gy.to_bytes(32, "big"))
    bad[63] ^= 1
    uc.mem_write(P, bytes(bad))
    check("badpt", call("luat_p256_mul", OUT, K, P), -1 & 0xFFFFFFFF)

    print(f"RESULT: {'ALL PASS' if fails == 0 else f'{fails} FAILURES'}")
    return fails

if __name__ == "__main__":
    if "--build" in sys.argv or not os.path.exists(BIN):
        build()
    sys.exit(1 if run_tests() else 0)

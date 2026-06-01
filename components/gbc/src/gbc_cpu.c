/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#include "gbc.h"

#define CPU_A(cpu)       ((cpu)->af.hi)
#define CPU_F(cpu)       ((cpu)->af.lo)
#define CPU_B(cpu)       ((cpu)->bc.hi)
#define CPU_C(cpu)       ((cpu)->bc.lo)
#define CPU_D(cpu)       ((cpu)->de.hi)
#define CPU_E(cpu)       ((cpu)->de.lo)
#define CPU_H(cpu)       ((cpu)->hl.hi)
#define CPU_L(cpu)       ((cpu)->hl.lo)

GBC_INLINE uint8_t cpu_read8(gbc_t *gbc)
{
    uint8_t value = gbc_mmu_read(gbc, gbc->cpu.pc);

    if (gbc->cpu.halt_bug) {
        gbc->cpu.halt_bug = 0;
    } else {
        gbc->cpu.pc++;
    }
    return value;
}

GBC_INLINE uint16_t cpu_read16(gbc_t *gbc)
{
    uint8_t lo = cpu_read8(gbc);
    uint8_t hi = cpu_read8(gbc);
    return (uint16_t)(lo | (hi << 8));
}

GBC_INLINE void cpu_push16(gbc_t *gbc, uint16_t value)
{
    gbc->cpu.sp--;
    gbc_mmu_write(gbc, gbc->cpu.sp, (uint8_t)(value >> 8));
    gbc->cpu.sp--;
    gbc_mmu_write(gbc, gbc->cpu.sp, (uint8_t)value);
}

GBC_INLINE uint16_t cpu_pop16(gbc_t *gbc)
{
    uint8_t lo = gbc_mmu_read(gbc, gbc->cpu.sp++);
    uint8_t hi = gbc_mmu_read(gbc, gbc->cpu.sp++);
    return (uint16_t)(lo | (hi << 8));
}

GBC_INLINE uint8_t cpu_get_r(gbc_t *gbc, uint8_t r)
{
    switch (r & 7) {
    case 0: return CPU_B(&gbc->cpu);
    case 1: return CPU_C(&gbc->cpu);
    case 2: return CPU_D(&gbc->cpu);
    case 3: return CPU_E(&gbc->cpu);
    case 4: return CPU_H(&gbc->cpu);
    case 5: return CPU_L(&gbc->cpu);
    case 6: return gbc_mmu_read(gbc, gbc->cpu.hl.w);
    default: return CPU_A(&gbc->cpu);
    }
}

GBC_INLINE void cpu_set_r(gbc_t *gbc, uint8_t r, uint8_t value)
{
    switch (r & 7) {
    case 0: CPU_B(&gbc->cpu) = value; break;
    case 1: CPU_C(&gbc->cpu) = value; break;
    case 2: CPU_D(&gbc->cpu) = value; break;
    case 3: CPU_E(&gbc->cpu) = value; break;
    case 4: CPU_H(&gbc->cpu) = value; break;
    case 5: CPU_L(&gbc->cpu) = value; break;
    case 6: gbc_mmu_write(gbc, gbc->cpu.hl.w, value); break;
    default: CPU_A(&gbc->cpu) = value; break;
    }
}

GBC_INLINE void cpu_set_flags(gbc_t *gbc, uint8_t z, uint8_t n, uint8_t h, uint8_t c)
{
    uint8_t f = 0;
    if (z) f |= GBC_FLAG_Z;
    if (n) f |= GBC_FLAG_N;
    if (h) f |= GBC_FLAG_H;
    if (c) f |= GBC_FLAG_C;
    CPU_F(&gbc->cpu) = f;
}

GBC_INLINE void cpu_add(gbc_t *gbc, uint8_t value, uint8_t carry)
{
    uint8_t a = CPU_A(&gbc->cpu);
    uint16_t result = (uint16_t)a + value + carry;
    cpu_set_flags(gbc, (uint8_t)result == 0, 0, ((a & 0x0F) + (value & 0x0F) + carry) > 0x0F, result > 0xFF);
    CPU_A(&gbc->cpu) = (uint8_t)result;
}

GBC_INLINE void cpu_sub(gbc_t *gbc, uint8_t value, uint8_t carry)
{
    uint8_t a = CPU_A(&gbc->cpu);
    uint16_t result = (uint16_t)a - value - carry;
    cpu_set_flags(gbc, (uint8_t)result == 0, 1, (a & 0x0F) < ((value & 0x0F) + carry), a < (uint16_t)(value + carry));
    CPU_A(&gbc->cpu) = (uint8_t)result;
}

GBC_INLINE void cpu_and(gbc_t *gbc, uint8_t value)
{
    CPU_A(&gbc->cpu) &= value;
    cpu_set_flags(gbc, CPU_A(&gbc->cpu) == 0, 0, 1, 0);
}

GBC_INLINE void cpu_xor(gbc_t *gbc, uint8_t value)
{
    CPU_A(&gbc->cpu) ^= value;
    cpu_set_flags(gbc, CPU_A(&gbc->cpu) == 0, 0, 0, 0);
}

GBC_INLINE void cpu_or(gbc_t *gbc, uint8_t value)
{
    CPU_A(&gbc->cpu) |= value;
    cpu_set_flags(gbc, CPU_A(&gbc->cpu) == 0, 0, 0, 0);
}

GBC_INLINE void cpu_cp(gbc_t *gbc, uint8_t value)
{
    uint8_t a = CPU_A(&gbc->cpu);
    uint16_t result = (uint16_t)a - value;
    cpu_set_flags(gbc, (uint8_t)result == 0, 1, (a & 0x0F) < (value & 0x0F), a < value);
}

GBC_INLINE uint8_t cpu_inc8(gbc_t *gbc, uint8_t value)
{
    uint8_t result = (uint8_t)(value + 1);
    uint8_t c = CPU_F(&gbc->cpu) & GBC_FLAG_C;
    cpu_set_flags(gbc, result == 0, 0, ((value & 0x0F) + 1) > 0x0F, c != 0);
    return result;
}

GBC_INLINE uint8_t cpu_dec8(gbc_t *gbc, uint8_t value)
{
    uint8_t result = (uint8_t)(value - 1);
    uint8_t c = CPU_F(&gbc->cpu) & GBC_FLAG_C;
    cpu_set_flags(gbc, result == 0, 1, (value & 0x0F) == 0, c != 0);
    return result;
}

GBC_INLINE void cpu_add_hl(gbc_t *gbc, uint16_t value)
{
    uint32_t result = (uint32_t)gbc->cpu.hl.w + value;
    uint8_t z = CPU_F(&gbc->cpu) & GBC_FLAG_Z;
    cpu_set_flags(gbc, z != 0, 0, ((gbc->cpu.hl.w & 0x0FFF) + (value & 0x0FFF)) > 0x0FFF, result > 0xFFFF);
    gbc->cpu.hl.w = (uint16_t)result;
}

GBC_INLINE uint8_t cpu_condition(gbc_t *gbc, uint8_t cc)
{
    uint8_t f = CPU_F(&gbc->cpu);
    switch (cc & 3) {
    case 0: return (f & GBC_FLAG_Z) == 0;
    case 1: return (f & GBC_FLAG_Z) != 0;
    case 2: return (f & GBC_FLAG_C) == 0;
    default: return (f & GBC_FLAG_C) != 0;
    }
}

static uint8_t cpu_cb(gbc_t *gbc)
{
    uint8_t op = cpu_read8(gbc);
    uint8_t r = op & 7;
    uint8_t x = op >> 6;
    uint8_t y = (op >> 3) & 7;
    uint8_t value = cpu_get_r(gbc, r);
    uint8_t carry = 0;
    uint8_t result = value;

    if (x == 0) {
        switch (y) {
        case 0:
            carry = (value >> 7) & 1;
            result = (uint8_t)((value << 1) | carry);
            break;
        case 1:
            carry = value & 1;
            result = (uint8_t)((value >> 1) | (carry << 7));
            break;
        case 2:
            carry = (value >> 7) & 1;
            result = (uint8_t)((value << 1) | ((CPU_F(&gbc->cpu) & GBC_FLAG_C) ? 1 : 0));
            break;
        case 3:
            carry = value & 1;
            result = (uint8_t)((value >> 1) | ((CPU_F(&gbc->cpu) & GBC_FLAG_C) ? 0x80 : 0));
            break;
        case 4:
            carry = (value >> 7) & 1;
            result = (uint8_t)(value << 1);
            break;
        case 5:
            carry = value & 1;
            result = (uint8_t)((value >> 1) | (value & 0x80));
            break;
        case 6:
            result = (uint8_t)((value << 4) | (value >> 4));
            carry = 0;
            break;
        default:
            carry = value & 1;
            result = (uint8_t)(value >> 1);
            break;
        }
        cpu_set_r(gbc, r, result);
        cpu_set_flags(gbc, result == 0, 0, 0, carry);
    } else if (x == 1) {
        cpu_set_flags(gbc, (value & (1U << y)) == 0, 0, 1, (CPU_F(&gbc->cpu) & GBC_FLAG_C) != 0);
    } else if (x == 2) {
        cpu_set_r(gbc, r, (uint8_t)(value & ~(1U << y)));
    } else {
        cpu_set_r(gbc, r, (uint8_t)(value | (1U << y)));
    }
    return (r == 6) ? 16 : 8;
}

static uint8_t cpu_service_interrupt(gbc_t *gbc)
{
    static const uint16_t vectors[5] = {0x40, 0x48, 0x50, 0x58, 0x60};
    uint8_t pending = (uint8_t)(gbc->mmu.ie & gbc->mmu.io[0x0F] & 0x1F);

    if (pending == 0) {
        return 0;
    }
    gbc->cpu.halted = 0;
    if (!gbc->cpu.ime) {
        return 0;
    }

    for (uint8_t i = 0; i < 5; i++) {
        if (pending & (1U << i)) {
            gbc->cpu.ime = 0;
            gbc->mmu.io[0x0F] &= (uint8_t)~(1U << i);
            cpu_push16(gbc, gbc->cpu.pc);
            gbc->cpu.pc = vectors[i];
            return 20;
        }
    }
    return 0;
}

void gbc_cpu_reset(gbc_t *gbc)
{
    gbc_cpu_t *cpu = &gbc->cpu;

    gbc_memset(cpu, 0, sizeof(*cpu));
    if (gbc->model == GBC_MODEL_CGB) {
        cpu->af.w = 0x1180;
        cpu->bc.w = 0x0000;
        cpu->de.w = 0xFF56;
        cpu->hl.w = 0x000D;
    } else {
        cpu->af.w = 0x01B0;
        cpu->bc.w = 0x0013;
        cpu->de.w = 0x00D8;
        cpu->hl.w = 0x014D;
    }
    cpu->sp = 0xFFFE;
    cpu->pc = 0x0100;
}

void gbc_cpu_request_interrupt(gbc_t *gbc, uint8_t bit)
{
    gbc_mmu_request_interrupt(gbc, (uint8_t)(1U << bit));
}

uint8_t gbc_cpu_step(gbc_t *gbc)
{
    gbc_cpu_t *cpu = &gbc->cpu;
    uint8_t delayed_ime = cpu->ime_delay;
    uint8_t op;
    uint8_t cycles = cpu_service_interrupt(gbc);

    if (cycles != 0) {
        cpu->cycles += cycles;
        return cycles;
    }
    if (cpu->halted) {
        cpu->cycles += 4;
        return 4;
    }

    cpu->ime_delay = 0;
    op = cpu_read8(gbc);
    cpu->last_opcode = op;

    if (op >= 0x40 && op <= 0x7F) {
        if (op == 0x76) {
            uint8_t pending = (uint8_t)(gbc->mmu.ie & gbc->mmu.io[0x0F] & 0x1F);
            if (!cpu->ime && pending != 0) {
                cpu->halt_bug = 1;
            } else {
                cpu->halted = 1;
            }
            cycles = 4;
        } else {
            uint8_t dst = (uint8_t)((op >> 3) & 7);
            uint8_t src = op & 7;
            cpu_set_r(gbc, dst, cpu_get_r(gbc, src));
            cycles = (src == 6 || dst == 6) ? 8 : 4;
        }
    } else if (op >= 0x80 && op <= 0xBF) {
        uint8_t src = op & 7;
        uint8_t alu = (uint8_t)((op >> 3) & 7);
        uint8_t value = cpu_get_r(gbc, src);
        switch (alu) {
        case 0: cpu_add(gbc, value, 0); break;
        case 1: cpu_add(gbc, value, (CPU_F(cpu) & GBC_FLAG_C) ? 1 : 0); break;
        case 2: cpu_sub(gbc, value, 0); break;
        case 3: cpu_sub(gbc, value, (CPU_F(cpu) & GBC_FLAG_C) ? 1 : 0); break;
        case 4: cpu_and(gbc, value); break;
        case 5: cpu_xor(gbc, value); break;
        case 6: cpu_or(gbc, value); break;
        default: cpu_cp(gbc, value); break;
        }
        cycles = (src == 6) ? 8 : 4;
    } else {
        switch (op) {
        case 0x00: cycles = 4; break;
        case 0x01: cpu->bc.w = cpu_read16(gbc); cycles = 12; break;
        case 0x02: gbc_mmu_write(gbc, cpu->bc.w, CPU_A(cpu)); cycles = 8; break;
        case 0x03: cpu->bc.w++; cycles = 8; break;
        case 0x04: CPU_B(cpu) = cpu_inc8(gbc, CPU_B(cpu)); cycles = 4; break;
        case 0x05: CPU_B(cpu) = cpu_dec8(gbc, CPU_B(cpu)); cycles = 4; break;
        case 0x06: CPU_B(cpu) = cpu_read8(gbc); cycles = 8; break;
        case 0x07: { uint8_t c = (CPU_A(cpu) >> 7) & 1; CPU_A(cpu) = (uint8_t)((CPU_A(cpu) << 1) | c); cpu_set_flags(gbc, 0, 0, 0, c); cycles = 4; break; }
        case 0x08: { uint16_t a = cpu_read16(gbc); gbc_mmu_write(gbc, a, (uint8_t)cpu->sp); gbc_mmu_write(gbc, (uint16_t)(a + 1), (uint8_t)(cpu->sp >> 8)); cycles = 20; break; }
        case 0x09: cpu_add_hl(gbc, cpu->bc.w); cycles = 8; break;
        case 0x0A: CPU_A(cpu) = gbc_mmu_read(gbc, cpu->bc.w); cycles = 8; break;
        case 0x0B: cpu->bc.w--; cycles = 8; break;
        case 0x0C: CPU_C(cpu) = cpu_inc8(gbc, CPU_C(cpu)); cycles = 4; break;
        case 0x0D: CPU_C(cpu) = cpu_dec8(gbc, CPU_C(cpu)); cycles = 4; break;
        case 0x0E: CPU_C(cpu) = cpu_read8(gbc); cycles = 8; break;
        case 0x0F: { uint8_t c = CPU_A(cpu) & 1; CPU_A(cpu) = (uint8_t)((CPU_A(cpu) >> 1) | (c << 7)); cpu_set_flags(gbc, 0, 0, 0, c); cycles = 4; break; }
        case 0x10:
            cpu_read8(gbc);
            if (gbc->model == GBC_MODEL_CGB && gbc->mmu.speed_prepare) {
                gbc->mmu.double_speed ^= 1;
                gbc->mmu.speed_prepare = 0;
            }
            cycles = 4;
            break;
        case 0x11: cpu->de.w = cpu_read16(gbc); cycles = 12; break;
        case 0x12: gbc_mmu_write(gbc, cpu->de.w, CPU_A(cpu)); cycles = 8; break;
        case 0x13: cpu->de.w++; cycles = 8; break;
        case 0x14: CPU_D(cpu) = cpu_inc8(gbc, CPU_D(cpu)); cycles = 4; break;
        case 0x15: CPU_D(cpu) = cpu_dec8(gbc, CPU_D(cpu)); cycles = 4; break;
        case 0x16: CPU_D(cpu) = cpu_read8(gbc); cycles = 8; break;
        case 0x17: { uint8_t oldc = (CPU_F(cpu) & GBC_FLAG_C) ? 1 : 0; uint8_t c = (CPU_A(cpu) >> 7) & 1; CPU_A(cpu) = (uint8_t)((CPU_A(cpu) << 1) | oldc); cpu_set_flags(gbc, 0, 0, 0, c); cycles = 4; break; }
        case 0x18: cpu->pc = (uint16_t)(cpu->pc + (int8_t)cpu_read8(gbc)); cycles = 12; break;
        case 0x19: cpu_add_hl(gbc, cpu->de.w); cycles = 8; break;
        case 0x1A: CPU_A(cpu) = gbc_mmu_read(gbc, cpu->de.w); cycles = 8; break;
        case 0x1B: cpu->de.w--; cycles = 8; break;
        case 0x1C: CPU_E(cpu) = cpu_inc8(gbc, CPU_E(cpu)); cycles = 4; break;
        case 0x1D: CPU_E(cpu) = cpu_dec8(gbc, CPU_E(cpu)); cycles = 4; break;
        case 0x1E: CPU_E(cpu) = cpu_read8(gbc); cycles = 8; break;
        case 0x1F: { uint8_t oldc = (CPU_F(cpu) & GBC_FLAG_C) ? 0x80 : 0; uint8_t c = CPU_A(cpu) & 1; CPU_A(cpu) = (uint8_t)((CPU_A(cpu) >> 1) | oldc); cpu_set_flags(gbc, 0, 0, 0, c); cycles = 4; break; }
        case 0x20: { int8_t e = (int8_t)cpu_read8(gbc); if ((CPU_F(cpu) & GBC_FLAG_Z) == 0) { cpu->pc = (uint16_t)(cpu->pc + e); cycles = 12; } else cycles = 8; break; }
        case 0x21: cpu->hl.w = cpu_read16(gbc); cycles = 12; break;
        case 0x22: gbc_mmu_write(gbc, cpu->hl.w++, CPU_A(cpu)); cycles = 8; break;
        case 0x23: cpu->hl.w++; cycles = 8; break;
        case 0x24: CPU_H(cpu) = cpu_inc8(gbc, CPU_H(cpu)); cycles = 4; break;
        case 0x25: CPU_H(cpu) = cpu_dec8(gbc, CPU_H(cpu)); cycles = 4; break;
        case 0x26: CPU_H(cpu) = cpu_read8(gbc); cycles = 8; break;
        case 0x27: {
            uint8_t a = CPU_A(cpu);
            uint8_t adjust = 0;
            uint8_t c = CPU_F(cpu) & GBC_FLAG_C;
            if ((CPU_F(cpu) & GBC_FLAG_H) || (!(CPU_F(cpu) & GBC_FLAG_N) && (a & 0x0F) > 9)) adjust |= 0x06;
            if (c || (!(CPU_F(cpu) & GBC_FLAG_N) && a > 0x99)) { adjust |= 0x60; c = GBC_FLAG_C; }
            CPU_A(cpu) = (CPU_F(cpu) & GBC_FLAG_N) ? (uint8_t)(a - adjust) : (uint8_t)(a + adjust);
            CPU_F(cpu) = (uint8_t)((CPU_A(cpu) == 0 ? GBC_FLAG_Z : 0) | (CPU_F(cpu) & GBC_FLAG_N) | c);
            cycles = 4;
            break;
        }
        case 0x28: { int8_t e = (int8_t)cpu_read8(gbc); if (CPU_F(cpu) & GBC_FLAG_Z) { cpu->pc = (uint16_t)(cpu->pc + e); cycles = 12; } else cycles = 8; break; }
        case 0x29: cpu_add_hl(gbc, cpu->hl.w); cycles = 8; break;
        case 0x2A: CPU_A(cpu) = gbc_mmu_read(gbc, cpu->hl.w++); cycles = 8; break;
        case 0x2B: cpu->hl.w--; cycles = 8; break;
        case 0x2C: CPU_L(cpu) = cpu_inc8(gbc, CPU_L(cpu)); cycles = 4; break;
        case 0x2D: CPU_L(cpu) = cpu_dec8(gbc, CPU_L(cpu)); cycles = 4; break;
        case 0x2E: CPU_L(cpu) = cpu_read8(gbc); cycles = 8; break;
        case 0x2F: CPU_A(cpu) ^= 0xFF; CPU_F(cpu) = (uint8_t)((CPU_F(cpu) & (GBC_FLAG_Z | GBC_FLAG_C)) | GBC_FLAG_N | GBC_FLAG_H); cycles = 4; break;
        case 0x30: { int8_t e = (int8_t)cpu_read8(gbc); if ((CPU_F(cpu) & GBC_FLAG_C) == 0) { cpu->pc = (uint16_t)(cpu->pc + e); cycles = 12; } else cycles = 8; break; }
        case 0x31: cpu->sp = cpu_read16(gbc); cycles = 12; break;
        case 0x32: gbc_mmu_write(gbc, cpu->hl.w--, CPU_A(cpu)); cycles = 8; break;
        case 0x33: cpu->sp++; cycles = 8; break;
        case 0x34: { uint8_t v = gbc_mmu_read(gbc, cpu->hl.w); gbc_mmu_write(gbc, cpu->hl.w, cpu_inc8(gbc, v)); cycles = 12; break; }
        case 0x35: { uint8_t v = gbc_mmu_read(gbc, cpu->hl.w); gbc_mmu_write(gbc, cpu->hl.w, cpu_dec8(gbc, v)); cycles = 12; break; }
        case 0x36: gbc_mmu_write(gbc, cpu->hl.w, cpu_read8(gbc)); cycles = 12; break;
        case 0x37: CPU_F(cpu) = (uint8_t)((CPU_F(cpu) & GBC_FLAG_Z) | GBC_FLAG_C); cycles = 4; break;
        case 0x38: { int8_t e = (int8_t)cpu_read8(gbc); if (CPU_F(cpu) & GBC_FLAG_C) { cpu->pc = (uint16_t)(cpu->pc + e); cycles = 12; } else cycles = 8; break; }
        case 0x39: cpu_add_hl(gbc, cpu->sp); cycles = 8; break;
        case 0x3A: CPU_A(cpu) = gbc_mmu_read(gbc, cpu->hl.w--); cycles = 8; break;
        case 0x3B: cpu->sp--; cycles = 8; break;
        case 0x3C: CPU_A(cpu) = cpu_inc8(gbc, CPU_A(cpu)); cycles = 4; break;
        case 0x3D: CPU_A(cpu) = cpu_dec8(gbc, CPU_A(cpu)); cycles = 4; break;
        case 0x3E: CPU_A(cpu) = cpu_read8(gbc); cycles = 8; break;
        case 0x3F: CPU_F(cpu) = (uint8_t)((CPU_F(cpu) & GBC_FLAG_Z) | ((CPU_F(cpu) & GBC_FLAG_C) ? 0 : GBC_FLAG_C)); cycles = 4; break;
        case 0xC0: if ((CPU_F(cpu) & GBC_FLAG_Z) == 0) { cpu->pc = cpu_pop16(gbc); cycles = 20; } else cycles = 8; break;
        case 0xC1: cpu->bc.w = cpu_pop16(gbc); cycles = 12; break;
        case 0xC2: { uint16_t a = cpu_read16(gbc); if ((CPU_F(cpu) & GBC_FLAG_Z) == 0) { cpu->pc = a; cycles = 16; } else cycles = 12; break; }
        case 0xC3: cpu->pc = cpu_read16(gbc); cycles = 16; break;
        case 0xC4: { uint16_t a = cpu_read16(gbc); if ((CPU_F(cpu) & GBC_FLAG_Z) == 0) { cpu_push16(gbc, cpu->pc); cpu->pc = a; cycles = 24; } else cycles = 12; break; }
        case 0xC5: cpu_push16(gbc, cpu->bc.w); cycles = 16; break;
        case 0xC6: cpu_add(gbc, cpu_read8(gbc), 0); cycles = 8; break;
        case 0xC7: cpu_push16(gbc, cpu->pc); cpu->pc = 0x00; cycles = 16; break;
        case 0xC8: if (CPU_F(cpu) & GBC_FLAG_Z) { cpu->pc = cpu_pop16(gbc); cycles = 20; } else cycles = 8; break;
        case 0xC9: cpu->pc = cpu_pop16(gbc); cycles = 16; break;
        case 0xCA: { uint16_t a = cpu_read16(gbc); if (CPU_F(cpu) & GBC_FLAG_Z) { cpu->pc = a; cycles = 16; } else cycles = 12; break; }
        case 0xCB: cycles = cpu_cb(gbc); break;
        case 0xCC: { uint16_t a = cpu_read16(gbc); if (CPU_F(cpu) & GBC_FLAG_Z) { cpu_push16(gbc, cpu->pc); cpu->pc = a; cycles = 24; } else cycles = 12; break; }
        case 0xCD: { uint16_t a = cpu_read16(gbc); cpu_push16(gbc, cpu->pc); cpu->pc = a; cycles = 24; break; }
        case 0xCE: cpu_add(gbc, cpu_read8(gbc), (CPU_F(cpu) & GBC_FLAG_C) ? 1 : 0); cycles = 8; break;
        case 0xCF: cpu_push16(gbc, cpu->pc); cpu->pc = 0x08; cycles = 16; break;
        case 0xD0: if ((CPU_F(cpu) & GBC_FLAG_C) == 0) { cpu->pc = cpu_pop16(gbc); cycles = 20; } else cycles = 8; break;
        case 0xD1: cpu->de.w = cpu_pop16(gbc); cycles = 12; break;
        case 0xD2: { uint16_t a = cpu_read16(gbc); if ((CPU_F(cpu) & GBC_FLAG_C) == 0) { cpu->pc = a; cycles = 16; } else cycles = 12; break; }
        case 0xD4: { uint16_t a = cpu_read16(gbc); if ((CPU_F(cpu) & GBC_FLAG_C) == 0) { cpu_push16(gbc, cpu->pc); cpu->pc = a; cycles = 24; } else cycles = 12; break; }
        case 0xD5: cpu_push16(gbc, cpu->de.w); cycles = 16; break;
        case 0xD6: cpu_sub(gbc, cpu_read8(gbc), 0); cycles = 8; break;
        case 0xD7: cpu_push16(gbc, cpu->pc); cpu->pc = 0x10; cycles = 16; break;
        case 0xD8: if (CPU_F(cpu) & GBC_FLAG_C) { cpu->pc = cpu_pop16(gbc); cycles = 20; } else cycles = 8; break;
        case 0xD9: cpu->pc = cpu_pop16(gbc); cpu->ime = 1; cycles = 16; break;
        case 0xDA: { uint16_t a = cpu_read16(gbc); if (CPU_F(cpu) & GBC_FLAG_C) { cpu->pc = a; cycles = 16; } else cycles = 12; break; }
        case 0xDC: { uint16_t a = cpu_read16(gbc); if (CPU_F(cpu) & GBC_FLAG_C) { cpu_push16(gbc, cpu->pc); cpu->pc = a; cycles = 24; } else cycles = 12; break; }
        case 0xDE: cpu_sub(gbc, cpu_read8(gbc), (CPU_F(cpu) & GBC_FLAG_C) ? 1 : 0); cycles = 8; break;
        case 0xDF: cpu_push16(gbc, cpu->pc); cpu->pc = 0x18; cycles = 16; break;
        case 0xE0: gbc_mmu_write(gbc, (uint16_t)(0xFF00 | cpu_read8(gbc)), CPU_A(cpu)); cycles = 12; break;
        case 0xE1: cpu->hl.w = cpu_pop16(gbc); cycles = 12; break;
        case 0xE2: gbc_mmu_write(gbc, (uint16_t)(0xFF00 | CPU_C(cpu)), CPU_A(cpu)); cycles = 8; break;
        case 0xE5: cpu_push16(gbc, cpu->hl.w); cycles = 16; break;
        case 0xE6: cpu_and(gbc, cpu_read8(gbc)); cycles = 8; break;
        case 0xE7: cpu_push16(gbc, cpu->pc); cpu->pc = 0x20; cycles = 16; break;
        case 0xE8: { int8_t e = (int8_t)cpu_read8(gbc); uint16_t sp = cpu->sp; cpu->sp = (uint16_t)(sp + e); cpu_set_flags(gbc, 0, 0, ((sp & 0x0F) + (e & 0x0F)) > 0x0F, ((sp & 0xFF) + (e & 0xFF)) > 0xFF); cycles = 16; break; }
        case 0xE9: cpu->pc = cpu->hl.w; cycles = 4; break;
        case 0xEA: gbc_mmu_write(gbc, cpu_read16(gbc), CPU_A(cpu)); cycles = 16; break;
        case 0xEE: cpu_xor(gbc, cpu_read8(gbc)); cycles = 8; break;
        case 0xEF: cpu_push16(gbc, cpu->pc); cpu->pc = 0x28; cycles = 16; break;
        case 0xF0: CPU_A(cpu) = gbc_mmu_read(gbc, (uint16_t)(0xFF00 | cpu_read8(gbc))); cycles = 12; break;
        case 0xF1: cpu->af.w = cpu_pop16(gbc); CPU_F(cpu) &= 0xF0; cycles = 12; break;
        case 0xF2: CPU_A(cpu) = gbc_mmu_read(gbc, (uint16_t)(0xFF00 | CPU_C(cpu))); cycles = 8; break;
        case 0xF3: cpu->ime = 0; cpu->ime_delay = 0; cycles = 4; break;
        case 0xF5: cpu_push16(gbc, cpu->af.w); cycles = 16; break;
        case 0xF6: cpu_or(gbc, cpu_read8(gbc)); cycles = 8; break;
        case 0xF7: cpu_push16(gbc, cpu->pc); cpu->pc = 0x30; cycles = 16; break;
        case 0xF8: { int8_t e = (int8_t)cpu_read8(gbc); uint16_t sp = cpu->sp; cpu->hl.w = (uint16_t)(sp + e); cpu_set_flags(gbc, 0, 0, ((sp & 0x0F) + (e & 0x0F)) > 0x0F, ((sp & 0xFF) + (e & 0xFF)) > 0xFF); cycles = 12; break; }
        case 0xF9: cpu->sp = cpu->hl.w; cycles = 8; break;
        case 0xFA: CPU_A(cpu) = gbc_mmu_read(gbc, cpu_read16(gbc)); cycles = 16; break;
        case 0xFB: cpu->ime_delay = 1; cycles = 4; break;
        case 0xFE: cpu_cp(gbc, cpu_read8(gbc)); cycles = 8; break;
        case 0xFF: cpu_push16(gbc, cpu->pc); cpu->pc = 0x38; cycles = 16; break;
        default:
            if ((op & 0xC7) == 0xC7) {
                cpu_push16(gbc, cpu->pc);
                cpu->pc = (uint16_t)(op & 0x38);
                cycles = 16;
            } else if ((op & 0xE7) == 0x20) {
                int8_t e = (int8_t)cpu_read8(gbc);
                if (cpu_condition(gbc, (op >> 3) & 3)) {
                    cpu->pc = (uint16_t)(cpu->pc + e);
                    cycles = 12;
                } else {
                    cycles = 8;
                }
            } else {
                GBC_LOG_DEBUG("unimplemented opcode 0x%02X at 0x%04X\n", op, (unsigned)(cpu->pc - 1));
                cycles = 4;
            }
            break;
        }
    }

    if (delayed_ime) {
        cpu->ime = 1;
    }
    cpu->cycles += cycles;
    CPU_F(cpu) &= 0xF0;
    return cycles;
}


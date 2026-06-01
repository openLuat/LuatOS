/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#pragma once

#include "gbc_default.h"

#ifdef __cplusplus
    extern "C" {
#endif

#define GBC_FLAG_Z                 (0x80)
#define GBC_FLAG_N                 (0x40)
#define GBC_FLAG_H                 (0x20)
#define GBC_FLAG_C                 (0x10)

typedef union {
    struct {
#if defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
        uint8_t hi;
        uint8_t lo;
#else
        uint8_t lo;
        uint8_t hi;
#endif
    };
    uint16_t w;
} gbc_reg16_t;

typedef struct {
    gbc_reg16_t af;
    gbc_reg16_t bc;
    gbc_reg16_t de;
    gbc_reg16_t hl;
    uint16_t sp;
    uint16_t pc;
    uint8_t ime;
    uint8_t ime_delay;
    uint8_t halted;
    uint8_t halt_bug;
    uint8_t stopped;
    uint8_t last_opcode;
    uint32_t cycles;
} gbc_cpu_t;

struct gbc;

void gbc_cpu_reset(struct gbc *gbc);
uint8_t gbc_cpu_step(struct gbc *gbc);
void gbc_cpu_request_interrupt(struct gbc *gbc, uint8_t bit);

static inline uint8_t gbc_cpu_get_f(gbc_cpu_t *cpu)
{
    return cpu->af.lo & 0xF0;
}

static inline void gbc_cpu_set_f(gbc_cpu_t *cpu, uint8_t f)
{
    cpu->af.lo = f & 0xF0;
}

#ifdef __cplusplus
    }
#endif


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

#define GBC_IF_VBLANK               (0x01)
#define GBC_IF_LCD                  (0x02)
#define GBC_IF_TIMER                (0x04)
#define GBC_IF_SERIAL               (0x08)
#define GBC_IF_JOYPAD               (0x10)

typedef struct {
    uint8_t vram[2][0x2000];
    uint8_t wram[8][0x1000];
    uint8_t oam[0xA0];
    uint8_t io[0x80];
    uint8_t hram[0x7F];
    uint8_t ie;
    uint8_t vram_bank;
    uint8_t wram_bank;
    uint8_t double_speed;
    uint8_t speed_prepare;
    uint16_t hdma_src;
    uint16_t hdma_dst;
    uint8_t hdma_blocks;
    uint8_t hdma_active;
    uint16_t oam_dma_cycles;
    uint16_t serial_cycles;
} gbc_mmu_t;

struct gbc;

void gbc_mmu_reset(struct gbc *gbc);
uint8_t gbc_mmu_read(struct gbc *gbc, uint16_t addr);
void gbc_mmu_write(struct gbc *gbc, uint16_t addr, uint8_t data);
void gbc_mmu_request_interrupt(struct gbc *gbc, uint8_t mask);
void gbc_mmu_hdma_hblank(struct gbc *gbc);
void gbc_mmu_step_dma(struct gbc *gbc, uint16_t cycles);
void gbc_mmu_step_serial(struct gbc *gbc, uint16_t cycles);

#ifdef __cplusplus
    }
#endif


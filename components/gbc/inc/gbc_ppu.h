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

typedef struct {
    uint16_t dot_cycles;
    uint8_t mode;
    uint8_t frame_ready;
    uint8_t win_line;
    uint8_t bgpi;
    uint8_t obpi;
    uint8_t bg_palette[64];
    uint8_t obj_palette[64];
    uint8_t bg_color_id[GBC_WIDTH];
    uint8_t bg_priority[GBC_WIDTH];
    uint8_t obj_drawn[GBC_WIDTH];
    gbc_color_t line[GBC_WIDTH];
} gbc_ppu_t;

struct gbc;

void gbc_ppu_reset(struct gbc *gbc);
void gbc_ppu_step(struct gbc *gbc, uint8_t cycles);
void gbc_ppu_render_scanline(struct gbc *gbc, uint8_t ly);
void gbc_ppu_update_lyc(struct gbc *gbc);
gbc_color_t gbc_ppu_color(uint8_t r5, uint8_t g5, uint8_t b5);

#ifdef __cplusplus
    }
#endif


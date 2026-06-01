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

#define GBC_APU_SAMPLE_BYTES        (4)

typedef struct {
    uint8_t enabled;
    uint8_t dac_enabled;
    uint8_t duty;
    uint8_t duty_step;
    uint8_t length_counter;
    uint8_t length_enabled;
    uint8_t envelope_volume;
    uint8_t envelope_period;
    uint8_t envelope_timer;
    uint8_t envelope_add;
    uint16_t frequency;
    uint16_t timer;
    uint16_t shadow_frequency;
    uint8_t sweep_period;
    uint8_t sweep_timer;
    uint8_t sweep_negate;
    uint8_t sweep_negate_used;
    uint8_t sweep_shift;
} gbc_apu_square_t;

typedef struct {
    uint8_t enabled;
    uint8_t dac_enabled;
    uint16_t length_counter;
    uint8_t length_enabled;
    uint8_t volume_code;
    uint8_t position;
    uint16_t frequency;
    uint16_t timer;
} gbc_apu_wave_t;

typedef struct {
    uint8_t enabled;
    uint8_t dac_enabled;
    uint8_t length_counter;
    uint8_t length_enabled;
    uint8_t envelope_volume;
    uint8_t envelope_period;
    uint8_t envelope_timer;
    uint8_t envelope_add;
    uint8_t clock_shift;
    uint8_t width_mode;
    uint8_t divisor_code;
    uint32_t timer;
    uint16_t lfsr;
} gbc_apu_noise_t;

typedef struct {
    uint8_t enabled;
    uint8_t frame_step;
    uint32_t frame_acc;
    uint32_t sample_acc;
    uint8_t sample_buffer[GBC_APU_BUFFER_SAMPLES * GBC_APU_SAMPLE_BYTES];
    uint16_t sample_index;
    gbc_apu_square_t square1;
    gbc_apu_square_t square2;
    gbc_apu_wave_t wave;
    gbc_apu_noise_t noise;
} gbc_apu_t;

struct gbc;

void gbc_apu_reset(struct gbc *gbc);
uint8_t gbc_apu_read(struct gbc *gbc, uint8_t reg);
void gbc_apu_write(struct gbc *gbc, uint8_t reg, uint8_t data);
void gbc_apu_step(struct gbc *gbc, uint8_t cycles);

#ifdef __cplusplus
    }
#endif


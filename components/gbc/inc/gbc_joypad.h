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

typedef enum {
    GBC_KEY_RIGHT = 0,
    GBC_KEY_LEFT,
    GBC_KEY_UP,
    GBC_KEY_DOWN,
    GBC_KEY_A,
    GBC_KEY_B,
    GBC_KEY_SELECT,
    GBC_KEY_START,
    GBC_KEY_COUNT
} gbc_key_t;

typedef struct {
    uint8_t state;
    uint8_t select;
} gbc_joypad_t;

struct gbc;

void gbc_joypad_reset(struct gbc *gbc);
void gbc_joypad_set(struct gbc *gbc, gbc_key_t key, uint8_t pressed);
uint8_t gbc_joypad_read(struct gbc *gbc);
void gbc_joypad_write(struct gbc *gbc, uint8_t data);

#ifdef __cplusplus
    }
#endif


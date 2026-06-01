/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#include "gbc.h"

void gbc_joypad_reset(gbc_t *gbc)
{
    gbc->joypad.state = 0xFF;
    gbc->joypad.select = 0x30;
}

void gbc_joypad_set(gbc_t *gbc, gbc_key_t key, uint8_t pressed)
{
    uint8_t mask;
    uint8_t old_state = gbc->joypad.state;

    if (key >= GBC_KEY_COUNT) {
        return;
    }
    mask = (uint8_t)(1U << key);
    if (pressed) {
        gbc->joypad.state &= (uint8_t)~mask;
    } else {
        gbc->joypad.state |= mask;
    }
    if (old_state != gbc->joypad.state && pressed) {
        gbc_mmu_request_interrupt(gbc, GBC_IF_JOYPAD);
    }
}

uint8_t gbc_joypad_read(gbc_t *gbc)
{
    uint8_t result = (uint8_t)(0xC0 | gbc->joypad.select | 0x0F);

    if ((gbc->joypad.select & 0x10) == 0) {
        result = (uint8_t)((result & 0xF0) | (gbc->joypad.state & 0x0F));
    }
    if ((gbc->joypad.select & 0x20) == 0) {
        result = (uint8_t)((result & 0xF0) | ((gbc->joypad.state >> 4) & 0x0F));
    }
    return result;
}

void gbc_joypad_write(gbc_t *gbc, uint8_t data)
{
    gbc->joypad.select = data & 0x30;
}


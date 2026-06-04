/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#include "gbc.h"

static void gbc_reset(gbc_t *gbc)
{
    gbc_model_t model = gbc->model;

    gbc->gbc_quit = 0;
    gbc->frame_count = 0;
    gbc->last_frame_ticks = 0;
    gbc->model = model;
    gbc_cart_reset(gbc);
    gbc_mmu_reset(gbc);
    gbc_timer_reset(gbc);
    gbc_joypad_reset(gbc);
    gbc_ppu_reset(gbc);
    gbc_apu_reset(gbc);
    gbc_cpu_reset(gbc);
}

gbc_t *gbc_init(void)
{
    gbc_t *gbc = (gbc_t *)gbc_malloc(sizeof(gbc_t));

    if (gbc == NULL) {
        return NULL;
    }
    gbc_memset(gbc, 0, sizeof(gbc_t));
    gbc->model = GBC_MODEL_DMG;
    gbc->preferred_model =
#if (GBC_ENABLE_CGB == 1)
        GBC_MODEL_CGB;
#else
        GBC_MODEL_DMG;
#endif
    gbc_reset(gbc);
    if (gbc_initex(gbc) != GBC_OK) {
        gbc_free(gbc);
        return NULL;
    }
    return gbc;
}

int gbc_deinit(gbc_t *gbc)
{
    if (gbc == NULL) {
        return GBC_ERROR;
    }
    gbc_cart_unload(gbc);
    gbc_deinitex(gbc);
    gbc_free(gbc);
    return GBC_OK;
}

int gbc_load_rom(gbc_t *gbc, const uint8_t *rom, uint32_t size)
{
    int ret;

    if (gbc == NULL) {
        return GBC_ERROR_BAD_ROM;
    }
    ret = gbc_cart_load_rom(gbc, rom, size, 0);
    if (ret != GBC_OK) {
        GBC_LOG_ERROR("gbc_load_rom failed: %d\n", ret);
        return ret;
    }
    gbc_reset(gbc);
    return GBC_OK;
}

int gbc_unload_rom(gbc_t *gbc)
{
    if (gbc == NULL) {
        return GBC_ERROR;
    }
    gbc_cart_unload(gbc);
    return GBC_OK;
}

#if (GBC_USE_FS == 1)
int gbc_load_file(gbc_t *gbc, const char *file_path)
{
    int ret;

    if (gbc == NULL || file_path == NULL) {
        return GBC_ERROR_IO;
    }
    ret = gbc_cart_load_file(gbc, file_path);
    if (ret != GBC_OK) {
        GBC_LOG_ERROR("gbc_load_file failed: %d\n", ret);
        return ret;
    }
    gbc_reset(gbc);
    return GBC_OK;
}

int gbc_unload_file(gbc_t *gbc)
{
    return gbc_unload_rom(gbc);
}
#endif

uint8_t gbc_step(gbc_t *gbc)
{
    uint8_t cycles;

    if (gbc == NULL || gbc->cart.rom_data == NULL) {
        return 0;
    }
    cycles = gbc_cpu_step(gbc);
    /* In CGB fast mode, the CPU runs at 8 MHz while PPU/timer still
     * run at 4 MHz.  Halve the cycles passed to subsystems so they advance
     * at the correct rate relative to wall time. */
    {
        uint8_t sub_cycles = gbc->mmu.double_speed ? (uint8_t)(cycles >> 1) : cycles;
        gbc_mmu_step_dma(gbc, cycles);
        gbc_mmu_step_serial(gbc, sub_cycles);
        gbc_timer_step(gbc, sub_cycles);
        gbc_ppu_step(gbc, sub_cycles);
        gbc_apu_step(gbc, sub_cycles);
    }

    if (gbc->ppu.frame_ready) {
        gbc->ppu.frame_ready = 0;
        gbc->frame_count++;
#if (GBC_FRAME_SKIP != 0)
        if (gbc->gbc_frame_skip_count >= GBC_FRAME_SKIP) {
            gbc->gbc_frame_skip_count = 0;
        } else {
            gbc->gbc_frame_skip_count++;
        }
#endif
        gbc_frame(gbc);
    }
    return cycles;
}

int gbc_set_model(gbc_t *gbc, gbc_model_t model)
{
    if (gbc == NULL) {
        return GBC_ERROR;
    }
    if (model == GBC_MODEL_CGB) {
#if (GBC_ENABLE_CGB == 0)
        return GBC_ERROR_UNSUPPORTED;
#endif
    } else {
#if (GBC_ENABLE_DMG == 0)
        return GBC_ERROR_UNSUPPORTED;
#endif
    }

    if (gbc->cart.rom_data != NULL) {
        if (gbc->cart.header.mode == GBC_CART_MODE_CGB_ONLY && model == GBC_MODEL_DMG) {
            return GBC_ERROR_UNSUPPORTED;
        }
        if (gbc->cart.header.mode == GBC_CART_MODE_DMG_ONLY && model == GBC_MODEL_CGB) {
            return GBC_ERROR_UNSUPPORTED;
        }
    }

    gbc->preferred_model = model;
    gbc->model = model;
    if (gbc->cart.rom_data != NULL) {
        gbc_reset(gbc);
    }
    return GBC_OK;
}

void gbc_run(gbc_t *gbc)
{
    if (gbc == NULL) {
        return;
    }
    while (!gbc->gbc_quit) {
        gbc_step(gbc);
    }
}


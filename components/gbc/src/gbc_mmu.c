/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#include "gbc.h"

static uint8_t gbc_mmu_read_io(gbc_t *gbc, uint8_t reg)
{
    if ((reg >= 0x10 && reg <= 0x26) || (reg >= 0x30 && reg <= 0x3F)) {
        return gbc_apu_read(gbc, reg);
    }

    switch (reg) {
    case 0x00:
        return gbc_joypad_read(gbc);
    case 0x04:
    case 0x05:
    case 0x06:
    case 0x07:
    case 0x0F:
    case 0x40:
    case 0x41:
    case 0x42:
    case 0x43:
    case 0x44:
    case 0x45:
    case 0x47:
    case 0x48:
    case 0x49:
    case 0x4A:
    case 0x4B:
        return gbc->mmu.io[reg];
    case 0x4D:
        return (uint8_t)(0x7E | (gbc->mmu.double_speed ? 0x80 : 0) | gbc->mmu.speed_prepare);
    case 0x4F:
        return (uint8_t)(0xFE | gbc->mmu.vram_bank);
    case 0x55:
        return gbc->mmu.io[0x55];  /* HDMA5: 0xFF = no active transfer */
    case 0x68:
        return gbc->ppu.bgpi;
    case 0x69:
        return gbc->ppu.bg_palette[gbc->ppu.bgpi & 0x3F];
    case 0x6A:
        return gbc->ppu.obpi;
    case 0x6B:
        return gbc->ppu.obj_palette[gbc->ppu.obpi & 0x3F];
    case 0x70:
        return (uint8_t)(0xF8 | gbc->mmu.wram_bank);
    default:
        return gbc->mmu.io[reg];
    }
}

static void gbc_mmu_do_dma(gbc_t *gbc, uint8_t data)
{
    uint16_t src = (uint16_t)data << 8;

    for (uint16_t i = 0; i < 0xA0; i++) {
        gbc->mmu.oam[i] = gbc_mmu_read(gbc, (uint16_t)(src + i));
    }
    gbc->mmu.oam_dma_cycles = 160U * 4U;
}

static uint8_t gbc_mmu_oam_dma_blocks(gbc_t *gbc, uint16_t addr)
{
    return (uint8_t)(gbc->mmu.oam_dma_cycles != 0 && addr < 0xFF80);
}

static uint16_t gbc_mmu_hdma_src_from_regs(gbc_t *gbc)
{
    return (uint16_t)(((uint16_t)gbc->mmu.io[0x51] << 8) | (gbc->mmu.io[0x52] & 0xF0));
}

static uint16_t gbc_mmu_hdma_dst_from_regs(gbc_t *gbc)
{
    return (uint16_t)(0x8000 | (((uint16_t)gbc->mmu.io[0x53] & 0x1F) << 8) | (gbc->mmu.io[0x54] & 0xF0));
}

static void gbc_mmu_hdma_copy_block(gbc_t *gbc)
{
    for (uint8_t i = 0; i < 16; i++) {
        gbc->mmu.vram[gbc->mmu.vram_bank][(gbc->mmu.hdma_dst + i) & 0x1FFF] =
            gbc_mmu_read(gbc, (uint16_t)(gbc->mmu.hdma_src + i));
    }
    gbc->mmu.hdma_src = (uint16_t)(gbc->mmu.hdma_src + 16);
    gbc->mmu.hdma_dst = (uint16_t)(0x8000 | ((gbc->mmu.hdma_dst + 16) & 0x1FFF));
    if (gbc->mmu.hdma_blocks > 0) {
        gbc->mmu.hdma_blocks--;
    }
    gbc->mmu.io[0x51] = (uint8_t)(gbc->mmu.hdma_src >> 8);
    gbc->mmu.io[0x52] = (uint8_t)(gbc->mmu.hdma_src & 0xF0);
    gbc->mmu.io[0x53] = (uint8_t)((gbc->mmu.hdma_dst >> 8) & 0x1F);
    gbc->mmu.io[0x54] = (uint8_t)(gbc->mmu.hdma_dst & 0xF0);
    if (gbc->mmu.hdma_blocks == 0) {
        gbc->mmu.hdma_active = 0;
        gbc->mmu.io[0x55] = 0xFF;
    } else {
        gbc->mmu.io[0x55] = (uint8_t)(gbc->mmu.hdma_blocks - 1);
    }
}

static void gbc_mmu_hdma_start(gbc_t *gbc, uint8_t data)
{
    gbc->mmu.hdma_src = gbc_mmu_hdma_src_from_regs(gbc);
    gbc->mmu.hdma_dst = gbc_mmu_hdma_dst_from_regs(gbc);
    gbc->mmu.hdma_blocks = (uint8_t)((data & 0x7F) + 1);

    if ((data & 0x80) == 0) {
        while (gbc->mmu.hdma_blocks != 0) {
            gbc_mmu_hdma_copy_block(gbc);
        }
        return;
    }

    gbc->mmu.hdma_active = 1;
    gbc->mmu.io[0x55] = (uint8_t)(gbc->mmu.hdma_blocks - 1);
}

static void gbc_mmu_write_io(gbc_t *gbc, uint8_t reg, uint8_t data)
{
    if ((reg >= 0x10 && reg <= 0x26) || (reg >= 0x30 && reg <= 0x3F)) {
        gbc_apu_write(gbc, reg, data);
        return;
    }

    switch (reg) {
    case 0x00:
        gbc_joypad_write(gbc, data);
        gbc->mmu.io[reg] = (uint8_t)(0xC0 | (data & 0x30) | 0x0F);
        return;
    case 0x04:
        gbc_timer_write_div(gbc);
        return;
    case 0x07:
        gbc_timer_write_tac(gbc, data);
        return;
    case 0x02:
        gbc->mmu.io[reg] = (uint8_t)(data | 0x7E);
        if ((data & 0x81) == 0x81) {
            gbc->mmu.serial_cycles = 4096;
        }
        return;
    case 0x0F:
        gbc->mmu.io[reg] = data | 0xE0;
        return;
    case 0x41:
        gbc->mmu.io[reg] = (uint8_t)((gbc->mmu.io[reg] & 0x07) | (data & 0x78) | 0x80);
        return;
    case 0x44:
        gbc->mmu.io[reg] = 0;
        gbc_ppu_update_lyc(gbc);
        return;
    case 0x45:
        gbc->mmu.io[reg] = data;
        gbc_ppu_update_lyc(gbc);
        return;
    case 0x46:
        gbc->mmu.io[reg] = data;
        gbc_mmu_do_dma(gbc, data);
        return;
    case 0x4D:
        gbc->mmu.speed_prepare = data & 0x01;
        gbc->mmu.io[reg] = data;
        return;
    case 0x4F:
        gbc->mmu.vram_bank = (gbc->model == GBC_MODEL_CGB) ? (data & 0x01) : 0;
        gbc->mmu.io[reg] = (uint8_t)(0xFE | gbc->mmu.vram_bank);
        return;
    case 0x68:
        gbc->ppu.bgpi = data;
        return;
    case 0x69:
        gbc->ppu.bg_palette[gbc->ppu.bgpi & 0x3F] = data;
        if (gbc->ppu.bgpi & 0x80) {
            gbc->ppu.bgpi = (uint8_t)(0x80 | ((gbc->ppu.bgpi + 1) & 0x3F));
        }
        return;
    case 0x6A:
        gbc->ppu.obpi = data;
        return;
    case 0x6B:
        gbc->ppu.obj_palette[gbc->ppu.obpi & 0x3F] = data;
        if (gbc->ppu.obpi & 0x80) {
            gbc->ppu.obpi = (uint8_t)(0x80 | ((gbc->ppu.obpi + 1) & 0x3F));
        }
        return;
    case 0x55:
        if (gbc->model != GBC_MODEL_CGB) {
            gbc->mmu.io[0x55] = 0xFF;
            return;
        }
        if (gbc->mmu.hdma_active && ((data & 0x80) == 0)) {
            gbc->mmu.hdma_active = 0;
            gbc->mmu.io[0x55] = (uint8_t)(0x80 | (gbc->mmu.hdma_blocks - 1));
            return;
        }
        gbc_mmu_hdma_start(gbc, data);
        return;
    case 0x70:
        gbc->mmu.wram_bank = data & 0x07;
        if (gbc->mmu.wram_bank == 0) {
            gbc->mmu.wram_bank = 1;
        }
        gbc->mmu.io[reg] = (uint8_t)(0xF8 | gbc->mmu.wram_bank);
        return;
    default:
        gbc->mmu.io[reg] = data;
        return;
    }
}

void gbc_mmu_reset(gbc_t *gbc)
{
    gbc_memset(&gbc->mmu, 0, sizeof(gbc->mmu));
    gbc_memset(gbc->mmu.vram, 0, sizeof(gbc->mmu.vram));
    gbc_memset(gbc->mmu.wram, 0, sizeof(gbc->mmu.wram));
    gbc_memset(gbc->mmu.oam, 0xFF, sizeof(gbc->mmu.oam));
    gbc_memset(gbc->mmu.io, 0, sizeof(gbc->mmu.io));
    gbc_memset(gbc->mmu.hram, 0, sizeof(gbc->mmu.hram));
    gbc->mmu.ie = 0;
    gbc->mmu.vram_bank = 0;
    gbc->mmu.wram_bank = 1;
    gbc->mmu.hdma_src = 0;
    gbc->mmu.hdma_dst = 0x8000;
    gbc->mmu.hdma_blocks = 0;
    gbc->mmu.hdma_active = 0;
    gbc->mmu.oam_dma_cycles = 0;
    gbc->mmu.serial_cycles = 0;

    gbc->mmu.io[0x00] = 0xCF;
    gbc->mmu.io[0x05] = 0x00;
    gbc->mmu.io[0x06] = 0x00;
    gbc->mmu.io[0x07] = 0x00;
    gbc->mmu.io[0x0F] = 0xE1;
    gbc->mmu.io[0x40] = 0x91;
    gbc->mmu.io[0x41] = 0x85;
    gbc->mmu.io[0x42] = 0x00;
    gbc->mmu.io[0x43] = 0x00;
    gbc->mmu.io[0x44] = 0x00;
    gbc->mmu.io[0x45] = 0x00;
    gbc->mmu.io[0x47] = 0xFC;
    gbc->mmu.io[0x48] = 0xFF;
    gbc->mmu.io[0x49] = 0xFF;
    gbc->mmu.io[0x4A] = 0x00;
    gbc->mmu.io[0x4B] = 0x00;
    gbc->mmu.io[0x4F] = 0xFE;
    gbc->mmu.io[0x55] = 0xFF;  /* HDMA5: no active transfer */
    gbc->mmu.io[0x70] = 0xF9;

    /* Audio post-boot values — NR52 bit 7 must be 1 or games spin-wait */
    gbc->mmu.io[0x10] = 0x80;  /* NR10 */
    gbc->mmu.io[0x11] = 0xBF;  /* NR11 */
    gbc->mmu.io[0x12] = 0xF3;  /* NR12 */
    gbc->mmu.io[0x13] = 0xFF;  /* NR13 */
    gbc->mmu.io[0x14] = 0xBF;  /* NR14 */
    gbc->mmu.io[0x16] = 0x3F;  /* NR21 */
    gbc->mmu.io[0x17] = 0x00;  /* NR22 */
    gbc->mmu.io[0x18] = 0xFF;  /* NR23 */
    gbc->mmu.io[0x19] = 0xBF;  /* NR24 */
    gbc->mmu.io[0x1A] = 0x7F;  /* NR30 */
    gbc->mmu.io[0x1B] = 0xFF;  /* NR31 */
    gbc->mmu.io[0x1C] = 0x9F;  /* NR32 */
    gbc->mmu.io[0x1D] = 0xFF;  /* NR33 */
    gbc->mmu.io[0x1E] = 0xBF;  /* NR34 */
    gbc->mmu.io[0x20] = 0xFF;  /* NR41 */
    gbc->mmu.io[0x21] = 0x00;  /* NR42 */
    gbc->mmu.io[0x22] = 0x00;  /* NR43 */
    gbc->mmu.io[0x23] = 0xBF;  /* NR44 */
    gbc->mmu.io[0x24] = 0x77;  /* NR50 */
    gbc->mmu.io[0x25] = 0xF3;  /* NR51 */
    gbc->mmu.io[0x26] = 0xF1;  /* NR52: master sound on */
}

uint8_t gbc_mmu_read(gbc_t *gbc, uint16_t addr)
{
    if (gbc_mmu_oam_dma_blocks(gbc, addr)) {
        return 0xFF;
    }
    if (addr < 0x8000) {
        return gbc_cart_read_rom(gbc, addr);
    }
    if (addr < 0xA000) {
        return gbc->mmu.vram[gbc->mmu.vram_bank][addr - 0x8000];
    }
    if (addr < 0xC000) {
        return gbc_cart_read_ram(gbc, addr);
    }
    if (addr < 0xD000) {
        return gbc->mmu.wram[0][addr - 0xC000];
    }
    if (addr < 0xE000) {
        return gbc->mmu.wram[gbc->mmu.wram_bank][addr - 0xD000];
    }
    if (addr < 0xFE00) {
        return gbc_mmu_read(gbc, (uint16_t)(addr - 0x2000));
    }
    if (addr < 0xFEA0) {
        return gbc->mmu.oam[addr - 0xFE00];
    }
    if (addr < 0xFF00) {
        return 0xFF;
    }
    if (addr < 0xFF80) {
        return gbc_mmu_read_io(gbc, (uint8_t)(addr & 0x7F));
    }
    if (addr < 0xFFFF) {
        return gbc->mmu.hram[addr - 0xFF80];
    }
    return gbc->mmu.ie;
}

void gbc_mmu_write(gbc_t *gbc, uint16_t addr, uint8_t data)
{
    if (gbc_mmu_oam_dma_blocks(gbc, addr)) {
        return;
    }
    if (addr < 0x8000) {
        gbc_cart_write(gbc, addr, data);
        return;
    }
    if (addr < 0xA000) {
        gbc->mmu.vram[gbc->mmu.vram_bank][addr - 0x8000] = data;
        return;
    }
    if (addr < 0xC000) {
        gbc_cart_write_ram(gbc, addr, data);
        return;
    }
    if (addr < 0xD000) {
        gbc->mmu.wram[0][addr - 0xC000] = data;
        return;
    }
    if (addr < 0xE000) {
        gbc->mmu.wram[gbc->mmu.wram_bank][addr - 0xD000] = data;
        return;
    }
    if (addr < 0xFE00) {
        gbc_mmu_write(gbc, (uint16_t)(addr - 0x2000), data);
        return;
    }
    if (addr < 0xFEA0) {
        gbc->mmu.oam[addr - 0xFE00] = data;
        return;
    }
    if (addr < 0xFF00) {
        return;
    }
    if (addr < 0xFF80) {
        gbc_mmu_write_io(gbc, (uint8_t)(addr & 0x7F), data);
        return;
    }
    if (addr < 0xFFFF) {
        gbc->mmu.hram[addr - 0xFF80] = data;
        return;
    }
    gbc->mmu.ie = data;
}

void gbc_mmu_request_interrupt(gbc_t *gbc, uint8_t mask)
{
    gbc->mmu.io[0x0F] |= mask;
}

void gbc_mmu_hdma_hblank(gbc_t *gbc)
{
    if (gbc->model == GBC_MODEL_CGB && gbc->mmu.hdma_active) {
        gbc_mmu_hdma_copy_block(gbc);
    }
}

void gbc_mmu_step_dma(gbc_t *gbc, uint16_t cycles)
{
    if (gbc->mmu.oam_dma_cycles == 0) {
        return;
    }
    if (cycles >= gbc->mmu.oam_dma_cycles) {
        gbc->mmu.oam_dma_cycles = 0;
    } else {
        gbc->mmu.oam_dma_cycles = (uint16_t)(gbc->mmu.oam_dma_cycles - cycles);
    }
}

void gbc_mmu_step_serial(gbc_t *gbc, uint16_t cycles)
{
    if (gbc->mmu.serial_cycles == 0) {
        return;
    }
    if (cycles < gbc->mmu.serial_cycles) {
        gbc->mmu.serial_cycles = (uint16_t)(gbc->mmu.serial_cycles - cycles);
        return;
    }
    gbc->mmu.serial_cycles = 0;
    gbc->mmu.io[0x01] = 0xFF;
    gbc->mmu.io[0x02] &= 0x7F;
    gbc_mmu_request_interrupt(gbc, GBC_IF_SERIAL);
}


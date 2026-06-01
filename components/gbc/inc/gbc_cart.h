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

#define GBC_ROM_BANK_SIZE           (0x4000)
#define GBC_RAM_BANK_SIZE           (0x2000)

typedef enum {
    GBC_MODEL_DMG = 0,
    GBC_MODEL_CGB,
} gbc_model_t;

typedef enum {
    GBC_CART_MODE_DMG_ONLY = 0,
    GBC_CART_MODE_CGB_COMPATIBLE,
    GBC_CART_MODE_CGB_ONLY,
} gbc_cart_mode_t;

typedef enum {
    GBC_MBC_NONE = 0,
    GBC_MBC1,
    GBC_MBC2,
    GBC_MBC3,
    GBC_MBC5,
} gbc_mbc_type_t;

typedef struct {
    uint8_t data[GBC_ROM_BANK_SIZE];
    uint16_t bank;
    uint32_t age;
    uint8_t valid;
} gbc_rom_cache_t;

typedef struct {
    char title[17];
    uint8_t cgb_flag;
    uint8_t sgb_flag;
    uint8_t cart_type;
    uint8_t rom_size_code;
    uint8_t ram_size_code;
    uint8_t destination_code;
    uint8_t version;
    uint8_t header_checksum;
    uint8_t header_checksum_ok;
    uint16_t rom_banks;
    uint8_t ram_banks;
    uint32_t rom_size;
    uint32_t ram_size;
    gbc_cart_mode_t mode;
    gbc_mbc_type_t mbc;
    uint8_t has_battery;
    uint8_t has_timer;
    uint8_t has_rumble;
} gbc_cart_header_t;

typedef struct {
    gbc_cart_header_t header;
    const uint8_t *rom_data;
    uint32_t rom_size;
    uint8_t *ram_data;
    uint32_t ram_size;
    uint8_t owns_rom;
    uint8_t owns_ram;
    uint8_t ram_enable;
    uint8_t banking_mode;
    uint16_t rom_bank;
    uint8_t ram_bank;
    uint8_t mbc2_ram[512];
    uint8_t mbc1_low5;
    uint8_t mbc1_high2;
    uint8_t rtc_select;
    uint8_t rtc_regs[5];
    uint8_t rtc_latched[5];
    uint8_t rtc_latch_prev;
    uint8_t rtc_started;
    uint16_t rtc_ms;
    uint32_t rtc_last_ticks;
#if (GBC_ENABLE_SRAM_SAVE == 1)
    char save_path[GBC_SAVE_PATH_MAX];
#endif
#if (GBC_ROM_STREAM == 1)
    FILE *stream;
    gbc_rom_cache_t cache[GBC_ROM_CACHE_BANKS];
    uint32_t cache_age;
#endif
} gbc_cart_t;

struct gbc;

int gbc_cart_load_rom(struct gbc *gbc, const uint8_t *rom, uint32_t size, uint8_t take_ownership);
#if (GBC_USE_FS == 1)
int gbc_cart_load_file(struct gbc *gbc, const char *file_path);
#endif
void gbc_cart_unload(struct gbc *gbc);
void gbc_cart_reset(struct gbc *gbc);
uint8_t gbc_cart_read_rom(struct gbc *gbc, uint16_t addr);
uint8_t gbc_cart_read_ram(struct gbc *gbc, uint16_t addr);
void gbc_cart_write(struct gbc *gbc, uint16_t addr, uint8_t data);
void gbc_cart_write_ram(struct gbc *gbc, uint16_t addr, uint8_t data);

#ifdef __cplusplus
    }
#endif


/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#include "gbc.h"

static uint32_t gbc_rom_size_from_code(uint8_t code)
{
    if (code <= 8) {
        return 32768UL << code;
    }
    if (code == 0x52) {
        return 72UL * 16384UL;
    }
    if (code == 0x53) {
        return 80UL * 16384UL;
    }
    if (code == 0x54) {
        return 96UL * 16384UL;
    }
    return 0;
}

static uint32_t gbc_ram_size_from_code(uint8_t code, uint8_t *banks)
{
    switch (code) {
    case 0x00:
        *banks = 0;
        return 0;
    case 0x02:
        *banks = 1;
        return 8UL * 1024UL;
    case 0x03:
        *banks = 4;
        return 32UL * 1024UL;
    case 0x04:
        *banks = 16;
        return 128UL * 1024UL;
    case 0x05:
        *banks = 8;
        return 64UL * 1024UL;
    default:
        *banks = 0;
        return 0;
    }
}

static int gbc_cart_decode_type(gbc_cart_header_t *header)
{
    header->mbc = GBC_MBC_NONE;
    header->has_battery = 0;
    header->has_timer = 0;
    header->has_rumble = 0;

    switch (header->cart_type) {
    case 0x00:
    case 0x08:
    case 0x09:
        header->mbc = GBC_MBC_NONE;
        header->has_battery = (header->cart_type == 0x09);
        return GBC_OK;
    case 0x01:
    case 0x02:
    case 0x03:
        header->mbc = GBC_MBC1;
        header->has_battery = (header->cart_type == 0x03);
        return GBC_OK;
    case 0x05:
    case 0x06:
        header->mbc = GBC_MBC2;
        header->has_battery = (header->cart_type == 0x06);
        header->ram_banks = 1;
        header->ram_size = 512;
        return GBC_OK;
    case 0x0F:
    case 0x10:
    case 0x11:
    case 0x12:
    case 0x13:
        header->mbc = GBC_MBC3;
        header->has_timer = (header->cart_type == 0x0F || header->cart_type == 0x10);
        header->has_battery = (header->cart_type == 0x0F || header->cart_type == 0x10 || header->cart_type == 0x13);
        return GBC_OK;
    case 0x19:
    case 0x1A:
    case 0x1B:
    case 0x1C:
    case 0x1D:
    case 0x1E:
        header->mbc = GBC_MBC5;
        header->has_rumble = (header->cart_type >= 0x1C);
        header->has_battery = (header->cart_type == 0x1B || header->cart_type == 0x1E);
        return GBC_OK;
    default:
        return GBC_ERROR_UNSUPPORTED;
    }
}

static int gbc_cart_parse_header(gbc_cart_header_t *header, const uint8_t *rom, uint32_t size)
{
    uint8_t checksum = 0;
    uint8_t title_len;
    uint32_t expected_size;

    if (rom == NULL || size < 0x150) {
        return GBC_ERROR_BAD_ROM;
    }

    gbc_memset(header, 0, sizeof(*header));
    title_len = (rom[0x143] == 0x80 || rom[0x143] == 0xC0) ? 11 : 16;
    if (title_len > 16) {
        title_len = 16;
    }
    gbc_memcpy(header->title, &rom[0x134], title_len);
    header->title[title_len] = '\0';
    header->cgb_flag = rom[0x143];
    header->sgb_flag = rom[0x146];
    header->cart_type = rom[0x147];
    header->rom_size_code = rom[0x148];
    header->ram_size_code = rom[0x149];
    header->destination_code = rom[0x14A];
    header->version = rom[0x14C];
    header->header_checksum = rom[0x14D];

    for (uint16_t i = 0x134; i <= 0x14C; i++) {
        checksum = (uint8_t)(checksum - rom[i] - 1);
    }
    header->header_checksum_ok = (checksum == header->header_checksum);

    expected_size = gbc_rom_size_from_code(header->rom_size_code);
    if (expected_size == 0 || size < expected_size) {
        return GBC_ERROR_BAD_ROM;
    }
    header->rom_size = expected_size;
    header->rom_banks = (uint16_t)(expected_size / GBC_ROM_BANK_SIZE);
    header->ram_size = gbc_ram_size_from_code(header->ram_size_code, &header->ram_banks);

    if (header->cgb_flag == 0xC0) {
        header->mode = GBC_CART_MODE_CGB_ONLY;
    } else if (header->cgb_flag == 0x80) {
        header->mode = GBC_CART_MODE_CGB_COMPATIBLE;
    } else {
        header->mode = GBC_CART_MODE_DMG_ONLY;
    }

    return gbc_cart_decode_type(header);
}

static uint16_t gbc_cart_mask_rom_bank(gbc_cart_t *cart, uint16_t bank, uint8_t force_switchable)
{
    if (cart->header.rom_banks == 0) {
        return 0;
    }
    bank %= cart->header.rom_banks;
    if (force_switchable && bank == 0 && cart->header.mbc != GBC_MBC_NONE) {
        bank = 1;
    }
    return bank;
}

static uint8_t gbc_cart_rtc_index(uint8_t select)
{
    return (select >= 0x08 && select <= 0x0C) ? (uint8_t)(select - 0x08) : 0xFF;
}

static uint16_t gbc_cart_rtc_days(gbc_cart_t *cart)
{
    return (uint16_t)(cart->rtc_regs[3] | ((uint16_t)(cart->rtc_regs[4] & 0x01) << 8));
}

static void gbc_cart_rtc_store_days(gbc_cart_t *cart, uint16_t days, uint8_t carry)
{
    cart->rtc_regs[3] = (uint8_t)days;
    cart->rtc_regs[4] = (uint8_t)((cart->rtc_regs[4] & 0x40) | ((days >> 8) & 0x01) | carry);
}

static void gbc_cart_rtc_add_seconds(gbc_cart_t *cart, uint32_t seconds)
{
    uint32_t total;
    uint32_t days;
    uint8_t carry = cart->rtc_regs[4] & 0x80;

    if (seconds == 0) {
        return;
    }

    days = gbc_cart_rtc_days(cart);
    total = (uint32_t)cart->rtc_regs[0] +
            ((uint32_t)cart->rtc_regs[1] * 60UL) +
            ((uint32_t)cart->rtc_regs[2] * 3600UL) +
            (days * 86400UL) + seconds;
    if (total >= (512UL * 86400UL)) {
        carry = 0x80;
        total %= (512UL * 86400UL);
    }

    cart->rtc_regs[0] = (uint8_t)(total % 60UL);
    total /= 60UL;
    cart->rtc_regs[1] = (uint8_t)(total % 60UL);
    total /= 60UL;
    cart->rtc_regs[2] = (uint8_t)(total % 24UL);
    total /= 24UL;
    gbc_cart_rtc_store_days(cart, (uint16_t)(total & 0x1FF), carry);
}

static void gbc_cart_rtc_sync(gbc_t *gbc)
{
    gbc_cart_t *cart = &gbc->cart;
    uint32_t now;
    uint32_t elapsed_ms;
    uint32_t seconds;

    if (!cart->header.has_timer) {
        return;
    }

    now = gbc_get_ticks();
    if (!cart->rtc_started) {
        cart->rtc_last_ticks = now;
        cart->rtc_started = 1;
        return;
    }

    elapsed_ms = (uint32_t)(now - cart->rtc_last_ticks) + cart->rtc_ms;
    cart->rtc_last_ticks = now;
    if (cart->rtc_regs[4] & 0x40) {
        cart->rtc_ms = 0;
        return;
    }

    seconds = elapsed_ms / 1000UL;
    cart->rtc_ms = (uint16_t)(elapsed_ms % 1000UL);
    gbc_cart_rtc_add_seconds(cart, seconds);
}

static uint8_t gbc_cart_rtc_read(gbc_t *gbc)
{
    uint8_t index = gbc_cart_rtc_index(gbc->cart.rtc_select);

    if (index == 0xFF || !gbc->cart.header.has_timer) {
        return 0xFF;
    }
    gbc_cart_rtc_sync(gbc);
    return gbc->cart.rtc_latched[index];
}

static void gbc_cart_rtc_write(gbc_t *gbc, uint8_t data)
{
    gbc_cart_t *cart = &gbc->cart;
    uint8_t index = gbc_cart_rtc_index(cart->rtc_select);

    if (index == 0xFF || !cart->header.has_timer) {
        return;
    }
    gbc_cart_rtc_sync(gbc);
    switch (index) {
    case 0:
    case 1:
        data &= 0x3F;
        if (data >= 60) {
            data = (uint8_t)(data - 60);
        }
        break;
    case 2:
        data &= 0x1F;
        if (data >= 24) {
            data = (uint8_t)(data - 24);
        }
        break;
    case 4:
        data &= 0xC1;
        break;
    default:
        break;
    }
    cart->rtc_regs[index] = data;
    cart->rtc_latched[index] = data;
    cart->rtc_ms = 0;
    cart->rtc_last_ticks = gbc_get_ticks();
    cart->rtc_started = 1;
}

static void gbc_cart_rtc_latch(gbc_t *gbc, uint8_t data)
{
    gbc_cart_t *cart = &gbc->cart;

    if (!cart->header.has_timer) {
        return;
    }
    if ((data & 0x01) && !cart->rtc_latch_prev) {
        gbc_cart_rtc_sync(gbc);
        gbc_memcpy(cart->rtc_latched, cart->rtc_regs, sizeof(cart->rtc_latched));
    }
    cart->rtc_latch_prev = data & 0x01;
}

#if (GBC_ENABLE_SRAM_SAVE == 1)
static uint8_t *gbc_cart_battery_ram_ptr(gbc_cart_t *cart)
{
    return (cart->header.mbc == GBC_MBC2) ? cart->mbc2_ram : cart->ram_data;
}

static uint32_t gbc_cart_battery_ram_size(gbc_cart_t *cart)
{
    return (cart->header.mbc == GBC_MBC2) ? (uint32_t)sizeof(cart->mbc2_ram) : cart->ram_size;
}

static void gbc_cart_set_save_path(gbc_cart_t *cart, const char *file_path)
{
    int ret;

    cart->save_path[0] = '\0';
    if (file_path == NULL) {
        return;
    }
    ret = snprintf(cart->save_path, sizeof(cart->save_path), "%s.sav", file_path);
    if (ret < 0 || (size_t)ret >= sizeof(cart->save_path)) {
        cart->save_path[0] = '\0';
        GBC_LOG_WARN("save path is too long, battery RAM disabled\n");
    }
}

static void gbc_cart_load_battery_ram(gbc_t *gbc)
{
    gbc_cart_t *cart = &gbc->cart;
    FILE *fp;
    uint8_t *ram;
    uint32_t ram_size;
    size_t got;

    ram = gbc_cart_battery_ram_ptr(cart);
    ram_size = gbc_cart_battery_ram_size(cart);
    if (!cart->header.has_battery || ram == NULL || ram_size == 0 || cart->save_path[0] == '\0') {
        return;
    }

    fp = gbc_fopen(cart->save_path, "rb");
    if (fp == NULL) {
        return;
    }
    got = gbc_fread(ram, 1, ram_size, fp);
    if (got != ram_size) {
        GBC_LOG_WARN("short battery RAM read: %u/%u bytes\n", (unsigned)got, (unsigned)ram_size);
    }
    gbc_fclose(fp);
}

static void gbc_cart_save_battery_ram(gbc_t *gbc)
{
    gbc_cart_t *cart = &gbc->cart;
    FILE *fp;
    uint8_t *ram;
    uint32_t ram_size;
    size_t wrote;

    ram = gbc_cart_battery_ram_ptr(cart);
    ram_size = gbc_cart_battery_ram_size(cart);
    if (!cart->header.has_battery || ram == NULL || ram_size == 0 || cart->save_path[0] == '\0') {
        return;
    }

    fp = gbc_fopen(cart->save_path, "wb");
    if (fp == NULL) {
        GBC_LOG_WARN("failed to open battery RAM save file\n");
        return;
    }
    wrote = gbc_fwrite(ram, 1, ram_size, fp);
    if (wrote != ram_size) {
        GBC_LOG_WARN("short battery RAM write: %u/%u bytes\n", (unsigned)wrote, (unsigned)ram_size);
    }
    if (gbc_fclose(fp) != 0) {
        GBC_LOG_WARN("failed to close battery RAM save file\n");
    }
}
#endif /* GBC_ENABLE_SRAM_SAVE */

int gbc_cart_load_rom(gbc_t *gbc, const uint8_t *rom, uint32_t size, uint8_t take_ownership)
{
    gbc_cart_t *cart;
    int ret;

    if (gbc == NULL || rom == NULL) {
        return GBC_ERROR_BAD_ROM;
    }

    cart = &gbc->cart;
    gbc_cart_unload(gbc);
    ret = gbc_cart_parse_header(&cart->header, rom, size);
    if (ret != GBC_OK) {
        return ret;
    }

#if (GBC_ENABLE_DMG == 0)
    if (cart->header.mode == GBC_CART_MODE_DMG_ONLY) {
        return GBC_ERROR_UNSUPPORTED;
    }
#endif
#if (GBC_ENABLE_CGB == 0)
    if (cart->header.mode == GBC_CART_MODE_CGB_ONLY) {
        return GBC_ERROR_UNSUPPORTED;
    }
#endif

    cart->rom_data = rom;
    cart->rom_size = cart->header.rom_size;
    cart->owns_rom = take_ownership;
    cart->rom_bank = 1;
    cart->ram_bank = 0;
    cart->mbc1_low5 = 1;
    cart->mbc1_high2 = 0;
    cart->banking_mode = 0;
    gbc_memset(cart->mbc2_ram, 0x0F, sizeof(cart->mbc2_ram));
    cart->rtc_last_ticks = gbc_get_ticks();
    cart->rtc_started = 1;

    if (cart->header.ram_size != 0 && cart->header.mbc != GBC_MBC2) {
        cart->ram_data = (uint8_t *)gbc_malloc((int)cart->header.ram_size);
        if (cart->ram_data == NULL) {
            gbc_cart_unload(gbc);
            return GBC_ERROR_ALLOC;
        }
        gbc_memset(cart->ram_data, 0xFF, cart->header.ram_size);
        cart->ram_size = cart->header.ram_size;
        cart->owns_ram = 1;
    }

    if (cart->header.mode == GBC_CART_MODE_CGB_ONLY) {
        gbc->model = GBC_MODEL_CGB;
    } else if (cart->header.mode == GBC_CART_MODE_CGB_COMPATIBLE) {
#if (GBC_ENABLE_CGB == 1)
        gbc->model = (gbc->preferred_model == GBC_MODEL_CGB) ? GBC_MODEL_CGB : GBC_MODEL_DMG;
#else
        gbc->model = GBC_MODEL_DMG;
#endif
    } else {
        gbc->model = GBC_MODEL_DMG;
    }

    GBC_LOG_INFO("loaded %s, type=0x%02X, rom=%uKB, ram=%uKB, mode=%s\n",
                 cart->header.title,
                 cart->header.cart_type,
                 (unsigned)(cart->header.rom_size / 1024),
                 (unsigned)(cart->header.ram_size / 1024),
                 gbc->model == GBC_MODEL_CGB ? "GBC" : "GB");
    return GBC_OK;
}

#if (GBC_USE_FS == 1)
int gbc_cart_load_file(gbc_t *gbc, const char *file_path)
{
    FILE *fp;
    long size;
    uint8_t *rom;

    if (gbc == NULL || file_path == NULL) {
        return GBC_ERROR_IO;
    }

    fp = gbc_fopen(file_path, "rb");
    if (fp == NULL) {
        return GBC_ERROR_IO;
    }

    if (gbc_fseek(fp, 0, SEEK_END) != 0) {
        gbc_fclose(fp);
        return GBC_ERROR_IO;
    }
    size = gbc_ftell(fp);
    if (size <= 0) {
        gbc_fclose(fp);
        return GBC_ERROR_IO;
    }
    if (gbc_fseek(fp, 0, SEEK_SET) != 0) {
        gbc_fclose(fp);
        return GBC_ERROR_IO;
    }

#if (GBC_ROM_STREAM == 1)
    rom = (uint8_t *)gbc_malloc(0x150);
    if (rom == NULL) {
        gbc_fclose(fp);
        return GBC_ERROR_ALLOC;
    }
    if (gbc_fread(rom, 1, 0x150, fp) != 0x150) {
        gbc_free(rom);
        gbc_fclose(fp);
        return GBC_ERROR_IO;
    }
    int ret = gbc_cart_load_rom(gbc, rom, (uint32_t)size, 1);
    if (ret != GBC_OK) {
        gbc_free(rom);
        gbc_fclose(fp);
        return ret;
    }
    gbc->cart.stream = fp;
    gbc_memset(gbc->cart.cache, 0, sizeof(gbc->cart.cache));
#if (GBC_ENABLE_SRAM_SAVE == 1)
    gbc_cart_set_save_path(&gbc->cart, file_path);
    gbc_cart_load_battery_ram(gbc);
#endif
    return GBC_OK;
#else
    rom = (uint8_t *)gbc_malloc((int)size);
    if (rom == NULL) {
        gbc_fclose(fp);
        return GBC_ERROR_ALLOC;
    }
    if (gbc_fread(rom, 1, (size_t)size, fp) != (size_t)size) {
        gbc_free(rom);
        gbc_fclose(fp);
        return GBC_ERROR_IO;
    }
    gbc_fclose(fp);
    int ret = gbc_cart_load_rom(gbc, rom, (uint32_t)size, 1);
    if (ret != GBC_OK) {
        gbc_free(rom);
    } else {
#if (GBC_ENABLE_SRAM_SAVE == 1)
        gbc_cart_set_save_path(&gbc->cart, file_path);
        gbc_cart_load_battery_ram(gbc);
#endif
    }
    return ret;
#endif
}
#endif

void gbc_cart_unload(gbc_t *gbc)
{
    gbc_cart_t *cart;

    if (gbc == NULL) {
        return;
    }
    cart = &gbc->cart;
#if (GBC_ENABLE_SRAM_SAVE == 1)
    gbc_cart_save_battery_ram(gbc);
#endif
#if (GBC_ROM_STREAM == 1)
    if (cart->stream != NULL) {
        gbc_fclose(cart->stream);
    }
#endif
    if (cart->owns_rom && cart->rom_data != NULL) {
        gbc_free((void *)cart->rom_data);
    }
    if (cart->owns_ram && cart->ram_data != NULL) {
        gbc_free(cart->ram_data);
    }
    gbc_memset(cart, 0, sizeof(*cart));
}

void gbc_cart_reset(gbc_t *gbc)
{
    gbc_cart_t *cart;

    if (gbc == NULL || gbc->cart.rom_data == NULL) {
        return;
    }
    cart = &gbc->cart;
    cart->ram_enable = 0;
    cart->banking_mode = 0;
    cart->rom_bank = 1;
    cart->ram_bank = 0;
    cart->mbc1_low5 = 1;
    cart->mbc1_high2 = 0;
    cart->rtc_select = 0;
    cart->rtc_latch_prev = 0;
}

static const uint8_t *gbc_cart_bank_ptr(gbc_cart_t *cart, uint16_t bank)
{
#if (GBC_ROM_STREAM == 1)
    uint8_t slot = 0;
    uint8_t victim = 0;
    uint32_t oldest = 0xFFFFFFFFUL;

    if (cart->stream == NULL) {
        return cart->rom_data + ((uint32_t)bank * GBC_ROM_BANK_SIZE);
    }
    for (slot = 0; slot < GBC_ROM_CACHE_BANKS; slot++) {
        if (cart->cache[slot].valid && cart->cache[slot].bank == bank) {
            cart->cache[slot].age = ++cart->cache_age;
            return cart->cache[slot].data;
        }
        if (!cart->cache[slot].valid) {
            victim = slot;
            oldest = 0;
            break;
        }
        if (cart->cache[slot].age < oldest) {
            oldest = cart->cache[slot].age;
            victim = slot;
        }
    }
    (void)oldest;
    if (gbc_fseek(cart->stream, (long)((uint32_t)bank * GBC_ROM_BANK_SIZE), SEEK_SET) != 0) {
        return NULL;
    }
    if (gbc_fread(cart->cache[victim].data, 1, GBC_ROM_BANK_SIZE, cart->stream) != GBC_ROM_BANK_SIZE) {
        return NULL;
    }
    cart->cache[victim].bank = bank;
    cart->cache[victim].age = ++cart->cache_age;
    cart->cache[victim].valid = 1;
    return cart->cache[victim].data;
#else
    return cart->rom_data + ((uint32_t)bank * GBC_ROM_BANK_SIZE);
#endif
}

uint8_t gbc_cart_read_rom(gbc_t *gbc, uint16_t addr)
{
    gbc_cart_t *cart = &gbc->cart;
    uint16_t bank = 0;
    const uint8_t *ptr;

    if (cart->rom_data == NULL) {
        return 0xFF;
    }

    if (addr < 0x4000) {
        if (cart->header.mbc == GBC_MBC1 && cart->banking_mode) {
            bank = (uint16_t)(cart->mbc1_high2 << 5);
        }
    } else {
        bank = gbc_cart_mask_rom_bank(cart, cart->rom_bank, 1);
        addr = (uint16_t)(addr - 0x4000);
    }

    bank = gbc_cart_mask_rom_bank(cart, bank, 0);
    ptr = gbc_cart_bank_ptr(cart, bank);
    if (ptr == NULL) {
        return 0xFF;
    }
    return ptr[addr & 0x3FFF];
}

uint8_t gbc_cart_read_ram(gbc_t *gbc, uint16_t addr)
{
    gbc_cart_t *cart = &gbc->cart;
    uint32_t offset;

    if (!cart->ram_enable) {
        return 0xFF;
    }
    if (cart->header.mbc == GBC_MBC2) {
        return (uint8_t)(0xF0 | (cart->mbc2_ram[addr & 0x01FF] & 0x0F));
    }
    if (cart->header.mbc == GBC_MBC3 && gbc_cart_rtc_index(cart->rtc_select) != 0xFF) {
        return gbc_cart_rtc_read(gbc);
    }
    if (cart->ram_data == NULL || cart->ram_size == 0) {
        return 0xFF;
    }
    offset = ((uint32_t)cart->ram_bank * GBC_RAM_BANK_SIZE) + (addr & 0x1FFF);
    if (offset >= cart->ram_size) {
        return 0xFF;
    }
    return cart->ram_data[offset];
}

void gbc_cart_write_ram(gbc_t *gbc, uint16_t addr, uint8_t data)
{
    gbc_cart_t *cart = &gbc->cart;
    uint32_t offset;

    if (!cart->ram_enable) {
        return;
    }
    if (cart->header.mbc == GBC_MBC2) {
        cart->mbc2_ram[addr & 0x01FF] = data & 0x0F;
        return;
    }
    if (cart->header.mbc == GBC_MBC3 && gbc_cart_rtc_index(cart->rtc_select) != 0xFF) {
        gbc_cart_rtc_write(gbc, data);
        return;
    }
    if (cart->ram_data == NULL || cart->ram_size == 0) {
        return;
    }
    offset = ((uint32_t)cart->ram_bank * GBC_RAM_BANK_SIZE) + (addr & 0x1FFF);
    if (offset < cart->ram_size) {
        cart->ram_data[offset] = data;
    }
}

void gbc_cart_write(gbc_t *gbc, uint16_t addr, uint8_t data)
{
    gbc_cart_t *cart = &gbc->cart;

    switch (cart->header.mbc) {
    case GBC_MBC_NONE:
        return;
    case GBC_MBC1:
        if (addr < 0x2000) {
            cart->ram_enable = ((data & 0x0F) == 0x0A);
        } else if (addr < 0x4000) {
            cart->mbc1_low5 = data & 0x1F;
            if (cart->mbc1_low5 == 0) {
                cart->mbc1_low5 = 1;
            }
            cart->rom_bank = gbc_cart_mask_rom_bank(cart, (uint16_t)((cart->mbc1_high2 << 5) | cart->mbc1_low5), 1);
        } else if (addr < 0x6000) {
            cart->mbc1_high2 = data & 0x03;
            if (cart->banking_mode) {
                cart->ram_bank = cart->mbc1_high2;
            } else {
                cart->rom_bank = gbc_cart_mask_rom_bank(cart, (uint16_t)((cart->mbc1_high2 << 5) | cart->mbc1_low5), 1);
            }
        } else {
            cart->banking_mode = data & 0x01;
            cart->ram_bank = cart->banking_mode ? cart->mbc1_high2 : 0;
        }
        return;
    case GBC_MBC2:
        if (addr < 0x4000) {
            if (addr & 0x0100) {
                cart->rom_bank = gbc_cart_mask_rom_bank(cart, data & 0x0F, 1);
            } else {
                cart->ram_enable = ((data & 0x0F) == 0x0A);
            }
        }
        return;
    case GBC_MBC3:
        if (addr < 0x2000) {
            cart->ram_enable = ((data & 0x0F) == 0x0A);
        } else if (addr < 0x4000) {
            cart->rom_bank = gbc_cart_mask_rom_bank(cart, data & 0x7F, 1);
        } else if (addr < 0x6000) {
            if (cart->header.has_timer && gbc_cart_rtc_index(data) != 0xFF) {
                cart->rtc_select = data;
            } else {
                cart->rtc_select = 0;
                cart->ram_bank = data & 0x03;
            }
        } else {
            gbc_cart_rtc_latch(gbc, data);
        }
        return;
    case GBC_MBC5:
        if (addr < 0x2000) {
            cart->ram_enable = ((data & 0x0F) == 0x0A);
        } else if (addr < 0x3000) {
            cart->rom_bank = (uint16_t)((cart->rom_bank & 0x100) | data);
        } else if (addr < 0x4000) {
            cart->rom_bank = (uint16_t)(((data & 0x01) << 8) | (cart->rom_bank & 0xFF));
        } else if (addr < 0x6000) {
            cart->ram_bank = data & 0x0F;
        }
        cart->rom_bank = gbc_cart_mask_rom_bank(cart, cart->rom_bank, 1);
        return;
    default:
        return;
    }
}


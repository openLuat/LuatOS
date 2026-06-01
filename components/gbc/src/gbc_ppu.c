/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 */
#include "gbc.h"

static const uint8_t dmg_shades[4][3] = {
    {31, 31, 31},
    {21, 21, 21},
    {10, 10, 10},
    {0, 0, 0},
};

gbc_color_t gbc_ppu_color(uint8_t r5, uint8_t g5, uint8_t b5)
{
#if (GBC_COLOR_DEPTH == 32)
    uint8_t r = (uint8_t)((r5 << 3) | (r5 >> 2));
    uint8_t g = (uint8_t)((g5 << 3) | (g5 >> 2));
    uint8_t b = (uint8_t)((b5 << 3) | (b5 >> 2));
    return (gbc_color_t)(0xFF000000UL | ((uint32_t)r << 16) | ((uint32_t)g << 8) | b);
#else
    uint16_t g6 = (uint16_t)((g5 << 1) | (g5 >> 4));
    uint16_t color = (uint16_t)((r5 << 11) | (g6 << 5) | b5);
#if (GBC_COLOR_SWAP == 1)
    color = (uint16_t)((color << 8) | (color >> 8));
#endif
    return color;
#endif
}

GBC_INLINE gbc_color_t gbc_ppu_dmg_color(uint8_t palette, uint8_t index)
{
    uint8_t shade = (palette >> (index * 2)) & 0x03;
    return gbc_ppu_color(dmg_shades[shade][0], dmg_shades[shade][1], dmg_shades[shade][2]);
}

GBC_INLINE gbc_color_t gbc_ppu_cgb_color(uint8_t *palette, uint8_t palette_id, uint8_t index)
{
    uint8_t base = (uint8_t)((palette_id * 8) + (index * 2));
    uint16_t raw = (uint16_t)(palette[base] | (palette[base + 1] << 8));
    return gbc_ppu_color(raw & 0x1F, (raw >> 5) & 0x1F, (raw >> 10) & 0x1F);
}

GBC_INLINE uint8_t gbc_ppu_should_draw(gbc_t *gbc)
{
#if (GBC_FRAME_SKIP != 0)
    return gbc->gbc_frame_skip_count == 0;
#else
    (void)gbc;
    return 1;
#endif
}

static void gbc_ppu_set_mode(gbc_t *gbc, uint8_t mode)
{
    uint8_t stat = gbc->mmu.io[0x41];
    uint8_t old_mode = stat & 0x03;

    gbc->ppu.mode = mode;
    gbc->mmu.io[0x41] = (uint8_t)((stat & 0xFC) | mode);
    if (old_mode == mode) {
        return;
    }
    if ((mode == 0 && (stat & 0x08)) ||
        (mode == 1 && (stat & 0x10)) ||
        (mode == 2 && (stat & 0x20))) {
        gbc_mmu_request_interrupt(gbc, GBC_IF_LCD);
    }
    if (mode == 0) {
        gbc_mmu_hdma_hblank(gbc);
    }
}

GBC_INLINE uint8_t gbc_ppu_visible_sprite_count(gbc_t *gbc, uint8_t ly)
{
    uint8_t lcdc = gbc->mmu.io[0x40];
    uint8_t sprite_height = (lcdc & 0x04) ? 16 : 8;
    uint8_t count = 0;

    if ((lcdc & 0x02) == 0) {
        return 0;
    }
    for (uint8_t i = 0; i < 40 && count < 10; i++) {
        int16_t sy = (int16_t)gbc->mmu.oam[i * 4] - 16;
        if (ly >= sy && ly < sy + sprite_height) {
            count++;
        }
    }
    return count;
}

GBC_INLINE uint16_t gbc_ppu_mode3_end(gbc_t *gbc, uint8_t ly)
{
    uint16_t end = (uint16_t)(252 + (gbc->mmu.io[0x43] & 0x07) +
                              (gbc_ppu_visible_sprite_count(gbc, ly) * 6));

    return end > 289 ? 289 : end;
}

GBC_INLINE uint8_t gbc_ppu_tile_pixel(gbc_t *gbc, uint16_t tile_addr, uint8_t x, uint8_t y, uint8_t bank)
{
    uint16_t row = (uint16_t)(tile_addr + (y * 2));
    uint8_t lo = gbc->mmu.vram[bank][row & 0x1FFF];
    uint8_t hi = gbc->mmu.vram[bank][(row + 1) & 0x1FFF];
    uint8_t bit = (uint8_t)(7 - x);

    return (uint8_t)(((lo >> bit) & 1) | (((hi >> bit) & 1) << 1));
}

static uint8_t gbc_ppu_render_bg_window(gbc_t *gbc, uint8_t ly)
{
    gbc_mmu_t *mmu = &gbc->mmu;
    gbc_ppu_t *ppu = &gbc->ppu;
    uint8_t *vram0 = mmu->vram[0];
    uint8_t *vram1 = mmu->vram[1];
    gbc_model_t model = gbc->model;
    uint8_t lcdc = mmu->io[0x40];
    uint8_t scy = mmu->io[0x42];
    uint8_t scx = mmu->io[0x43];
    uint8_t wy = mmu->io[0x4A];
    uint8_t wx = mmu->io[0x4B];
    uint8_t use_window = (uint8_t)((lcdc & 0x20) && ly >= wy && wx <= 166);
    uint16_t bg_map = (lcdc & 0x08) ? 0x1C00 : 0x1800;
    uint16_t win_map = (lcdc & 0x40) ? 0x1C00 : 0x1800;
    uint8_t signed_tiles = ((lcdc & 0x10) == 0);
    uint8_t win_used = 0;

    for (uint8_t x = 0; x < GBC_WIDTH; x++) {
        uint8_t pixel_x = (uint8_t)(x + scx);
        uint8_t pixel_y = (uint8_t)(ly + scy);
        uint16_t map = bg_map;
        uint8_t tile_x;
        uint8_t tile_y;
        uint8_t tile_no;
        uint8_t attr = 0;
        uint8_t bank = 0;
        uint8_t color_id;
        uint8_t tile_px;
        uint8_t tile_py;
        uint16_t tile_addr;

        if (use_window && x + 7 >= wx) {
            pixel_x = (uint8_t)(x + 7 - wx);
            pixel_y = ppu->win_line;
            map = win_map;
            win_used = 1;
        }

        tile_x = (uint8_t)(pixel_x / 8);
        tile_y = (uint8_t)(pixel_y / 8);
        tile_no = vram0[map + (tile_y * 32) + tile_x];
        if (model == GBC_MODEL_CGB) {
            attr = vram1[map + (tile_y * 32) + tile_x];
            bank = (attr & 0x08) ? 1 : 0;
        }

        if (signed_tiles) {
            tile_addr = (uint16_t)(0x1000 + ((int8_t)tile_no * 16));
        } else {
            tile_addr = (uint16_t)(tile_no * 16);
        }

        tile_px = pixel_x & 7;
        tile_py = pixel_y & 7;
        if (model == GBC_MODEL_CGB) {
            if (attr & 0x20) {
                tile_px = (uint8_t)(7 - tile_px);
            }
            if (attr & 0x40) {
                tile_py = (uint8_t)(7 - tile_py);
            }
        }

        color_id = gbc_ppu_tile_pixel(gbc, tile_addr, tile_px, tile_py, bank);
        ppu->bg_color_id[x] = color_id;
        ppu->bg_priority[x] = (model == GBC_MODEL_CGB && (attr & 0x80)) ? 1 : 0;
        if (model == GBC_MODEL_CGB) {
            ppu->line[x] = gbc_ppu_cgb_color(ppu->bg_palette, attr & 0x07, color_id);
        } else {
            ppu->line[x] = gbc_ppu_dmg_color(mmu->io[0x47], color_id);
        }
    }
    return win_used;
}

static void gbc_ppu_render_sprites(gbc_t *gbc, uint8_t ly)
{
    gbc_mmu_t *mmu = &gbc->mmu;
    gbc_ppu_t *ppu = &gbc->ppu;
    uint8_t *oam_data = mmu->oam;
    gbc_model_t model = gbc->model;
    uint8_t lcdc = mmu->io[0x40];
    uint8_t sprite_height = (lcdc & 0x04) ? 16 : 8;
    uint8_t bg_priority_enabled = !(model == GBC_MODEL_CGB && ((lcdc & 0x01) == 0));
    uint8_t sprites[10];
    uint8_t sprite_count = 0;

    if ((lcdc & 0x02) == 0) {
        return;
    }

    for (uint8_t i = 0; i < 40 && sprite_count < 10; i++) {
        uint8_t *oam = &oam_data[i * 4];
        int16_t sy = (int16_t)oam[0] - 16;

        if (ly >= sy && ly < sy + sprite_height) {
            sprites[sprite_count++] = i;
        }
    }

    if (model == GBC_MODEL_DMG) {
        for (uint8_t i = 1; i < sprite_count; i++) {
            uint8_t sprite = sprites[i];
            uint8_t x = oam_data[(sprite * 4) + 1];
            uint8_t j = i;
            while (j > 0 && oam_data[(sprites[j - 1] * 4) + 1] > x) {
                sprites[j] = sprites[j - 1];
                j--;
            }
            sprites[j] = sprite;
        }
    }

    for (uint8_t n = 0; n < sprite_count; n++) {
        uint8_t *oam = &oam_data[sprites[n] * 4];
        int16_t sy = (int16_t)oam[0] - 16;
        int16_t sx = (int16_t)oam[1] - 8;
        uint8_t tile = oam[2];
        uint8_t attr = oam[3];
        uint8_t line;
        uint8_t bank = (model == GBC_MODEL_CGB && (attr & 0x08)) ? 1 : 0;

        line = (uint8_t)(ly - sy);
        if (attr & 0x40) {
            line = (uint8_t)(sprite_height - 1 - line);
        }
        if (sprite_height == 16) {
            tile &= 0xFE;
        }
        for (uint8_t px = 0; px < 8; px++) {
            int16_t screen_x = sx + px;
            uint8_t tx = (attr & 0x20) ? (uint8_t)(7 - px) : px;
            uint8_t color_id;

            if (screen_x < 0 || screen_x >= GBC_WIDTH) {
                continue;
            }
            if (ppu->obj_drawn[screen_x]) {
                continue;
            }
            color_id = gbc_ppu_tile_pixel(gbc, (uint16_t)(tile * 16), tx, line, bank);
            if (color_id == 0) {
                continue;
            }
            ppu->obj_drawn[screen_x] = 1;
            if (bg_priority_enabled && (attr & 0x80) && ppu->bg_color_id[screen_x] != 0) {
                continue;
            }
            if (bg_priority_enabled && model == GBC_MODEL_CGB && ppu->bg_priority[screen_x] && ppu->bg_color_id[screen_x] != 0) {
                continue;
            }
            if (model == GBC_MODEL_CGB) {
                ppu->line[screen_x] = gbc_ppu_cgb_color(ppu->obj_palette, attr & 0x07, color_id);
            } else {
                ppu->line[screen_x] = gbc_ppu_dmg_color((attr & 0x10) ? mmu->io[0x49] : mmu->io[0x48], color_id);
            }
        }
    }
}

void gbc_ppu_reset(gbc_t *gbc)
{
    gbc_memset(&gbc->ppu, 0, sizeof(gbc->ppu));
    for (uint8_t i = 0; i < 8; i++) {
        uint8_t base = (uint8_t)(i * 8);
        gbc->ppu.bg_palette[base + 0] = 0xFF;
        gbc->ppu.bg_palette[base + 1] = 0x7F;
        gbc->ppu.bg_palette[base + 2] = 0xB5;
        gbc->ppu.bg_palette[base + 3] = 0x56;
        gbc->ppu.bg_palette[base + 4] = 0x4A;
        gbc->ppu.bg_palette[base + 5] = 0x29;
        gbc->ppu.bg_palette[base + 6] = 0x00;
        gbc->ppu.bg_palette[base + 7] = 0x00;
        gbc_memcpy(&gbc->ppu.obj_palette[base], &gbc->ppu.bg_palette[base], 8);
    }
}

void gbc_ppu_update_lyc(gbc_t *gbc)
{
    uint8_t stat = gbc->mmu.io[0x41];

    if (gbc->mmu.io[0x44] == gbc->mmu.io[0x45]) {
        if ((stat & 0x04) == 0 && (stat & 0x40)) {
            gbc_mmu_request_interrupt(gbc, GBC_IF_LCD);
        }
        gbc->mmu.io[0x41] = stat | 0x04;
    } else {
        gbc->mmu.io[0x41] = stat & (uint8_t)~0x04;
    }
}

void gbc_ppu_render_scanline(gbc_t *gbc, uint8_t ly)
{
    gbc_color_t white = gbc_ppu_dmg_color(0xFC, 0);

    if ((gbc->mmu.io[0x40] & 0x80) == 0) {
        for (uint8_t x = 0; x < GBC_WIDTH; x++) {
            gbc->ppu.line[x] = white;
            gbc->ppu.bg_color_id[x] = 0;
            gbc->ppu.bg_priority[x] = 0;
            gbc->ppu.obj_drawn[x] = 0;
        }
    } else if ((gbc->mmu.io[0x40] & 0x01) || gbc->model == GBC_MODEL_CGB) {
        gbc_memset(gbc->ppu.obj_drawn, 0, sizeof(gbc->ppu.obj_drawn));
        if (gbc_ppu_render_bg_window(gbc, ly)) {
            gbc->ppu.win_line++;
        }
        gbc_ppu_render_sprites(gbc, ly);
    } else {
        for (uint8_t x = 0; x < GBC_WIDTH; x++) {
            gbc->ppu.line[x] = white;
            gbc->ppu.bg_color_id[x] = 0;
            gbc->ppu.bg_priority[x] = 0;
            gbc->ppu.obj_drawn[x] = 0;
        }
        gbc_ppu_render_sprites(gbc, ly);
    }

#if (GBC_RAM_LACK == 1)
    gbc_memcpy(&gbc->gbc_draw_data[(ly % (GBC_HEIGHT / 2)) * GBC_WIDTH], gbc->ppu.line, sizeof(gbc->ppu.line));
    if (gbc_ppu_should_draw(gbc) && (ly == (GBC_HEIGHT / 2 - 1) || ly == (GBC_HEIGHT - 1))) {
        uint8_t y1 = (ly < GBC_HEIGHT / 2) ? 0 : (GBC_HEIGHT / 2);
        gbc_draw(0, y1, GBC_WIDTH - 1, ly, gbc->gbc_draw_data);
    }
#else
    gbc_memcpy(&gbc->gbc_draw_data[ly * GBC_WIDTH], gbc->ppu.line, sizeof(gbc->ppu.line));
#endif
}

void gbc_ppu_step(gbc_t *gbc, uint8_t cycles)
{
    uint8_t ly;

    if ((gbc->mmu.io[0x40] & 0x80) == 0) {
        gbc->ppu.dot_cycles = 0;
        gbc->mmu.io[0x44] = 0;
        gbc_ppu_set_mode(gbc, 0);
        return;
    }

    gbc->ppu.dot_cycles = (uint16_t)(gbc->ppu.dot_cycles + cycles);

    while (gbc->ppu.dot_cycles >= GBC_CYCLES_PER_LINE) {
        gbc->ppu.dot_cycles = (uint16_t)(gbc->ppu.dot_cycles - GBC_CYCLES_PER_LINE);
        ly = gbc->mmu.io[0x44];
        if (ly < GBC_HEIGHT) {
            gbc_ppu_render_scanline(gbc, ly);
        }
        ly++;
        gbc->mmu.io[0x44] = ly;

        if (ly == 144) {
            gbc_mmu_request_interrupt(gbc, GBC_IF_VBLANK);
            gbc_ppu_set_mode(gbc, 1);
#if (GBC_RAM_LACK == 0)
            if (gbc_ppu_should_draw(gbc)) {
                gbc_draw(0, 0, GBC_WIDTH - 1, GBC_HEIGHT - 1, gbc->gbc_draw_data);
            }
#endif
            gbc->ppu.frame_ready = 1;
        } else if (ly > 153) {
            gbc->mmu.io[0x44] = 0;
            gbc->ppu.win_line = 0;
            gbc->ppu.frame_ready = 0;
        }

        gbc_ppu_update_lyc(gbc);
    }

    /* Update LCD mode based on actual position within the current scanline.
     * Done after the while loop so dot_cycles is guaranteed < GBC_CYCLES_PER_LINE
     * and we never compute mode from an accumulated (wrapped) value. */
    ly = gbc->mmu.io[0x44];
    if (ly < 144) {
        uint8_t mode;
        if (gbc->ppu.dot_cycles < 80) {
            mode = 2;
        } else if (gbc->ppu.dot_cycles < gbc_ppu_mode3_end(gbc, ly)) {
            mode = 3;
        } else {
            mode = 0;
        }
        gbc_ppu_set_mode(gbc, mode);
    }
    /* VBlank mode (1) is already set inside the while loop when ly becomes 144. */
}


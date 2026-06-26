/*
 * Copyright PeakRacing
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "nes.h"

/* https://www.nesdev.org/wiki/INES_Mapper_095
 * Mapper 95 - Namcot 108 Rev. B (Dragon Buster).
 * The register interface is Namco 118-like, but CHR data bit5 selects the
 * one-screen nametable page for the corresponding 1KB pattern slot.
 */

typedef struct {
    uint8_t reg_select;
    uint8_t prg[2];
    uint8_t chr[6];
    uint8_t mirror_cache[8];
    uint8_t last_ppu_slot;
    uint8_t current_mirror;
    uint8_t in_background;
} mapper95_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper95_apply_mirror(nes_t* nes, uint8_t slot) {
    mapper95_t* r = (mapper95_t*)nes->nes_mapper.mapper_register;
    const uint8_t mirror = r->mirror_cache[slot & 0x07u] & 0x01u;
    if (r->current_mirror == mirror) return;

    r->current_mirror = mirror;
    for (uint8_t i = 0; i < 4u; i++) {
        nes->nes_ppu.name_table[i] = nes->nes_ppu.ppu_vram[mirror];
        nes->nes_ppu.name_table_mirrors[i] = nes->nes_ppu.name_table[i];
    }
}

static void mapper95_sync(nes_t* nes) {
    mapper95_t* r = (mapper95_t*)nes->nes_mapper.mapper_register;
    const uint16_t prg_count = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);

    nes_load_prgrom_8k(nes, 0, r->prg[0]);
    nes_load_prgrom_8k(nes, 1, r->prg[1]);
    nes_load_prgrom_8k(nes, 2, prg_count > 1u ? (uint16_t)(prg_count - 2u) : 0u);
    nes_load_prgrom_8k(nes, 3, prg_count > 0u ? (uint16_t)(prg_count - 1u) : 0u);
    mapper95_apply_mirror(nes, r->last_ppu_slot);

    if (nes->nes_rom.chr_rom_size == 0u) return;

    nes_load_chrrom_1k(nes, 0, (uint16_t)(r->chr[0] & 0x1Eu));
    nes_load_chrrom_1k(nes, 1, (uint16_t)((r->chr[0] & 0x1Eu) + 1u));
    nes_load_chrrom_1k(nes, 2, (uint16_t)(r->chr[1] & 0x1Eu));
    nes_load_chrrom_1k(nes, 3, (uint16_t)((r->chr[1] & 0x1Eu) + 1u));
    nes_load_chrrom_1k(nes, 4, r->chr[2]);
    nes_load_chrrom_1k(nes, 5, r->chr[3]);
    nes_load_chrrom_1k(nes, 6, r->chr[4]);
    nes_load_chrrom_1k(nes, 7, r->chr[5]);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper95_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper95_t* r = (mapper95_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper95_t));
    r->current_mirror = 0xFFu;

    if (nes->nes_rom.chr_rom_size == 0u) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
    mapper95_sync(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper95_t* r = (mapper95_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF001u) {
    case 0x8000:
        r->reg_select = data;
        break;
    case 0x8001:
        switch (r->reg_select & 0x07u) {
        case 0:
            r->chr[0] = data & 0x1Fu;
            r->mirror_cache[0] = r->mirror_cache[1] = (data >> 5u) & 0x01u;
            mapper95_sync(nes);
            break;
        case 1:
            r->chr[1] = data & 0x1Fu;
            r->mirror_cache[2] = r->mirror_cache[3] = (data >> 5u) & 0x01u;
            mapper95_sync(nes);
            break;
        case 2:
            r->chr[2] = data & 0x1Fu;
            r->mirror_cache[4] = (data >> 5u) & 0x01u;
            mapper95_sync(nes);
            break;
        case 3:
            r->chr[3] = data & 0x1Fu;
            r->mirror_cache[5] = (data >> 5u) & 0x01u;
            mapper95_sync(nes);
            break;
        case 4:
            r->chr[4] = data & 0x1Fu;
            r->mirror_cache[6] = (data >> 5u) & 0x01u;
            mapper95_sync(nes);
            break;
        case 5:
            r->chr[5] = data & 0x1Fu;
            r->mirror_cache[7] = (data >> 5u) & 0x01u;
            mapper95_sync(nes);
            break;
        case 6:
            r->prg[0] = data;
            mapper95_sync(nes);
            break;
        case 7:
            r->prg[1] = data;
            mapper95_sync(nes);
            break;
        default:
            break;
        }
        break;
    default:
        break;
    }
}

static void nes_mapper_ppu(nes_t* nes, uint16_t address) {
    mapper95_t* r = (mapper95_t*)nes->nes_mapper.mapper_register;
    if (r == NULL || !r->in_background || address >= 0x2000u) return;

    r->last_ppu_slot = (uint8_t)(address >> 10u);
    mapper95_apply_mirror(nes, r->last_ppu_slot);
}

static void nes_mapper_render_screen(nes_t* nes, uint8_t mode) {
    mapper95_t* r = (mapper95_t*)nes->nes_mapper.mapper_register;
    if (r == NULL) return;

    r->in_background = mode ? 1u : 0u;
    if (r->in_background) {
        mapper95_apply_mirror(nes, r->last_ppu_slot);
    }
}

int nes_mapper95_init(nes_t* nes) {
    nes->nes_mapper.mapper_init     = nes_mapper_init;
    nes->nes_mapper.mapper_deinit   = nes_mapper_deinit;
    nes->nes_mapper.mapper_write    = nes_mapper_write;
    nes->nes_mapper.mapper_ppu      = nes_mapper_ppu;
    nes->nes_mapper.mapper_ppu_tile_min = 0x00u;
    nes->nes_mapper.mapper_ppu_tile_max = 0xFFu;
    nes->nes_mapper.mapper_render_screen = nes_mapper_render_screen;
    return NES_OK;
}

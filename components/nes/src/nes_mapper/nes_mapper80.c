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

/* https://www.nesdev.org/wiki/INES_Mapper_080
 * Mapper 80 - Taito X1-005.
 * PRG: 3x8KB switchable + 8KB fixed last bank.
 * CHR: 2x2KB banks at $0000/$0800 + 4x1KB banks at $1000-$1C00.
 * All registers accessed via SRAM area $7EF0-$7EFF (mapper_sram callback).
 * Mirror: controlled by $7EF6/$7EF7.
 */

typedef struct {
    uint8_t chr[6];
    uint8_t prg[3];
    uint8_t mirror;
} mapper80_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper80_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper80_register_t* r = (mapper80_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper80_register_t));

    uint8_t prg_banks = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 0);
    nes_load_prgrom_8k(nes, 2, 0);
    nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_banks - 1u));

    if (nes->nes_rom.chr_rom_size == 0)
        nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper80_register_t* r = (mapper80_register_t*)nes->nes_mapper.mapper_register;
    switch (address) {
    case 0x7EF0u:
        r->chr[0] = (uint8_t)(data & 0x7Fu);
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_1k(nes, 0, (uint8_t)(r->chr[0] & 0xFEu));
            nes_load_chrrom_1k(nes, 1, (uint8_t)(r->chr[0] | 0x01u));
        }
        break;
    case 0x7EF1u:
        r->chr[1] = (uint8_t)(data & 0x7Fu);
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_1k(nes, 2, (uint8_t)(r->chr[1] & 0xFEu));
            nes_load_chrrom_1k(nes, 3, (uint8_t)(r->chr[1] | 0x01u));
        }
        break;
    case 0x7EF2u:
        r->chr[2] = data;
        if (nes->nes_rom.chr_rom_size > 0) nes_load_chrrom_1k(nes, 4, r->chr[2]);
        break;
    case 0x7EF3u:
        r->chr[3] = data;
        if (nes->nes_rom.chr_rom_size > 0) nes_load_chrrom_1k(nes, 5, r->chr[3]);
        break;
    case 0x7EF4u:
        r->chr[4] = data;
        if (nes->nes_rom.chr_rom_size > 0) nes_load_chrrom_1k(nes, 6, r->chr[4]);
        break;
    case 0x7EF5u:
        r->chr[5] = data;
        if (nes->nes_rom.chr_rom_size > 0) nes_load_chrrom_1k(nes, 7, r->chr[5]);
        break;
    case 0x7EF6u:
    case 0x7EF7u:
        r->mirror = (uint8_t)(data & 0x01u);
        if (nes->nes_rom.four_screen == 0)
            nes_ppu_screen_mirrors(nes, r->mirror ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        break;
    case 0x7EFBu:
        r->prg[0] = (uint8_t)(data & 0x3Fu);
        nes_load_prgrom_8k(nes, 0, r->prg[0]);
        break;
    case 0x7EFCu:
        r->prg[1] = (uint8_t)(data & 0x3Fu);
        nes_load_prgrom_8k(nes, 1, r->prg[1]);
        break;
    case 0x7EFDu:
        r->prg[2] = (uint8_t)(data & 0x3Fu);
        nes_load_prgrom_8k(nes, 2, r->prg[2]);
        break;
    default:
        break;
    }
}

int nes_mapper80_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    return NES_OK;
}

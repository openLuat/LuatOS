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

/* https://www.nesdev.org/wiki/INES_Mapper_032
 * Mapper 32 - Irem G-101.
 * PRG: 2 switchable 8KB banks at $8000/$A000; $C000/$E000 fixed to last 2 banks.
 * Mode bit: when prg_mode=1, $8000 is fixed to second-last, $C000 is switchable.
 * CHR: 8x1KB switchable banks at $B000-$B007.
 * Mirror: bit 0 of $9000 (0=V, 1=H).
 * WRAM: 8KB at $6000-$7FFF.
 */

typedef struct {
    uint8_t prg[2];
    uint8_t chr[8];
    uint8_t mirror;
    uint8_t prg_mode;
    uint8_t prg_bank_count; /* 8KB units */
} mapper32_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper32_update_prg(nes_t* nes) {
    mapper32_register_t* r = (mapper32_register_t*)nes->nes_mapper.mapper_register;
    uint8_t last  = (uint8_t)(r->prg_bank_count - 1u);
    uint8_t slast = (uint8_t)(r->prg_bank_count - 2u);
    if (r->prg_mode == 0) {
        nes_load_prgrom_8k(nes, 0, (uint16_t)(r->prg[0] % r->prg_bank_count));
        nes_load_prgrom_8k(nes, 1, (uint16_t)(r->prg[1] % r->prg_bank_count));
        nes_load_prgrom_8k(nes, 2, slast);
        nes_load_prgrom_8k(nes, 3, last);
    } else {
        nes_load_prgrom_8k(nes, 0, slast);
        nes_load_prgrom_8k(nes, 1, (uint16_t)(r->prg[1] % r->prg_bank_count));
        nes_load_prgrom_8k(nes, 2, (uint16_t)(r->prg[0] % r->prg_bank_count));
        nes_load_prgrom_8k(nes, 3, last);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper32_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper32_register_t* r = (mapper32_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper32_register_t));

    r->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    uint8_t last  = (uint8_t)(r->prg_bank_count - 1u);
    uint8_t slast = (uint8_t)(r->prg_bank_count - 2u);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 0);
    nes_load_prgrom_8k(nes, 2, slast);
    nes_load_prgrom_8k(nes, 3, last);

    if (nes->nes_rom.chr_rom_size == 0)
        nes_load_chrrom_8k(nes, 0, 0);
    else
        nes_load_chrrom_8k(nes, 0, 0);

    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        } else {
            NES_LOG_ERROR("mapper32: failed to allocate SRAM\n");
        }
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper32_register_t* r = (mapper32_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u:
        r->prg[0] = (uint8_t)(data & 0x1Fu);
        mapper32_update_prg(nes);
        break;
    case 0x9000u:
        r->mirror   = (uint8_t)(data & 0x01u);
        r->prg_mode = (uint8_t)((data >> 1) & 0x01u);
        if (nes->nes_rom.four_screen == 0)
            nes_ppu_screen_mirrors(nes, r->mirror ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        mapper32_update_prg(nes);
        break;
    case 0xA000u:
        r->prg[1] = (uint8_t)(data & 0x1Fu);
        mapper32_update_prg(nes);
        break;
    case 0xB000u:
        {
            uint8_t slot = (uint8_t)(address & 0x07u);
            r->chr[slot] = data;
            if (nes->nes_rom.chr_rom_size > 0) {
                const uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
                nes_load_chrrom_1k(nes, slot, (uint8_t)(r->chr[slot] % chr_banks));
            }
        }
        break;
    default:
        break;
    }
}

int nes_mapper32_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

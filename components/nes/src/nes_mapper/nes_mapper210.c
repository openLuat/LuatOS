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

/* https://www.nesdev.org/wiki/INES_Mapper_210
 * Mapper 210 — Namco 175/340 (simplified Namco 163, no audio).
 * PRG 8KB × 4 + CHR 1KB × 8 (no expansion audio).
 * Shares register structure with mapper 19 but without audio.
 */

typedef struct {
    uint8_t  prg[3];            /* 8KB banks at $8000/$A000/$C000 */
    uint8_t  chr[8];            /* 1KB CHR banks */
    uint16_t prg_bank_count;    /* total 8KB PRG bank count */
    uint16_t chr_bank_count;    /* total 1KB CHR bank count */
} mapper210_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper210_update_banks(nes_t* nes) {
    mapper210_t* m = (mapper210_t*)nes->nes_mapper.mapper_register;
    uint16_t last  = (uint16_t)(m->prg_bank_count - 1u);
    nes_load_prgrom_8k(nes, 0, (uint16_t)(m->prg[0] % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 1, (uint16_t)(m->prg[1] % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 2, (uint16_t)(m->prg[2] % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 3, last);
    if (m->chr_bank_count > 0u) {
        for (uint8_t i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, (uint16_t)(m->chr[i] % m->chr_bank_count));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper210_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper210_t* m = (mapper210_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper210_t));
    m->prg_bank_count = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper210_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper210_t* m = (mapper210_t*)nes->nes_mapper.mapper_register;
    if (address < 0xC000u) {
        /* $8000-$BFFF: CHR 1KB banks 0-7, one register per $800 bytes */
        uint8_t slot = (uint8_t)((address & 0x3800u) >> 11u);
        m->chr[slot] = data;
    } else {
        switch (address & 0xF800u) {
        case 0xE000u: m->prg[0] = data & 0x3Fu; break;  /* PRG bank at $8000 */
        case 0xE800u: m->prg[1] = data & 0x3Fu; break;  /* PRG bank at $A000 */
        case 0xF000u: m->prg[2] = data & 0x3Fu; break;  /* PRG bank at $C000 */
        default: return;
        }
    }
    mapper210_update_banks(nes);
}

int nes_mapper210_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

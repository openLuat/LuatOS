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
    uint8_t prg[4];
    uint8_t chr[8];
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper210_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper210_update_banks(nes_t* nes) {
    mapper210_t* m = (mapper210_t*)nes->nes_mapper.mapper_register;
    uint8_t last  = (uint8_t)(m->prg_bank_count - 1u);
    nes_load_prgrom_8k(nes, 0, m->prg[0] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 2, m->prg[2] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 3, last);
    if (m->chr_bank_count > 0u) {
        for (uint8_t i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, (uint8_t)(m->chr[i] % m->chr_bank_count));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper210_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper210_t* m = (mapper210_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper210_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper210_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper210_t* m = (mapper210_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF800u) {
    case 0x8000u: case 0x8800u: m->chr[0] = data; mapper210_update_banks(nes); break;
    case 0x9000u: case 0x9800u: m->chr[1] = data; mapper210_update_banks(nes); break;
    case 0xA000u: case 0xA800u: m->chr[2] = data; mapper210_update_banks(nes); break;
    case 0xB000u: case 0xB800u: m->chr[3] = data; mapper210_update_banks(nes); break;
    case 0xC000u: case 0xC800u: m->chr[4] = data; mapper210_update_banks(nes); break;
    case 0xD000u: case 0xD800u: m->chr[5] = data; mapper210_update_banks(nes); break;
    case 0xE000u: case 0xE800u: m->chr[6] = data; mapper210_update_banks(nes); break;
    case 0xF000u:               m->chr[7] = data; mapper210_update_banks(nes); break;
    case 0xF800u:
        if ((address & 0x01u) == 0u) {
            m->prg[0] = data & 0x3Fu; mapper210_update_banks(nes);
        } else {
            m->prg[1] = data & 0x3Fu; mapper210_update_banks(nes);
        }
        break;
    default: break;
    }
}

int nes_mapper210_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

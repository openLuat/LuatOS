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

/* https://www.nesdev.org/wiki/INES_Mapper_050
 * Mapper 50 — FDS port pirate (SMB2 Japan FDS→Famicom cart).
 * PRG: 8KB switchable at $6000 (via $4020 APU regs), rest fixed.
 * CHR: 8KB fixed.
 */

typedef struct {
    uint8_t prg_bank;
    uint8_t prg_bank_count;
} mapper50_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper50_update_banks(nes_t* nes) {
    mapper50_t* m = (mapper50_t*)nes->nes_mapper.mapper_register;
    /* Fixed banks: $8000=bank8, $A000=bank9, $C000=bank4, $E000=last */
    uint8_t last = (uint8_t)(m->prg_bank_count - 1u);
    nes_load_prgrom_8k(nes, 0, (uint8_t)(m->prg_bank % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 1, 8u % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 2, 9u % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 3, last);
    if (nes->nes_rom.chr_rom_size == 0u) nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper50_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper50_t* m = (mapper50_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper50_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    if (m->prg_bank_count == 0u) m->prg_bank_count = 1u;
    mapper50_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper50_t* m = (mapper50_t*)nes->nes_mapper.mapper_register;
    (void)address;
    /* bits[3,5] of data form the 8KB bank index */
    m->prg_bank = (uint8_t)(((data & 0x08u) >> 3u) | ((data & 0x20u) >> 4u));
    mapper50_update_banks(nes);
}

int nes_mapper50_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    return NES_OK;
}

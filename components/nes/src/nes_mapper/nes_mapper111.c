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

/* https://www.nesdev.org/wiki/INES_Mapper_111
 * Mapper 111 — GTROM (Cheapo / Power Punch II homebrew).
 * Single bit select at $5000:
 *   bit0: PRG bank select (32KB blocks)
 *   bit4: CHR bank select (32KB blocks)
 */

typedef struct {
    uint8_t reg;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper111_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper111_update_banks(nes_t* nes) {
    mapper111_t* m = (mapper111_t*)nes->nes_mapper.mapper_register;
    uint8_t prg4 = (uint8_t)(m->prg_bank_count / 4u);
    uint8_t chr4 = (uint8_t)(m->chr_bank_count / 4u);
    if (prg4 == 0u) prg4 = 1u;
    if (chr4 == 0u) chr4 = 1u;
    nes_load_prgrom_32k(nes, 0, (uint16_t)((m->reg & 0x01u) % prg4));
    if (m->chr_bank_count > 0u)
        nes_load_chrrom_8k(nes, 0, (uint8_t)(((m->reg >> 4u) & 0x01u) % (chr4 * 2u)));
    else
        nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper111_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper111_t* m = (mapper111_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper111_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper111_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper111_t* m = (mapper111_t*)nes->nes_mapper.mapper_register;
    if (address == 0x5000u) {
        m->reg = data;
        mapper111_update_banks(nes);
    }
}

int nes_mapper111_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    return NES_OK;
}

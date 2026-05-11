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

/* https://www.nesdev.org/wiki/INES_Mapper_167
 * Mapper 167 — SUBOR Type 2.
 * Like mapper 166 but register writes slightly differ.
 * Simplified: use same logic as mapper 166.
 */

typedef struct {
    uint8_t regs[4];
    uint8_t accum;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper167_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper167_update_banks(nes_t* nes) {
    mapper167_t* m = (mapper167_t*)nes->nes_mapper.mapper_register;
    for (uint8_t i = 0u; i < 4u; i++)
        nes_load_prgrom_8k(nes, i, m->regs[i] % (m->prg_bank_count > 0u ? m->prg_bank_count : 1u));
    if (m->chr_bank_count > 0u) {
        uint8_t chr8 = (uint8_t)(m->chr_bank_count / 8u);
        if (chr8 == 0u) chr8 = 1u;
        nes_load_chrrom_8k(nes, 0, (uint8_t)(m->accum % chr8));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper167_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper167_t* m = (mapper167_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper167_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper167_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper167_t* m = (mapper167_t*)nes->nes_mapper.mapper_register;
    uint8_t idx = (uint8_t)((address >> 13u) & 0x03u);
    m->accum = (uint8_t)((m->accum << 2u) | (data & 0x03u));
    m->regs[idx] = m->accum & 0x1Fu;
    mapper167_update_banks(nes);
}

int nes_mapper167_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

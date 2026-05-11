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

/* https://www.nesdev.org/wiki/INES_Mapper_147
 * Mapper 147 — TC-U01 (Sachen).
 * Like mapper 136 but register addresses slightly differ.
 * Simplified: APU write selects register, SRAM write sets data.
 */

typedef struct {
    uint8_t regs[8];
    uint8_t reg_sel;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper147_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper147_update_banks(nes_t* nes) {
    mapper147_t* m = (mapper147_t*)nes->nes_mapper.mapper_register;
    uint8_t prg32 = (uint8_t)(m->prg_bank_count / 4u);
    uint8_t chr8  = (uint8_t)(m->chr_bank_count / 8u);
    if (prg32 == 0u) prg32 = 1u;
    if (chr8  == 0u) chr8  = 1u;
    nes_load_prgrom_32k(nes, 0, (uint16_t)((m->regs[5] & 0x03u) % prg32));
    nes_load_chrrom_8k(nes, 0, (uint8_t)((m->regs[0] & 0x0Fu) % chr8));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper147_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper147_t* m = (mapper147_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper147_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper147_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper147_t* m = (mapper147_t*)nes->nes_mapper.mapper_register;
    (void)data;
    m->reg_sel = address & 0x07u;
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper147_t* m = (mapper147_t*)nes->nes_mapper.mapper_register;
    (void)address;
    m->regs[m->reg_sel] = data;
    mapper147_update_banks(nes);
}

int nes_mapper147_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    return NES_OK;
}

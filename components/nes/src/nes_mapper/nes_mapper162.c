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

/* https://www.nesdev.org/wiki/INES_Mapper_162
 * Mapper 162 — Waixing variant (simplified pirate).
 * PRG 16KB × 2 switchable + CHR 8KB fixed.
 * Register at $8000: bits[3:0] → PRG 16KB bank pair.
 */

typedef struct {
    uint8_t regs[4];
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper162_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper162_update_banks(nes_t* nes) {
    mapper162_t* m = (mapper162_t*)nes->nes_mapper.mapper_register;
    uint8_t prg16 = (uint8_t)(m->prg_bank_count / 2u);
    if (prg16 == 0u) prg16 = 1u;
    uint8_t bank = (uint8_t)(((m->regs[0] & 0x0Fu) | ((m->regs[2] & 0x01u) << 4u)) % prg16);
    nes_load_prgrom_16k(nes, 0, (uint16_t)bank);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(prg16 - 1u));
    if (nes->nes_rom.chr_rom_size == 0u)
        nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper162_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper162_t* m = (mapper162_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper162_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    m->regs[3] = 0x07u;
    mapper162_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper162_t* m = (mapper162_t*)nes->nes_mapper.mapper_register;
    uint8_t idx = (uint8_t)((address >> 13u) & 0x03u);
    m->regs[idx] = data;
    mapper162_update_banks(nes);
}

int nes_mapper162_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

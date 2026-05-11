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

/* https://www.nesdev.org/wiki/INES_Mapper_121
 * Mapper 121 — Panda Prince pirate (Punch-Out!!/SMB3 pirate).
 * Like mapper 3 (CNROM) but with extra CHR high bits at $A001.
 * PRG 32KB fixed + CHR 8KB switchable.
 */

typedef struct {
    uint8_t chr_bank;
    uint8_t chr_bank_count;
} mapper121_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper121_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper121_t* m = (mapper121_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper121_t));
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) m->chr_bank_count = 1u;
    nes_load_prgrom_32k(nes, 0, 0);
    nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper121_t* m = (mapper121_t*)nes->nes_mapper.mapper_register;
    if ((address & 0xA001u) == 0xA001u) {
        /* high CHR bits from $A001 */
        m->chr_bank = (uint8_t)((m->chr_bank & 0x0Fu) | ((data & 0x03u) << 4u));
    } else if (address >= 0x8000u) {
        /* low CHR bits */
        m->chr_bank = (uint8_t)((m->chr_bank & 0x30u) | (data & 0x0Fu));
    }
    nes_load_chrrom_8k(nes, 0, (uint8_t)(m->chr_bank % m->chr_bank_count));
}

int nes_mapper121_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

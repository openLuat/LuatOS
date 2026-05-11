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

/* https://www.nesdev.org/wiki/INES_Mapper_139
 * Mapper 139 — Sachen 8259C.
 * Like 8259D but CHR banks are 1KB each (8 banks total per group).
 * R0 bits[2:0] × 4: CHR group at $0000; R1×4: $1000; etc.
 */

typedef struct {
    uint8_t regs[8];
    uint8_t reg_sel;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper139_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper139_update_banks(nes_t* nes) {
    mapper139_t* m = (mapper139_t*)nes->nes_mapper.mapper_register;

    if (m->prg_bank_count > 0u) {
        uint8_t prg = m->regs[5] % m->prg_bank_count;
        uint8_t last = (uint8_t)(m->prg_bank_count - 1u);
        nes_load_prgrom_8k(nes, 0, prg);
        nes_load_prgrom_8k(nes, 1, prg);
        nes_load_prgrom_8k(nes, 2, last);
        nes_load_prgrom_8k(nes, 3, last);
    }

    if (m->chr_bank_count > 0u) {
        /* 8259C: R0 × 8, R1 × 8 for upper/lower halves */
        uint8_t lo = (uint8_t)((m->regs[0] * 8u) % m->chr_bank_count);
        uint8_t hi = (uint8_t)((m->regs[1] * 8u) % m->chr_bank_count);
        for (uint8_t i = 0u; i < 4u; i++) {
            nes_load_chrrom_1k(nes, i,              (uint8_t)((lo + i) % m->chr_bank_count));
            nes_load_chrrom_1k(nes, (uint8_t)(i+4u),(uint8_t)((hi + i) % m->chr_bank_count));
        }
    }

    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, (m->regs[4] & 1u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper139_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper139_t* m = (mapper139_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper139_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper139_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper139_t* m = (mapper139_t*)nes->nes_mapper.mapper_register;
    if ((address & 0xFFu) == 0x00u)
        m->reg_sel = data & 0x07u;
    else if ((address & 0xFFu) == 0x01u) {
        m->regs[m->reg_sel] = data;
        mapper139_update_banks(nes);
    }
}

int nes_mapper139_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    return NES_OK;
}

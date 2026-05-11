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

/* https://www.nesdev.org/wiki/INES_Mapper_141
 * Mapper 141 — Sachen 8259A.
 * PRG: 32KB pages at $8000-$FFFF, switched by R5.
 * CHR: 4 × 2KB pages — 8259A formula: shift=1, chrOr={0,1,0,1}.
 *   Page n (2KB): page_idx = ((chrHigh | (R[n]&7)) << 1) | (n & 1)
 *   where chrHigh = (R4 & 7) << 3.
 * R4 bit 0: 0=vertical mirror, 1=horizontal mirror.
 */

typedef struct {
    uint8_t regs[8];
    uint8_t reg_sel;
    uint8_t prg_bank_count32;   /* number of 32KB PRG blocks */
    uint16_t chr_bank_count;    /* 1KB CHR bank total, max 256 requires uint16_t */
} mapper141_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper141_update_banks(nes_t* nes) {
    mapper141_t* m = (mapper141_t*)nes->nes_mapper.mapper_register;

    /* PRG: 32KB banking — R5 selects 32KB block */
    if (m->prg_bank_count32 > 0u) {
        uint8_t prg32 = m->regs[5] % m->prg_bank_count32;
        nes_load_prgrom_32k(nes, 0, prg32);
    }

    /* CHR: 4 × 2KB pages — Sachen 8259A formula
     * page_idx = ((chrHigh | (R[p] & 7)) << 1) | (p & 1)
     * chrHigh = (R4 & 7) << 3  */
    if (m->chr_bank_count > 0u) {
        uint16_t total_2k = m->chr_bank_count / 2u;
        if (total_2k == 0u) total_2k = 1u;
        uint8_t chrHigh = (uint8_t)((m->regs[4] & 0x07u) << 3u);
        for (uint8_t p = 0u; p < 4u; p++) {
            uint16_t page = (uint16_t)(((uint16_t)(chrHigh | (m->regs[p] & 0x07u)) << 1u) | (p & 1u));
            page %= total_2k;
            nes_load_chrrom_1k(nes, (uint8_t)(p * 2u),      (uint16_t)(page * 2u));
            nes_load_chrrom_1k(nes, (uint8_t)(p * 2u + 1u), (uint16_t)(page * 2u + 1u));
        }
    }

    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, (m->regs[4] & 1u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper141_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper141_t* m = (mapper141_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper141_t));
    m->prg_bank_count32 = (uint8_t)(nes->nes_rom.prg_rom_size / 2u);
    if (m->prg_bank_count32 == 0u) m->prg_bank_count32 = 1u;
    m->chr_bank_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper141_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper141_t* m = (mapper141_t*)nes->nes_mapper.mapper_register;
    if ((address & 0xFFu) == 0x00u)
        m->reg_sel = data & 0x07u;
    else if ((address & 0xFFu) == 0x01u) {
        m->regs[m->reg_sel] = data;
        mapper141_update_banks(nes);
    }
}

int nes_mapper141_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    return NES_OK;
}

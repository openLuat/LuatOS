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

/* https://www.nesdev.org/wiki/INES_Mapper_041
 * Mapper 41 — Caltron 6-in-1.
 * Outer bank select from $6000-$67FF range (SRAM write range):
 *   bits[2:0]: PRG 32KB outer, bits[5:3]: CHR 8KB outer, bit6: CHR inner enable
 * Inner CHR 8KB bank via $8000-$FFFF bits[1:0].
 */

typedef struct {
    uint8_t outer;
    uint8_t inner_chr;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper41_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper41_update_banks(nes_t* nes) {
    mapper41_t* m = (mapper41_t*)nes->nes_mapper.mapper_register;
    uint8_t prg32 = (uint8_t)(m->prg_bank_count / 4u);
    uint8_t chr8  = (uint8_t)(m->chr_bank_count / 8u);
    if (prg32 == 0u) prg32 = 1u;
    if (chr8  == 0u) chr8  = 1u;

    uint8_t prg = (m->outer & 0x07u) % prg32;
    /* outer CHR base × 4 + inner 2-bit */
    uint8_t chr_outer = (m->outer >> 3u) & 0x07u;
    uint8_t chr = (uint8_t)((chr_outer * 4u + (m->outer & 0x40u ? m->inner_chr & 0x03u : 0u)) % chr8);

    nes_load_prgrom_32k(nes, 0, (uint16_t)prg);
    nes_load_chrrom_8k(nes, 0, chr);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper41_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper41_t* m = (mapper41_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper41_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper41_update_banks(nes);
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper41_t* m = (mapper41_t*)nes->nes_mapper.mapper_register;
    if (address <= 0x67FFu) {
        m->outer = data & 0x7Fu;
        mapper41_update_banks(nes);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper41_t* m = (mapper41_t*)nes->nes_mapper.mapper_register;
    (void)address;
    if (m->outer & 0x40u) {
        m->inner_chr = data & 0x03u;
        mapper41_update_banks(nes);
    }
}

int nes_mapper41_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_155
 * Mapper 155 — MMC1A (SxROM variant A).
 * Identical to mapper 1 (MMC1) for banking purposes.
 * The only difference is WRAM is always enabled (no disable bit).
 * Delegate to mapper 1 logic by using same implementation.
 */

typedef struct {
    uint8_t shift_reg;
    uint8_t shift_count;
    uint8_t control;
    uint8_t chr0;
    uint8_t chr1;
    uint8_t prg;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper155_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper155_apply(nes_t* nes) {
    mapper155_t* m = (mapper155_t*)nes->nes_mapper.mapper_register;
    uint8_t mirror = m->control & 0x03u;
    switch (mirror) {
    case 0u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
    case 1u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
    case 2u: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
    default: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
    }
    uint8_t prg_mode = (m->control >> 2u) & 0x03u;
    if (m->prg_bank_count > 0u) {
        uint8_t prg_banks16 = (uint8_t)(m->prg_bank_count / 2u);
        if (prg_banks16 == 0u) prg_banks16 = 1u;
        switch (prg_mode) {
        case 0u:
        case 1u:
            nes_load_prgrom_32k(nes, 0, (uint16_t)((m->prg >> 1u) % (prg_banks16 / 2u > 0u ? prg_banks16 / 2u : 1u)));
            break;
        case 2u:
            nes_load_prgrom_16k(nes, 0, 0);
            nes_load_prgrom_16k(nes, 1, (uint16_t)(m->prg % prg_banks16));
            break;
        case 3u:
            nes_load_prgrom_16k(nes, 0, (uint16_t)(m->prg % prg_banks16));
            nes_load_prgrom_16k(nes, 1, (uint16_t)(prg_banks16 - 1u));
            break;
        }
    }
    if (m->chr_bank_count > 0u) {
        uint8_t chr_mode = (m->control >> 4u) & 1u;
        uint8_t chr4 = (uint8_t)(m->chr_bank_count / 4u);
        uint8_t chr8 = (uint8_t)(m->chr_bank_count / 8u);
        if (chr4 == 0u) chr4 = 1u;
        if (chr8 == 0u) chr8 = 1u;
        if (chr_mode) {
            nes_load_chrrom_4k(nes, 0, (uint8_t)(m->chr0 % chr4));
            nes_load_chrrom_4k(nes, 1, (uint8_t)(m->chr1 % chr4));
        } else {
            nes_load_chrrom_8k(nes, 0, (uint8_t)((m->chr0 >> 1u) % chr8));
        }
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper155_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper155_t* m = (mapper155_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper155_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    m->control = 0x0Cu;
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper155_apply(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper155_t* m = (mapper155_t*)nes->nes_mapper.mapper_register;
    if (data & 0x80u) {
        m->shift_reg = 0;
        m->shift_count = 0;
        m->control |= 0x0Cu;
        mapper155_apply(nes);
        return;
    }
    m->shift_reg = (uint8_t)(m->shift_reg | ((data & 1u) << m->shift_count));
    m->shift_count++;
    if (m->shift_count < 5u) return;
    uint8_t val = m->shift_reg & 0x1Fu;
    m->shift_reg = 0;
    m->shift_count = 0;
    switch ((address >> 13u) & 0x03u) {
    case 0u: m->control = val; break;
    case 1u: m->chr0    = val; break;
    case 2u: m->chr1    = val; break;
    case 3u: m->prg     = val & 0x0Fu; break;
    }
    mapper155_apply(nes);
}

int nes_mapper155_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

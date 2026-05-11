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

/* https://www.nesdev.org/wiki/INES_Mapper_028
 * Mapper 28 — Action 53 (meta-mapper for Famicom pirates).
 * Register select via $5100, data via $8000-$FFFF.
 * R0: CHR bank bits[1:0]; R1: outer PRG; R2: mirror; R3: inner bank + mode
 */

typedef struct {
    uint8_t regs[4];
    uint8_t reg_sel;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper28_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper28_update_banks(nes_t* nes) {
    mapper28_t* m = (mapper28_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_mode = (m->regs[3] >> 2u) & 0x03u;
    uint8_t outer    = (uint8_t)(m->regs[1] << 1u);
    uint8_t inner    = m->regs[3] & 0x0Fu;
    uint8_t prg16    = (uint8_t)(m->prg_bank_count / 2u);
    if (prg16 == 0u) prg16 = 1u;

    switch (prg_mode) {
    case 0u: case 1u:
        nes_load_prgrom_32k(nes, 0, (uint16_t)((outer | (inner >> 1u)) % (prg16 / 2u > 0u ? prg16 / 2u : 1u)));
        break;
    case 2u:
        nes_load_prgrom_16k(nes, 0, (uint16_t)(outer % prg16));
        nes_load_prgrom_16k(nes, 1, (uint16_t)((outer | (uint8_t)(prg16 - 1u)) % prg16));
        break;
    case 3u:
        nes_load_prgrom_16k(nes, 0, (uint16_t)((outer | inner) % prg16));
        nes_load_prgrom_16k(nes, 1, (uint16_t)((outer | 0x0Fu) % prg16));
        break;
    }

    if (m->chr_bank_count > 0u) {
        uint8_t chr8 = (uint8_t)(m->chr_bank_count / 8u);
        if (chr8 == 0u) chr8 = 1u;
        nes_load_chrrom_8k(nes, 0, (uint8_t)((m->regs[0] & 0x03u) % chr8));
    }

    if (nes->nes_rom.four_screen == 0) {
        switch (m->regs[2] & 0x03u) {
        case 0u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
        case 1u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
        case 2u: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
        default: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
        }
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper28_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper28_t* m = (mapper28_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper28_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    m->regs[3] = 0x0Cu;  /* default: PRG mode 3 → fixed last bank */
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper28_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper28_t* m = (mapper28_t*)nes->nes_mapper.mapper_register;
    if (address == 0x5100u)
        m->reg_sel = data & 0x03u;
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper28_t* m = (mapper28_t*)nes->nes_mapper.mapper_register;
    (void)address;
    m->regs[m->reg_sel] = data;
    mapper28_update_banks(nes);
}

int nes_mapper28_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

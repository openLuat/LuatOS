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

/* https://www.nesdev.org/wiki/INES_Mapper_151
 * Mapper 151 — VRC1 (Vs. System Japan variant).
 * PRG: 3 × 8KB + 1 fixed (last). CHR: 2 × 4KB.
 * Addressed like simplified VRC4 but with fewer register bits.
 * $8000: PRG[0] bits[3:0], bit[0]=mirror (H/V)
 * $A000: PRG[1] bits[3:0]
 * $C000: PRG[2] bits[3:0]
 * $E000: CHR bits[3:0] for 4KB slot 0
 * $F000: CHR bits[3:0] for 4KB slot 1
 */

typedef struct {
    uint8_t prg[3];
    uint8_t chr[2];
    uint8_t mirror;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper151_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper151_update_banks(nes_t* nes) {
    mapper151_t* m = (mapper151_t*)nes->nes_mapper.mapper_register;
    uint8_t last = (uint8_t)(m->prg_bank_count - 1u);
    nes_load_prgrom_8k(nes, 0, m->prg[0] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 2, m->prg[2] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 3, last);
    if (m->chr_bank_count > 0u) {
        uint8_t c4 = (uint8_t)(m->chr_bank_count / 4u);
        if (c4 == 0u) c4 = 1u;
        nes_load_chrrom_4k(nes, 0, (uint8_t)(m->chr[0] % c4));
        nes_load_chrrom_4k(nes, 1, (uint8_t)(m->chr[1] % c4));
    }
    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, m->mirror ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper151_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper151_t* m = (mapper151_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper151_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper151_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper151_t* m = (mapper151_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u:
        m->prg[0] = data & 0x0Fu;
        m->mirror = data & 0x01u;
        mapper151_update_banks(nes);
        break;
    case 0xA000u: m->prg[1] = data & 0x0Fu; mapper151_update_banks(nes); break;
    case 0xC000u: m->prg[2] = data & 0x0Fu; mapper151_update_banks(nes); break;
    case 0xE000u: m->chr[0] = data & 0x0Fu; mapper151_update_banks(nes); break;
    case 0xF000u: m->chr[1] = data & 0x0Fu; mapper151_update_banks(nes); break;
    default: break;
    }
}

int nes_mapper151_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

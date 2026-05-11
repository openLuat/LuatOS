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

/* https://www.nesdev.org/wiki/INES_Mapper_165
 * Mapper 165 — Fire Emblem pirate (MMC2-like with CHR-RAM).
 * Same bank logic as MMC2/mapper 9 but CHR uses RAM for banks 4-7.
 * Simplified: use standard MMC2 latch logic; CHR-RAM if no CHR-ROM.
 */

typedef struct {
    uint8_t prg_bank;
    uint8_t latch[2];
    uint8_t chr_banks[2][2];
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper165_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper165_update_banks(nes_t* nes) {
    mapper165_t* m = (mapper165_t*)nes->nes_mapper.mapper_register;
    uint8_t last4 = (uint8_t)(m->prg_bank_count - 1u);
    nes_load_prgrom_8k(nes, 0, m->prg_bank % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 1, (uint8_t)((m->prg_bank_count - 3u) % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 2, (uint8_t)((m->prg_bank_count - 2u) % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 3, last4);
    if (m->chr_bank_count > 0u) {
        nes_load_chrrom_4k(nes, 0, (uint8_t)(m->chr_banks[0][m->latch[0]] % (m->chr_bank_count / 4u > 0u ? m->chr_bank_count / 4u : 1u)));
        nes_load_chrrom_4k(nes, 1, (uint8_t)(m->chr_banks[1][m->latch[1]] % (m->chr_bank_count / 4u > 0u ? m->chr_bank_count / 4u : 1u)));
    } else {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper165_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper165_t* m = (mapper165_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper165_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->prg_bank_count == 0u) m->prg_bank_count = 4u;
    mapper165_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper165_t* m = (mapper165_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0xA000u: m->prg_bank = data & 0x0Fu; mapper165_update_banks(nes); break;
    case 0xB000u: m->chr_banks[0][0] = data & 0xFEu; mapper165_update_banks(nes); break;
    case 0xC000u: m->chr_banks[0][1] = data & 0xFEu; mapper165_update_banks(nes); break;
    case 0xD000u: m->chr_banks[1][0] = data | 0x01u;  mapper165_update_banks(nes); break;
    case 0xE000u: m->chr_banks[1][1] = data | 0x01u;  mapper165_update_banks(nes); break;
    default: break;
    }
}

static void nes_mapper_ppu(nes_t* nes, uint16_t address) {
    mapper165_t* m = (mapper165_t*)nes->nes_mapper.mapper_register;
    if (address == 0x0FD8u) { m->latch[0] = 0u; mapper165_update_banks(nes); }
    else if (address == 0x0FE8u) { m->latch[0] = 1u; mapper165_update_banks(nes); }
    else if (address >= 0x1FD8u && address <= 0x1FDFu) { m->latch[1] = 0u; mapper165_update_banks(nes); }
    else if (address >= 0x1FE8u && address <= 0x1FEFu) { m->latch[1] = 1u; mapper165_update_banks(nes); }
}

int nes_mapper165_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_ppu    = nes_mapper_ppu;
    nes->nes_mapper.mapper_ppu_tile_min = 0xFD;
    nes->nes_mapper.mapper_ppu_tile_max = 0xFE;
    return NES_OK;
}

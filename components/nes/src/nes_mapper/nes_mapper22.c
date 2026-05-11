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

/* https://www.nesdev.org/wiki/INES_Mapper_022
 * Mapper 22 - VRC2a (Konami).
 * PRG: 8KB switchable at $8000 and $A000; $C000-$FFFF fixed (last 16KB).
 * CHR: 8x1KB banks ($0000-$1C00), switched via nibble-pair registers.
 * CHR address decode: A1 = nibble select, A0 = bank-within-block (same as VRC4c/d).
 * CHR data nibble: bits[4:1] of written byte (shifted right by 1), unlike VRC4.
 * No IRQ.
 */

typedef struct {
    uint8_t prg[2];   /* 5-bit PRG bank indices for $8000 and $A000 */
    uint8_t chr[8];   /* 8-bit assembled CHR 1KB bank indices [0-7] */
    uint8_t mirror;   /* 0=vertical, 1=horizontal */
} mapper22_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static inline uint16_t mapper22_prg_bank(nes_t* nes, uint8_t bank) {
    const uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    return (prg_banks == 0u) ? 0u : (uint16_t)(bank % prg_banks);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper22_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper22_register_t* r = (mapper22_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper22_register_t));

    const uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    r->prg[0] = 0;
    r->prg[1] = 1;
    nes_load_prgrom_8k(nes, 0, mapper22_prg_bank(nes, r->prg[0]));
    nes_load_prgrom_8k(nes, 1, mapper22_prg_bank(nes, r->prg[1]));
    nes_load_prgrom_8k(nes, 2, (uint16_t)(prg_banks - 2u));
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_banks - 1u));

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        for (int i = 0; i < 8; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)i, 0);
        }
    }
}

/*
 * CHR bank write for $B000-$E003 (VRC2a address/data encoding).
 * A1 selects nibble (0=low4, 1=high4); A0 selects bank within block.
 * Data nibble is in bits[4:1] (right-shifted by 1) per VRC2a specification.
 */
static void mapper22_write_chr(mapper22_register_t* r, nes_t* nes,
                                uint16_t addr, uint8_t data) {
    if (nes->nes_rom.chr_rom_size == 0) return;
    uint8_t nibble = (uint8_t)((addr >> 1) & 1u); /* A1: hi/lo nibble select */
    uint8_t sub    = (uint8_t)(addr & 1u);         /* A0: bank within block */
    uint8_t block  = (uint8_t)((addr >> 12) - 0xBu);
    uint8_t idx    = (uint8_t)(block * 2u + sub);
    uint8_t ndata  = (uint8_t)((data >> 1) & 0x0Fu); /* VRC2a: nibble in bits[4:1] */
    if (nibble == 0) {
        r->chr[idx] = (r->chr[idx] & 0xF0u) | ndata;
    } else {
        r->chr[idx] = (r->chr[idx] & 0x0Fu) | (uint8_t)(ndata << 4);
    }
    const uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    nes_load_chrrom_1k(nes, idx, (uint8_t)(r->chr[idx] % chr_banks));
}

/*
 * $8000        : 8KB PRG bank at $8000, bits[4:0]
 * $9000        : mirroring, bit0: 0=vertical, 1=horizontal
 * $A000        : 8KB PRG bank at $A000, bits[4:0]
 * $B000-$E003  : 8x1KB CHR banks via nibble pairs
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper22_register_t* r = (mapper22_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u:
        r->prg[0] = data & 0x1Fu;
        nes_load_prgrom_8k(nes, 0, mapper22_prg_bank(nes, r->prg[0]));
        break;
    case 0x9000u:
        r->mirror = data & 0x01u;
        if (nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes, r->mirror ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        }
        break;
    case 0xA000u:
        r->prg[1] = data & 0x1Fu;
        nes_load_prgrom_8k(nes, 1, mapper22_prg_bank(nes, r->prg[1]));
        break;
    case 0xB000u:
    case 0xC000u:
    case 0xD000u:
    case 0xE000u:
        mapper22_write_chr(r, nes, address, data);
        break;
    default:
        break;
    }
}

int nes_mapper22_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

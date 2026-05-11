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

/* https://www.nesdev.org/wiki/INES_Mapper_057
 * Globe / GK-47 — PRG+CHR bank with game select bit.
 * Write $8000-$FFFF:
 *   bit[6]  = outer game select (affects which 128KB PRG block)
 *   bit[3]  = PRG mode: 0=16KB (first+last of block), 1=32KB (from block)
 *   bits[2:0] = PRG bank within mode
 *   CHR 8KB bank = bit[6]<<3 | bits[2:0]
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, 7);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    uint8_t outer    = (uint8_t)((data >> 6) & 0x01u);
    uint8_t inner    = (uint8_t)(data & 0x07u);
    uint8_t chr_bank = (uint8_t)((outer << 3u) | inner);
    if (data & 0x08u) {
        /* 32KB mode */
        nes_load_prgrom_32k(nes, 0, (uint16_t)((outer << 2u) | (inner >> 1u)));
    } else {
        /* 16KB mode: inner bank in first half, last bank of block in second */
        uint8_t b = (uint8_t)((outer << 3u) | inner);
        nes_load_prgrom_16k(nes, 0, b);
        nes_load_prgrom_16k(nes, 1, (uint8_t)((outer << 3u) | 7u));
    }
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, chr_bank);
    }
}

int nes_mapper57_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

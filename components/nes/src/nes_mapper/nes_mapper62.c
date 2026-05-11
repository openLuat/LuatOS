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

/* https://www.nesdev.org/wiki/INES_Mapper_062
 * Super 700-in-1 — outer+inner PRG+CHR bank via address bits and data bits.
 * Write $8000-$FFFF:
 *   address[13:6] = outer PRG bank (8 bits)
 *   address[5:0]  = outer CHR bank (6 bits)
 *   data[7]       = 0: 32KB PRG mode, 1: 16KB PRG mode
 *   data[6]       = inner CHR bank bit 0
 *   data[0]       = inner PRG bank bit 0 (for 16KB mode)
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    uint16_t outer_prg = (uint16_t)((address >> 6) & 0xFFu);
    uint8_t  outer_chr = (uint8_t)(address & 0x3Fu);
    uint8_t  chr = (uint8_t)((outer_chr << 1u) | ((data >> 6) & 1u));
    if (data & 0x80u) {
        /* 16KB mode */
        uint16_t prg = (uint16_t)((outer_prg << 1u) | (data & 1u));
        nes_load_prgrom_16k(nes, 0, prg);
        nes_load_prgrom_16k(nes, 1, prg);
    } else {
        nes_load_prgrom_32k(nes, 0, outer_prg);
    }
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, chr);
    }
}

int nes_mapper62_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

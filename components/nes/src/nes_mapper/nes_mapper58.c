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

/* https://www.nesdev.org/wiki/INES_Mapper_058
 * Study & Game 32-in-1 — PRG+CHR bank via $6000-$7FFF writes.
 * Write $6000-$7FFF:
 *   bit[6]  = PRG mode: 0=32KB, 1=16KB
 *   bits[2:0] = PRG bank (32KB) or 16KB bank for $8000
 *   bits[5:3] = CHR 8KB bank
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    uint8_t chr = (uint8_t)((data >> 3) & 0x07u);
    if (data & 0x40u) {
        /* 16KB mode */
        uint8_t b = (uint8_t)(data & 0x07u);
        nes_load_prgrom_16k(nes, 0, b);
        nes_load_prgrom_16k(nes, 1, (uint8_t)(b | 0x07u));
    } else {
        nes_load_prgrom_32k(nes, 0, (uint16_t)(data & 0x07u));
    }
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, chr);
    }
}

int nes_mapper58_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_sram = nes_mapper_sram;
    return NES_OK;
}

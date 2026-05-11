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

/* https://www.nesdev.org/wiki/INES_Mapper_204
 * 64-in-1 / Super Hi 8-in-1 multicart.
 * Write $8000-$FFFF: address[2:1] = bank; when address[1]=1, uses 32KB mode.
 * PRG: 16KB mirrored (both halves same) or two different banks.
 * CHR: 8KB bank.
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)data;
    uint8_t bank = (uint8_t)((address >> 1) & 0x03u);
    /* If bit 1 of the bank is set, both halves use same bank */
    if (bank & 0x02u) {
        nes_load_prgrom_16k(nes, 0, bank);
        nes_load_prgrom_16k(nes, 1, bank);
    } else {
        nes_load_prgrom_16k(nes, 0, (uint8_t)(bank & ~1u));
        nes_load_prgrom_16k(nes, 1, (uint8_t)(bank | 1u));
    }
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, bank);
    }
}

int nes_mapper204_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

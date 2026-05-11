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

/* https://www.nesdev.org/wiki/INES_Mapper_008 */

static void nes_mapper_init(nes_t* nes) {
    // CPU $8000-$BFFF: 16 KB switchable PRG ROM bank
    nes_load_prgrom_16k(nes, 0, 0);
    // CPU $C000-$FFFF: 16 KB PRG ROM bank, fixed to bank 1
    nes_load_prgrom_16k(nes, 1, 1);
    // CHR capacity: 8 KiB switchable ROM
    nes_load_chrrom_8k(nes, 0, 0);
}

/*
    Bank select ($8000-$FFFF)
    7  bit  0
    ---- ----
    PPPP PCCC
    |||||  |||
    +++++--+++ Select 16 KB PRG ROM bank for CPU $8000-$BFFF
           +++ Select  8 KB CHR ROM bank for PPU $0000-$1FFF
*/

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    nes_load_prgrom_16k(nes, 0, (data >> 3) & 0x1F);
    nes_load_chrrom_8k(nes, 0, data & 0x07);
}

int nes_mapper8_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

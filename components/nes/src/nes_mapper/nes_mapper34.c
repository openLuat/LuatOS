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

/* https://www.nesdev.org/wiki/INES_Mapper_034 */
/* Implements both BxROM (mapper_write) and NINA-001 (mapper_sram) variants */

static void nes_mapper_init(nes_t* nes) {
    // CPU $8000-$FFFF: 32 KB switchable PRG ROM bank
    nes_load_prgrom_32k(nes, 0, 0);
    // CHR capacity: 8 KiB ROM or RAM
    nes_load_chrrom_8k(nes, 0, 0);
}

/*
    BxROM variant: write to $8000-$FFFF
    7  bit  0
    ---- ----
    xxxx xxPP
              ||
              ++- Select 32 KB PRG ROM bank for CPU $8000-$FFFF
*/
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    nes_load_prgrom_32k(nes, 0, data & 0x03);
}

/*
    NINA-001 variant: write to $6000-$7FFF
    $7FFD: bit 0 = 32 KB PRG ROM bank select
    $7FFE: bits [3:0] = 4 KB CHR ROM bank for PPU $0000-$0FFF
    $7FFF: bits [3:0] = 4 KB CHR ROM bank for PPU $1000-$1FFF
*/
static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    switch (address) {
        case 0x7FFD:
            nes_load_prgrom_32k(nes, 0, data & 0x01);
            break;
        case 0x7FFE:
            nes_load_chrrom_4k(nes, 0, data & 0x0F);
            break;
        case 0x7FFF:
            nes_load_chrrom_4k(nes, 1, data & 0x0F);
            break;
        default:
            break;
    }
}

int nes_mapper34_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_sram  = nes_mapper_sram;
    return NES_OK;
}

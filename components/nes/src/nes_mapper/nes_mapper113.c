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
#include "nes_mapper.h"

/* https://www.nesdev.org/wiki/INES_Mapper_113 */

static void nes_mapper_init(nes_t* nes) {
    // CPU $8000-$FFFF: 32 KB switchable PRG ROM bank.
    nes_load_prgrom_32k(nes, 0, 0);
    // CHR $0000-$1FFF: 8 KB switchable CHR ROM bank.
    nes_load_chrrom_8k(nes, 0, 0);
}

/*
    Register at $4100 (write to $4020-$5FFF):
    7  bit  0
    ---- ----
    CPPP PCCC
    |||| ||||
    |+++-++++- CHR bank select:
    |              bit 7 (C) -> CHR bit 6
    |              bits [5:3] -> CHR bits [5:3]
    |              bits [2:0] -> CHR bits [2:0]
    +--------- PRG 32KB bank select (bit 6)
*/
static void nes_mapper_apu_write(nes_t* nes, uint16_t address, uint8_t data) {
    if (address >= 0x4020 && address <= 0x5FFF) {
        uint8_t prg = (data >> 6) & 0x01;
        // CHR = (bit7 << 6) | bits[5:3] | bits[2:0]
        uint8_t chr = ((data & 0x80) >> 1) | (data & 0x3F);
        nes_load_prgrom_32k(nes, 0, prg);
        nes_load_chrrom_8k(nes, 0, chr);
    }
}

int nes_mapper113_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_apu  = nes_mapper_apu_write;
    return NES_OK;
}

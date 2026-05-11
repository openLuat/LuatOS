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

/* https://www.nesdev.org/wiki/INES_Mapper_003 */
static void nes_mapper_init(nes_t* nes){
    uint8_t last = (uint8_t)(nes->nes_rom.prg_rom_size - 1u);
    uint8_t second_last = (nes->nes_rom.prg_rom_size >= 2u) ? (uint8_t)(nes->nes_rom.prg_rom_size - 2u) : 0u;
    // CPU $8000-$BFFF: second-to-last 16 KB (= first 16 KB for <=32KB ROMs).
    nes_load_prgrom_16k(nes, 0, second_last);
    // CPU $C000-$FFFF: Last 16 KB of ROM (or mirror of $8000-$BFFF for 16 KB ROMs).
    nes_load_prgrom_16k(nes, 1, last);
    // CHR capacity: 8 KiB ROM.
    nes_load_chrrom_8k(nes, 0, 0);
}

/*
    PPU $0000-$1FFF: 8 KB switchable CHR ROM bank
    7  bit  0
    ---- ----
    cccc ccCC
    |||| ||||
    ++++-++++- Select 8 KB CHR ROM bank for PPU $0000-$1FFF
    CNROM only implements the lowest 2 bits, capping it at 32 KiB CHR. Other boards may implement 4 or more bits for larger CHR.
*/
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    if (nes->nes_rom.chr_rom_size == 0) return;
    // Bus conflicts: effective data = written_data & ROM[address]
    uint8_t slot = (uint8_t)((address - 0x8000u) >> 13u);
    uint8_t rom_byte = nes->nes_cpu.prg_banks[slot][address & 0x1FFFu];
    uint8_t effective = data & rom_byte;
    nes_load_chrrom_8k(nes, 0, effective % nes->nes_rom.chr_rom_size);
}

int nes_mapper3_init(nes_t* nes){
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}


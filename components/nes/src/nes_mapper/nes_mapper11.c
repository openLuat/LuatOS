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

/* https://www.nesdev.org/wiki/Color_Dreams */

static void nes_mapper_init(nes_t* nes) {
    // CPU $8000-$FFFF: last 32 KB PRG ROM bank (supports multi-bank ROMs like 64KB)
    uint8_t prg_bank_count32 = (uint8_t)(nes->nes_rom.prg_rom_size / 2u);
    uint8_t last = prg_bank_count32 > 0u ? (uint8_t)(prg_bank_count32 - 1u) : 0u;
    nes_load_prgrom_32k(nes, 0, last);
    // CHR capacity: 8 KiB ROM (skip if CHR-RAM)
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

/*
    7  bit  0
    ---- ----
    CCCC PPPP
    |||| ||||
    |||| ++++- Select 32 KB PRG ROM bank for CPU $8000-$FFFF
    ++++------ Select 8 KB CHR ROM bank for PPU $0000-$1FFF
*/
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    // PRG: bits 0-3 select 32KB bank; CHR: bits 4-7 select 8KB bank.
    // Wrap bank numbers to valid range (Color Dreams ROMs rely on this).
    const uint16_t num_prg_banks = nes->nes_rom.prg_rom_size >> 1; // 16KB→32KB units
    const uint16_t num_chr_banks = nes->nes_rom.chr_rom_size;       // already in 8KB units
    uint8_t prg = (data & 0x0F) % (num_prg_banks ? num_prg_banks : 1);
    uint8_t chr = (nes->nes_rom.chr_rom_size > 0) ? (uint8_t)(((data >> 4) & 0x0F) % num_chr_banks) : 0;
    NES_LOG_DEBUG("Mapper11 write addr=$%04X data=$%02X -> PRG=%d CHR=%d\n", address, data, prg, chr);
    nes_load_prgrom_32k(nes, 0, prg);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, chr);
    }
}

int nes_mapper11_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

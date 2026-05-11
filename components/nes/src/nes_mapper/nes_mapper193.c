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

/* https://www.nesdev.org/wiki/INES_Mapper_193
 * NTDEC TC-112 (FCEUX boards/193.cpp is authoritative)
 *
 * CPU $8000-$9FFF: 8 KiB switchable PRG bank (selected by $6003 write)
 * CPU $A000-$FFFF: fixed last 24 KiB of PRG ROM
 *
 * $6000: selects 4KB CHR bank at PPU $0000-$0FFF  (bank# = data >> 2)
 * $6001: selects 2KB CHR bank at PPU $1000-$17FF  (bank# = data >> 1)
 * $6002: selects 2KB CHR bank at PPU $1800-$1FFF  (bank# = data >> 1)
 * $6003: selects 8KB PRG bank at CPU $8000-$9FFF
 *
 * Writes to $8000-$FFFF do nothing (ROM is read-only on this board).
 */

static void nes_mapper_init(nes_t* nes) {
    uint16_t prg8k = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    nes_load_prgrom_8k(nes, 0, 0);           // $8000-$9FFF: switchable, init bank 0
    nes_load_prgrom_8k(nes, 1, prg8k - 3u); // $A000-$BFFF: fixed
    nes_load_prgrom_8k(nes, 2, prg8k - 2u); // $C000-$DFFF: fixed
    nes_load_prgrom_8k(nes, 3, prg8k - 1u); // $E000-$FFFF: fixed (reset vector here)
    if (nes->nes_rom.chr_rom_size > 0) {
        // $6000=0: 4KB bank 0 → slots 0-3 = 1KB banks 0,1,2,3
        nes_load_chrrom_1k(nes, 0, 0);
        nes_load_chrrom_1k(nes, 1, 1);
        nes_load_chrrom_1k(nes, 2, 2);
        nes_load_chrrom_1k(nes, 3, 3);
        // $6001=0: 2KB bank 0 → slots 4-5 = 1KB banks 0,1
        nes_load_chrrom_1k(nes, 4, 0);
        nes_load_chrrom_1k(nes, 5, 1);
        // $6002=0: 2KB bank 0 → slots 6-7 = 1KB banks 0,1
        nes_load_chrrom_1k(nes, 6, 0);
        nes_load_chrrom_1k(nes, 7, 1);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    /* $8000-$FFFF writes do nothing on this board (ROM read-only) */
    (void)nes; (void)address; (void)data;
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    uint16_t base;
    switch (address & 0x03u) {
        case 0: /* $6000: 4KB CHR at PPU $0000-$0FFF, bank# = data >> 2 */
            if (nes->nes_rom.chr_rom_size == 0) return;
            base = (uint16_t)((data >> 2u) * 4u);
            nes_load_chrrom_1k(nes, 0, base);
            nes_load_chrrom_1k(nes, 1, base + 1u);
            nes_load_chrrom_1k(nes, 2, base + 2u);
            nes_load_chrrom_1k(nes, 3, base + 3u);
            break;
        case 1: /* $6001: 2KB CHR at PPU $1000-$17FF, bank# = data >> 1 */
            if (nes->nes_rom.chr_rom_size == 0) return;
            base = (uint16_t)((data >> 1u) * 2u);
            nes_load_chrrom_1k(nes, 4, base);
            nes_load_chrrom_1k(nes, 5, base + 1u);
            break;
        case 2: /* $6002: 2KB CHR at PPU $1800-$1FFF, bank# = data >> 1 */
            if (nes->nes_rom.chr_rom_size == 0) return;
            base = (uint16_t)((data >> 1u) * 2u);
            nes_load_chrrom_1k(nes, 6, base);
            nes_load_chrrom_1k(nes, 7, base + 1u);
            break;
        case 3: /* $6003: 8KB PRG bank at CPU $8000-$9FFF */
            nes_load_prgrom_8k(nes, 0, data);
            break;
    }
}

int nes_mapper193_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_sram  = nes_mapper_sram;
    return NES_OK;
}


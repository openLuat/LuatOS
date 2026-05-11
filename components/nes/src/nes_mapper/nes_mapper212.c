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

/* https://www.nesdev.org/wiki/INES_Mapper_212
 * BMC 300-in-1 — PRG+CHR bank encoded in address bits.
 * Write $8000-$FFFF:
 *   address[14]  = mirroring (0=V, 1=H)
 *   address[13]  = PRG mode (0=32KB, 1=16KB)
 *   address[12:8]= PRG bank (5 bits, 16KB granularity)
 *   address[7:5] = ignored
 *   address[4:0] = CHR 8KB bank
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)data;
    uint16_t prg = (uint16_t)((address >> 8) & 0x1Fu);
    uint8_t  chr = (uint8_t)(address & 0x1Fu);
    if (nes->nes_rom.four_screen == 0) {
        nes_ppu_screen_mirrors(nes, (address & 0x4000u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
    }
    if (address & 0x2000u) {
        nes_load_prgrom_16k(nes, 0, prg);
        nes_load_prgrom_16k(nes, 1, prg);
    } else {
        nes_load_prgrom_32k(nes, 0, (uint16_t)(prg >> 1));
    }
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, chr);
    }
}

int nes_mapper212_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

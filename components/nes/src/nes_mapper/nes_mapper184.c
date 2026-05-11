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

/* https://www.nesdev.org/wiki/INES_Mapper_184
 * Sunsoft-1 — PRG-ROM 32KB fixed; CHR 4KB banks switchable via $6000-$7FFF.
 * Write $6000-$7FFF:
 *   bits[2:0] = 4KB CHR bank for PPU $0000-$0FFF
 *   bits[6:4] = 4KB CHR bank for PPU $1000-$1FFF (add 4 for slot offset)
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_4k(nes, 0, 0);
        nes_load_chrrom_4k(nes, 1, 0);
    }
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_4k(nes, 0, (uint8_t)(data & 0x07u));
        nes_load_chrrom_4k(nes, 1, (uint8_t)((data >> 4) & 0x07u));
    }
}

int nes_mapper184_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_sram = nes_mapper_sram;
    return NES_OK;
}

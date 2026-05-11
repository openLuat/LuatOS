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

/* https://www.nesdev.org/wiki/INES_Mapper_207
 * Taito X1-005 minicart: switchable 16KB PRG at $8000 and 4KB CHR mirrored
 * into both pattern-table halves. Register is decoded at $FFF8-$FFFF.
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, nes->nes_rom.prg_rom_size - 1u);
    nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    if (address < 0xFFF8u) {
        return;
    }

    nes_load_prgrom_16k(nes, 0, data & 0x0Fu);
    if (nes->nes_rom.chr_rom_size > 0) {
        const uint8_t chr = (uint8_t)((data >> 4u) & 0x0Fu);
        nes_load_chrrom_4k(nes, 0, chr);
        nes_load_chrrom_4k(nes, 1, chr);
    }
}

int nes_mapper207_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}


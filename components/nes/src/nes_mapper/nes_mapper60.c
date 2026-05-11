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

/* https://www.nesdev.org/wiki/INES_Mapper_060
 * Reset-based 4-game multicart — on each reset, the next game is selected.
 * Game is encoded in address bits on writes to $8000-$FFFF.
 * Bit[3] of address = 32KB mode vs 16KB; bits[2:0] = game bank.
 * For simplicity: boot to game 0 (bank 0, 16KB+fixed last).
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)data;
    uint8_t bank = (uint8_t)(address & 0x07u);
    if (address & 0x08u) {
        /* 32KB mode */
        nes_load_prgrom_32k(nes, 0, (uint16_t)bank);
    } else {
        /* 16KB mode: fixed last */
        nes_load_prgrom_16k(nes, 0, (uint16_t)bank);
        nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    }
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, bank);
    }
}

int nes_mapper60_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/Camerica_boards */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, nes->nes_rom.prg_rom_size - 1);
    nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    uint16_t prg_banks = nes->nes_rom.prg_rom_size;
    if (address >= 0x9000 && address <= 0x9FFF) {
        /* $9000-$9FFF: bit 4 = one-screen nametable select */
        nes_ppu_screen_mirrors(nes, (data & 0x10) ? NES_MIRROR_ONE_SCREEN1 : NES_MIRROR_ONE_SCREEN0);
    } else if (address >= 0xC000) {
        /* $C000-$FFFF: bits 3-0 = PRG 16KB bank at $8000 */
        if (prg_banks > 0) nes_load_prgrom_16k(nes, 0, (data & 0x0F) % prg_banks);
    }
}

int nes_mapper71_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return 0;
}

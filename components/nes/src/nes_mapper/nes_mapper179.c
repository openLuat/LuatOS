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

/* https://www.nesdev.org/wiki/INES_Mapper_179
 * Simple Chinese pirate — 8KB PRG bank switcher.
 * Write $5000-$5FFF: bits[2:0] = 8KB PRG bank for $8000-$9FFF.
 * Remaining 24KB PRG fixed.
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 1);
    nes_load_prgrom_8k(nes, 2, 2);
    nes_load_prgrom_8k(nes, 3, 3);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    if ((address & 0xF000u) != 0x5000u) return;
    nes_load_prgrom_8k(nes, 0, (uint16_t)(data & 0x07u));
}

int nes_mapper179_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_apu  = nes_mapper_apu;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_038
 * Crime Busters / 16-in-1 — PRG 32KB + CHR 8KB bank select via $7000-$7FFF.
 * Write $7000-$7FFF:
 *   bits[1:0] = CHR 8KB bank
 *   bits[3:2] = PRG 32KB bank
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    if ((address & 0xF000u) != 0x7000u) return;
    nes_load_prgrom_32k(nes, 0, (uint16_t)((data >> 2) & 0x03u));
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, (uint8_t)(data & 0x03u));
    }
}

int nes_mapper38_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_sram = nes_mapper_sram;
    return NES_OK;
}

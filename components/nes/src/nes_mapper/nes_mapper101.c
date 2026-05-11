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

/* https://www.nesdev.org/wiki/INES_Mapper_101
 * Jaleco JF-10 — PRG-ROM 32KB fixed; 8KB CHR-ROM switchable via $6000-$7FFF.
 * Write $6000-$7FFF: bits[3:0] = CHR 8KB bank.
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, (uint8_t)(data & 0x0Fu));
    }
}

int nes_mapper101_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_sram = nes_mapper_sram;
    return NES_OK;
}

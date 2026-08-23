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

/* https://www.nesdev.org/wiki/INES_Mapper_093
 * Sunsoft-2 on Sunsoft-3R / Fantasy Zone compatible wiring.
 * $8000-$BFFF: 16KB switchable PRG, $C000-$FFFF: last 16KB fixed.
 * CHR is usually 8KB RAM; bit0 is a CHR-RAM enable line, but no known
 * commercial software relies on disabling it.
 *
 * Write $8000-$FFFF has bus conflicts:
 *   bits[6:4] = 16KB PRG bank at $8000.
 *
 * Some Fantasy Zone dumps/implementations model the original Sunsoft-1
 * compatible latch at $6000, where the written value directly selects PRG.
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    nes_load_chrrom_8k(nes, 0, 0);
    nes_ppu_screen_mirrors(nes, NES_MIRROR_AUTO);
}

static uint8_t mapper93_bus_conflict(nes_t* nes, uint16_t address, uint8_t data) {
    uint8_t* bank = nes->nes_cpu.prg_banks[(address >> 13u) - 4u];
    if (bank) {
        data &= bank[address & 0x1FFFu];
    }
    return data;
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    data = mapper93_bus_conflict(nes, address, data);
    nes_load_prgrom_16k(nes, 0, (uint16_t)((data >> 4) & 0x07u));
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    if (address == 0x6000u) {
        nes_load_prgrom_16k(nes, 0, data);
    }
}

int nes_mapper93_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_sram  = nes_mapper_sram;
    return NES_OK;
}

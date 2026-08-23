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

/* FCEUX boards/72.cpp
 * Jaleco JF-19 — fixed first 16KB PRG + switchable upper 16KB PRG,
 * with 8KB CHR switchable.
 * Write $8000-$FFFF:
 *   bit[7] = 1 -> PRG 16KB bank = data[3:0] for $C000-$FFFF
 *   bit[6] = 1 -> CHR 8KB bank = data[3:0]
 * Fixed first 16KB at $8000-$BFFF.
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    if (data & 0x80u) {
        nes_load_prgrom_16k(nes, 1, (uint16_t)(data & 0x0Fu));
    }
    if ((data & 0x40u) && nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, (uint16_t)(data & 0x0Fu));
    }
}

int nes_mapper92_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_097
 * Irem TAM-S1 — fixed first 16KB at $8000-$BFFF; switchable 16KB at $C000-$FFFF.
 * Write $8000-$FFFF:
 *   bits[5:0] = 16KB PRG bank for $C000-$FFFF
 *   bits[7:6] = mirroring: 00=1scr-NT1, 01=1scr-NT0, 10=H, 11=V
 */

static const nes_mirror_type_t mapper97_mirror[4] = {
    NES_MIRROR_ONE_SCREEN1,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_VERTICAL,
};

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    nes_load_prgrom_16k(nes, 1, (uint16_t)(data & 0x3Fu));
    if (nes->nes_rom.four_screen == 0) {
        nes_ppu_screen_mirrors(nes, mapper97_mirror[(data >> 6) & 0x03u]);
    }
}

int nes_mapper97_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

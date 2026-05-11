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

/* https://www.nesdev.org/wiki/INES_Mapper_089
 * Sunsoft-2 — 16KB PRG switchable + CHR 8KB switchable + single-screen mirror.
 * Write $8000-$FFFF:
 *   bit[7]   = mirroring (0=NT0 single-screen, 1=NT1 single-screen)
 *   bits[6:4]= 16KB PRG bank for $8000-$BFFF
 *   bit[3]   = CHR bank bit 3
 *   bits[2:0]= CHR bank bits 2:0
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    nes_load_prgrom_16k(nes, 0, (uint16_t)((data >> 4) & 0x07u));
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, (uint8_t)(data & 0x0Fu));
    }
    if (nes->nes_rom.four_screen == 0) {
        nes_ppu_screen_mirrors(nes, (data & 0x80u) ? NES_MIRROR_ONE_SCREEN1 : NES_MIRROR_ONE_SCREEN0);
    }
}

int nes_mapper89_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

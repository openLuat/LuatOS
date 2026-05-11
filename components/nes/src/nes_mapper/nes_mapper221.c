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

/* https://www.nesdev.org/wiki/INES_Mapper_221
 * N625092 / Street Heroes multicart — bank select via address bits.
 * Write $8000-$FFFF:
 *   address[8:7] = outer PRG bank (2 bits)
 *   address[6]   = PRG mode (0=16KB first+last, 1=32KB)
 *   address[5:1] = PRG inner bank (5 bits)
 *   address[0]   = mirroring (0=V, 1=H)
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
    uint16_t outer = (uint16_t)((address >> 7) & 0x03u);
    uint16_t inner = (uint16_t)((address >> 1) & 0x1Fu);
    uint16_t prg   = (uint16_t)((outer << 5u) | inner);
    if (nes->nes_rom.four_screen == 0) {
        nes_ppu_screen_mirrors(nes, (address & 0x01u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
    }
    if (address & 0x40u) {
        /* 32KB mode */
        nes_load_prgrom_32k(nes, 0, (uint16_t)(prg >> 1));
    } else {
        /* 16KB mode: switchable + fixed last within outer block */
        nes_load_prgrom_16k(nes, 0, prg);
        nes_load_prgrom_16k(nes, 1, (uint16_t)((outer << 5u) | 0x1Fu));
    }
}

int nes_mapper221_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

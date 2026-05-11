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

/* https://www.nesdev.org/wiki/INES_Mapper_228
 * Action 52 — MLT-ACTION52 board
 * PRG/CHR bank selection entirely encoded in the write address.
 * Reference: FCEUX src/boards/228.cpp
 *
 * Write $8000-$FFFF (address = areg, data = vreg):
 *   PRG:
 *     page   = areg[12:7] (6 bits), pages 48-63 remapped to 32-47
 *     A6, A5 control 32KB/16KB mode and bank parity
 *     prgl   = (page << 1) + (A6 & A5)
 *     prgh   = prgl + (A5 ^ 1)        — if A5=1: 16KB mirrored, else 32KB
 *   CHR (6-bit, 64 x 8KB):
 *     chr    = (vreg[1:0]) | (areg[3:0] << 2)
 *   Mirroring:
 *     areg[13]=0 → vertical, areg[13]=1 → horizontal
 */

static void nes_mapper_init(nes_t* nes) {
    /* Reset state: areg=$8000 → page=0, prgl=0, prgh=1 */
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, 1);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
    nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    uint16_t areg = address;
    uint16_t prg_count = nes->nes_rom.prg_rom_size;

    /* PRG: page from A[12:7], remap pages 48-63 → 32-47 for 96-bank ROM */
    uint16_t page = (areg >> 7u) & 0x3Fu;
    if ((page & 0x30u) == 0x30u) {
        page -= 0x10u;
    }
    uint8_t a6 = (uint8_t)((areg >> 6u) & 1u);
    uint8_t a5 = (uint8_t)((areg >> 5u) & 1u);
    uint16_t prgl = (uint16_t)((page << 1u) + (uint16_t)(a6 & a5));
    uint16_t prgh = (uint16_t)(prgl + (uint16_t)(a5 ^ 1u));

    nes_load_prgrom_16k(nes, 0, prgl % prg_count);
    nes_load_prgrom_16k(nes, 1, prgh % prg_count);

    /* CHR: 6-bit bank = D[1:0] | (A[3:0] << 2), addresses 64 x 8KB banks */
    if (nes->nes_rom.chr_rom_size > 0) {
        uint16_t chr = (uint16_t)((data & 0x03u) | ((areg & 0x0Fu) << 2u));
        nes_load_chrrom_8k(nes, 0, chr % nes->nes_rom.chr_rom_size);
    }

    /* Mirroring: A[13]=0 → vertical, A[13]=1 → horizontal */
    if (nes->nes_rom.four_screen == 0) {
        uint8_t mirror_h = (uint8_t)((areg >> 13u) & 1u);
        nes_ppu_screen_mirrors(nes, mirror_h ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
    }
}

int nes_mapper228_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

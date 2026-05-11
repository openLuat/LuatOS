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
#include "nes_mapper.h"
#include "nes_log.h"

/*
 * Mapper 15 — 100-in-1 Contra Function 16 / Waixing/Subor Chinese originals
 * https://www.nesdev.org/wiki/INES_Mapper_015
 * Reference: FCEUX src/boards/15.cpp
 *
 * Register at $8000-$FFFF (write-only):
 *   Bit 7:   S  — 8KB bank select within 16KB pair (mode 2 only)
 *   Bit 6:   M  — Mirroring: 0=vertical, 1=horizontal
 *   Bits 5-0: B — 6-bit 16KB bank number
 *
 * Banking mode = (address & 3) [A1:A0]:
 *   0: 32KB block → $8000-$BFFF = bank B, $C000-$FFFF = bank B+1
 *   1: $8000-$BFFF = bank B, $C000-$FFFF = bank (B|7) (last in 8-bank group)
 *   2: all four 8KB slots = 8KB bank (B*2 + S)
 *   3: $8000-$BFFF = bank B, $C000-$FFFF = bank B (mirror)
 */

static void mapper15_apply(nes_t* nes, uint16_t address, uint8_t data) {
    uint8_t  B = data & 0x3Fu;
    uint8_t  S = data >> 7;
    uint8_t  M = (data >> 6) & 1u;

    switch (address & 3u) {
        case 0: /* 32KB aligned block */
            nes_load_prgrom_16k(nes, 0, B);
            nes_load_prgrom_16k(nes, 1, (uint16_t)(B + 1u));
            break;
        case 1: /* lower=B, upper=last-in-group */
            nes_load_prgrom_16k(nes, 0, B);
            nes_load_prgrom_16k(nes, 1, B | 7u);
            break;
        case 2: /* all four 8KB slots = same 8KB bank */
        {
            uint16_t bank8 = (uint16_t)((uint16_t)B * 2u + S);
            nes_load_prgrom_8k(nes, 0, bank8);
            nes_load_prgrom_8k(nes, 1, bank8);
            nes_load_prgrom_8k(nes, 2, bank8);
            nes_load_prgrom_8k(nes, 3, bank8);
            break;
        }
        default: /* case 3: mirror lower = upper = B */
            nes_load_prgrom_16k(nes, 0, B);
            nes_load_prgrom_16k(nes, 1, B);
            break;
    }

    nes_ppu_screen_mirrors(nes, M ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
}

static void nes_mapper_init(nes_t* nes) {
    /* Power-on: latchea=0x8000, latched=0 → case 0, B=0 → first 32KB */
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, 1);
    nes_load_chrrom_8k(nes, 0, 0);

    /* WRAM at $6000-$7FFF (Chinese originals use it extensively) */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper15_apply(nes, address, data);
}

int nes_mapper15_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

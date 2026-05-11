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

/* https://www.nesdev.org/wiki/INES_Mapper_075
 * Mapper 75 - VRC1 (Konami).
 * PRG: 8KB switchable at $8000 and $A000; $C000-$FFFF fixed (last 16KB).
 * CHR: two 4KB banks at $0000 and $1000, each with a 5-bit index
 *      assembled from a 1-bit high nibble ($9000 bits 1/2) and
 *      4-bit low nibble ($B000/$C000 bits 3:0).
 * No IRQ.
 */

typedef struct {
    uint8_t prg[2];     /* 4-bit PRG bank indices for $8000 and $A000 */
    uint8_t chr_lo[2];  /* low 4 bits of CHR banks 0 ($0000) and 1 ($1000) */
    uint8_t chr_hi[2];  /* high bit (A4) of CHR banks 0 and 1 */
} mapper75_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper75_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper75_register_t* r = (mapper75_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper75_register_t));

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 1);
    nes_load_prgrom_8k(nes, 2, (uint16_t)(prg_banks - 2u));
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_banks - 1u));

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        nes_load_chrrom_4k(nes, 0, 0);
        nes_load_chrrom_4k(nes, 1, 0);
    }
}

/*
 * $8000 : PRG bank for $8000-$9FFF (bits[3:0])
 * $9000 : bit0=mirror (0=V,1=H), bit1=CHR0 high bit, bit2=CHR1 high bit
 * $A000 : PRG bank for $A000-$BFFF (bits[3:0])
 * $B000 : CHR bank 0 low nibble
 * $C000 : CHR bank 1 low nibble
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper75_register_t* r = (mapper75_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u:
        r->prg[0] = data & 0x0Fu;
        nes_load_prgrom_8k(nes, 0, r->prg[0]);
        break;
    case 0x9000u:
        if (nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes, (data & 1u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        }
        r->chr_hi[0] = (data >> 1) & 0x01u;
        r->chr_hi[1] = (data >> 2) & 0x01u;
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_4k(nes, 0, (uint8_t)((r->chr_hi[0] << 4) | r->chr_lo[0]));
            nes_load_chrrom_4k(nes, 1, (uint8_t)((r->chr_hi[1] << 4) | r->chr_lo[1]));
        }
        break;
    case 0xA000u:
        r->prg[1] = data & 0x0Fu;
        nes_load_prgrom_8k(nes, 1, r->prg[1]);
        break;
    case 0xB000u:
        r->chr_lo[0] = data & 0x0Fu;
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_4k(nes, 0, (uint8_t)((r->chr_hi[0] << 4) | r->chr_lo[0]));
        }
        break;
    case 0xC000u:
        r->chr_lo[1] = data & 0x0Fu;
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_4k(nes, 1, (uint8_t)((r->chr_hi[1] << 4) | r->chr_lo[1]));
        }
        break;
    default:
        break;
    }
}

int nes_mapper75_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

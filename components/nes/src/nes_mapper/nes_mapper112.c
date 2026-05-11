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

/* https://www.nesdev.org/wiki/INES_Mapper_112
 * Mapper 112 - NTDEC.
 * Two-register interface: $8000 = register select (bits[2:0]), $A000 = register data.
 * Mirroring at $E000 bit[0] (0=V, 1=H). No IRQ.
 * Reg 0: 8KB PRG bank for $8000-$9FFF
 * Reg 1: 8KB PRG bank for $A000-$BFFF
 * Reg 2: 2KB CHR bank for PPU $0000-$07FF
 * Reg 3: 2KB CHR bank for PPU $0800-$0FFF
 * Reg 4: 1KB CHR bank for PPU $1000-$13FF
 * Reg 5: 1KB CHR bank for PPU $1400-$17FF
 * Reg 6: 1KB CHR bank for PPU $1800-$1BFF
 * Reg 7: 1KB CHR bank for PPU $1C00-$1FFF
 * $C000-$DFFF/$E000-$FFFF: fixed to last two 8KB PRG banks.
 */

typedef struct {
    uint8_t reg_select;
    uint8_t prg[2];     /* regs 0-1: 8KB PRG banks */
    uint8_t chr[6];     /* regs 2-7: chr[0-1]=2KB banks, chr[2-5]=1KB banks */
} mapper112_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper112_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper112_register_t* r = (mapper112_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper112_register_t));

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 1);
    nes_load_prgrom_8k(nes, 2, (uint8_t)(prg_banks - 2));
    nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_banks - 1));

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        nes_load_chrrom_1k(nes, 0, 0);
        nes_load_chrrom_1k(nes, 1, 1);
        nes_load_chrrom_1k(nes, 2, 0);
        nes_load_chrrom_1k(nes, 3, 1);
        for (int i = 4; i < 8; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)i, 0);
        }
    }
}

/*
 * $8000-$9FFF: register select — bits[2:0] latch the target register (0-7)
 * $A000-$BFFF: register data  — write data into the selected register
 *   Reg 0: prg[0] — 8KB PRG at $8000
 *   Reg 1: prg[1] — 8KB PRG at $A000
 *   Reg 2: chr[0] — 2KB CHR at PPU $0000 (value is 2KB bank number)
 *   Reg 3: chr[1] — 2KB CHR at PPU $0800
 *   Reg 4: chr[2] — 1KB CHR at PPU $1000
 *   Reg 5: chr[3] — 1KB CHR at PPU $1400
 *   Reg 6: chr[4] — 1KB CHR at PPU $1800
 *   Reg 7: chr[5] — 1KB CHR at PPU $1C00
 * $E000-$FFFF: mirroring — bit[0]: 0=vertical, 1=horizontal
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper112_register_t* r = (mapper112_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE000u) {
    case 0x8000u: /* $8000-$9FFF: register select */
        r->reg_select = data & 0x07u;
        break;
    case 0xA000u: /* $A000-$BFFF: register data */
        switch (r->reg_select) {
        case 0:
            r->prg[0] = data;
            nes_load_prgrom_8k(nes, 0, r->prg[0]);
            break;
        case 1:
            r->prg[1] = data;
            nes_load_prgrom_8k(nes, 1, r->prg[1]);
            break;
        case 2: /* 2KB CHR at PPU $0000 */
            r->chr[0] = data;
            nes_load_chrrom_1k(nes, 0, (uint8_t)(r->chr[0] * 2u));
            nes_load_chrrom_1k(nes, 1, (uint8_t)(r->chr[0] * 2u + 1u));
            break;
        case 3: /* 2KB CHR at PPU $0800 */
            r->chr[1] = data;
            nes_load_chrrom_1k(nes, 2, (uint8_t)(r->chr[1] * 2u));
            nes_load_chrrom_1k(nes, 3, (uint8_t)(r->chr[1] * 2u + 1u));
            break;
        case 4: /* 1KB CHR at PPU $1000 */
            r->chr[2] = data;
            nes_load_chrrom_1k(nes, 4, r->chr[2]);
            break;
        case 5: /* 1KB CHR at PPU $1400 */
            r->chr[3] = data;
            nes_load_chrrom_1k(nes, 5, r->chr[3]);
            break;
        case 6: /* 1KB CHR at PPU $1800 */
            r->chr[4] = data;
            nes_load_chrrom_1k(nes, 6, r->chr[4]);
            break;
        case 7: /* 1KB CHR at PPU $1C00 */
            r->chr[5] = data;
            nes_load_chrrom_1k(nes, 7, r->chr[5]);
            break;
        default:
            break;
        }
        break;
    case 0xE000u: /* $E000-$FFFF: mirroring */
        if (nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes,
                (data & 1u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        }
        break;
    default:
        break;
    }
}

int nes_mapper112_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

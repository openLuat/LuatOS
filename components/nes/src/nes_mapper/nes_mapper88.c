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

/* https://www.nesdev.org/wiki/INES_Mapper_088
 * Mapper 88 - Namco 118 (simplified MMC3-like, no IRQ, no mirroring control).
 * Two-register interface: even address = register select, odd = register data.
 * Registers 0-1: 2KB CHR banks at PPU $0000/$0800.
 * Registers 2-5: 1KB CHR banks at PPU $1000-$1C00.
 * Registers 6-7: 8KB PRG banks at $8000/$A000.
 * Slots $C000-$FFFF (prg_banks 2-3) are fixed to the last two 8KB PRG banks.
 */

typedef struct {
    uint8_t reg_select;
    uint8_t chr[6]; /* [0-1]=2KB banks (regs 0-1), [2-5]=1KB banks (regs 2-5) */
    uint8_t prg[2]; /* 8KB PRG banks for $8000/$A000 (regs 6-7) */
} mapper88_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper88_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper88_register_t* r = (mapper88_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper88_register_t));

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
 * Even address ($8000, $8002, ...): register select — bits[2:0]
 * Odd  address ($8001, $8003, ...): register data
 *   Reg 0: 2KB CHR at PPU $0000-$07FF (6-bit 2KB bank number)
 *   Reg 1: 2KB CHR at PPU $0800-$0FFF
 *   Reg 2: 1KB CHR at PPU $1000-$13FF (6-bit 1KB bank number)
 *   Reg 3: 1KB CHR at PPU $1400-$17FF
 *   Reg 4: 1KB CHR at PPU $1800-$1BFF
 *   Reg 5: 1KB CHR at PPU $1C00-$1FFF
 *   Reg 6: 8KB PRG bank at $8000-$9FFF
 *   Reg 7: 8KB PRG bank at $A000-$BFFF
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper88_register_t* r = (mapper88_register_t*)nes->nes_mapper.mapper_register;
    if (address & 1u) { /* odd: bank data */
        switch (r->reg_select) {
        case 0: /* 2KB CHR at PPU $0000 */
            r->chr[0] = data & 0x3Fu;
            nes_load_chrrom_1k(nes, 0, (uint8_t)(r->chr[0] * 2u));
            nes_load_chrrom_1k(nes, 1, (uint8_t)(r->chr[0] * 2u + 1u));
            break;
        case 1: /* 2KB CHR at PPU $0800 */
            r->chr[1] = data & 0x3Fu;
            nes_load_chrrom_1k(nes, 2, (uint8_t)(r->chr[1] * 2u));
            nes_load_chrrom_1k(nes, 3, (uint8_t)(r->chr[1] * 2u + 1u));
            break;
        case 2: /* 1KB CHR at PPU $1000 */
            r->chr[2] = data & 0x3Fu;
            nes_load_chrrom_1k(nes, 4, r->chr[2]);
            break;
        case 3: /* 1KB CHR at PPU $1400 */
            r->chr[3] = data & 0x3Fu;
            nes_load_chrrom_1k(nes, 5, r->chr[3]);
            break;
        case 4: /* 1KB CHR at PPU $1800 */
            r->chr[4] = data & 0x3Fu;
            nes_load_chrrom_1k(nes, 6, r->chr[4]);
            break;
        case 5: /* 1KB CHR at PPU $1C00 */
            r->chr[5] = data & 0x3Fu;
            nes_load_chrrom_1k(nes, 7, r->chr[5]);
            break;
        case 6: /* 8KB PRG at $8000 */
            r->prg[0] = data & 0x3Fu;
            nes_load_prgrom_8k(nes, 0, r->prg[0]);
            break;
        case 7: /* 8KB PRG at $A000 */
            r->prg[1] = data & 0x3Fu;
            nes_load_prgrom_8k(nes, 1, r->prg[1]);
            break;
        default:
            break;
        }
    } else { /* even: register select */
        r->reg_select = data & 0x07u;
    }
}

int nes_mapper88_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

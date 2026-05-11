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

/* https://www.nesdev.org/wiki/INES_Mapper_091
 * Mapper 91 - Street Fighter 2 pirate (MMC3-based unlicensed cart).
 * All registers are written via mapper_sram ($6000-$7FFF).
 * 4x1KB CHR banks at PPU $0000-$0FFF; PPU $1000-$1FFF uses last 4 CHR banks (fixed).
 * 2x8KB switchable PRG banks at $8000/$A000; $C000/$E000 fixed to last two banks.
 * Scanline IRQ fires every 8 scanlines (counter 7→0 then reload and assert IRQ).
 */

typedef struct {
    uint8_t chr[4];
    uint8_t prg[2];
    uint8_t irq_enable;
    uint8_t irq_counter;
} mapper91_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper91_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper91_register_t* r = (mapper91_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper91_register_t));
    r->irq_counter = 7;

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 1);
    nes_load_prgrom_8k(nes, 2, (uint8_t)(prg_banks - 2));
    nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_banks - 1));

    /* PPU $1000-$1FFF: fixed to last four 1KB CHR banks */
    if (nes->nes_rom.chr_rom_size > 0) {
        uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8);
        nes_load_chrrom_1k(nes, 0, 0);
        nes_load_chrrom_1k(nes, 1, 1);
        nes_load_chrrom_1k(nes, 2, 2);
        nes_load_chrrom_1k(nes, 3, 3);
        nes_load_chrrom_1k(nes, 4, (uint8_t)(chr_banks - 4));
        nes_load_chrrom_1k(nes, 5, (uint8_t)(chr_banks - 3));
        nes_load_chrrom_1k(nes, 6, (uint8_t)(chr_banks - 2));
        nes_load_chrrom_1k(nes, 7, (uint8_t)(chr_banks - 1));
    } else {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

/*
 * All registers are in $6000-$7FFF (SRAM space):
 *   $6000: 1KB CHR bank for PPU $0000-$03FF — slot 0
 *   $6001: 1KB CHR bank for PPU $0400-$07FF — slot 1
 *   $6002: 1KB CHR bank for PPU $0800-$0BFF — slot 2
 *   $6003: 1KB CHR bank for PPU $0C00-$0FFF — slot 3
 *   $7000: 8KB PRG bank at $8000-$9FFF
 *   $7001: 8KB PRG bank at $A000-$BFFF
 *   $7002: IRQ acknowledge (disable IRQ, clear pending, reset counter)
 *   $7003: IRQ enable (enable IRQ, reset counter to 7)
 * Registers mirror every 4 bytes within each $1000 block.
 */
static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper91_register_t* r = (mapper91_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0x7003u) {
    case 0x6000u:
        r->chr[0] = data;
        nes_load_chrrom_1k(nes, 0, data);
        break;
    case 0x6001u:
        r->chr[1] = data;
        nes_load_chrrom_1k(nes, 1, data);
        break;
    case 0x6002u:
        r->chr[2] = data;
        nes_load_chrrom_1k(nes, 2, data);
        break;
    case 0x6003u:
        r->chr[3] = data;
        nes_load_chrrom_1k(nes, 3, data);
        break;
    case 0x7000u:
        r->prg[0] = data & 0x0Fu;
        nes_load_prgrom_8k(nes, 0, r->prg[0]);
        break;
    case 0x7001u:
        r->prg[1] = data & 0x0Fu;
        nes_load_prgrom_8k(nes, 1, r->prg[1]);
        break;
    case 0x7002u: /* IRQ acknowledge */
        r->irq_enable = 0;
        r->irq_counter = 7;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0x7003u: /* IRQ enable */
        r->irq_enable = 1;
        r->irq_counter = 7;
        break;
    default:
        break;
    }
}

/*
 * Scanline IRQ: counter starts at 7 and decrements each active scanline.
 * When it reaches 0 an IRQ is asserted and the counter reloads to 7,
 * giving a period of 8 scanlines.
 */
static void nes_mapper_hsync(nes_t* nes) {
    mapper91_register_t* r = (mapper91_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (r->irq_counter == 0) {
        r->irq_counter = 7;
        nes_cpu_irq(nes);
    } else {
        r->irq_counter--;
    }
}

int nes_mapper91_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

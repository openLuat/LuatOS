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
 * 4x2KB CHR banks at PPU $0000-$1FFF.
 * 2x8KB switchable PRG banks at $8000/$A000; $C000/$E000 fixed to last two banks.
 * Scanline IRQ asserts once the counter reaches 8, then remains pending until ACK.
 */

typedef struct {
    uint8_t chr[4];
    uint8_t prg[2];
    uint8_t irq_enable;
    uint8_t irq_counter;
} mapper91_register_t;

static void mapper91_load_chr2(nes_t* nes, uint8_t slot, uint8_t bank) {
    uint16_t base;
    if (nes->nes_rom.chr_rom_size > 0u) {
        uint16_t chr2_count = (uint16_t)(nes->nes_rom.chr_rom_size * 4u);
        base = (uint16_t)((bank % chr2_count) * 2u);
    } else {
        base = (uint16_t)(slot * 2u);
    }
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2u), base);
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2u + 1u), (uint16_t)(base + 1u));
}

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

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 0);
    nes_load_prgrom_8k(nes, 2, (uint16_t)(prg_banks - 2u));
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_banks - 1u));

    mapper91_load_chr2(nes, 0, 0);
    mapper91_load_chr2(nes, 1, 0);
    mapper91_load_chr2(nes, 2, 0);
    mapper91_load_chr2(nes, 3, 0);
}

/*
 * All registers are in $6000-$7FFF (SRAM space):
 *   $6000: 2KB CHR bank for PPU $0000-$07FF
 *   $6001: 2KB CHR bank for PPU $0800-$0FFF
 *   $6002: 2KB CHR bank for PPU $1000-$17FF
 *   $6003: 2KB CHR bank for PPU $1800-$1FFF
 *   $7000: 8KB PRG bank at $8000-$9FFF
 *   $7001: 8KB PRG bank at $A000-$BFFF
 *   $7002: IRQ acknowledge (disable IRQ, clear pending, reset counter to 0)
 *   $7003: IRQ enable (enable IRQ, clear pending)
 * Registers mirror every 4 bytes within each $1000 block.
 */
static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper91_register_t* r = (mapper91_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0x7003u) {
    case 0x6000u:
        r->chr[0] = data;
        mapper91_load_chr2(nes, 0, data);
        break;
    case 0x6001u:
        r->chr[1] = data;
        mapper91_load_chr2(nes, 1, data);
        break;
    case 0x6002u:
        r->chr[2] = data;
        mapper91_load_chr2(nes, 2, data);
        break;
    case 0x6003u:
        r->chr[3] = data;
        mapper91_load_chr2(nes, 3, data);
        break;
    case 0x7000u:
        r->prg[0] = data;
        nes_load_prgrom_8k(nes, 0, r->prg[0]);
        break;
    case 0x7001u:
        r->prg[1] = data;
        nes_load_prgrom_8k(nes, 1, r->prg[1]);
        break;
    case 0x7002u: /* IRQ acknowledge */
        r->irq_enable = 0;
        r->irq_counter = 0;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0x7003u: /* IRQ enable */
        r->irq_enable = 1;
        nes->nes_cpu.irq_pending = 0;
        break;
    default:
        break;
    }
}

/*
 * Scanline IRQ: counts up to 8 while enabled. The counter is only reset by
 * $7002; after reaching 8, the IRQ line remains asserted until acknowledged.
 */
static void nes_mapper_hsync(nes_t* nes) {
    mapper91_register_t* r = (mapper91_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (r->irq_counter < 8u) {
        r->irq_counter++;
        if (r->irq_counter >= 8u) {
            nes_cpu_irq(nes);
        }
    }
}

int nes_mapper91_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

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

/*
 * https://www.nesdev.org/wiki/INES_Mapper_253
 * Mapper 253 — VRC4 variant with embedded 2KB CHR-RAM (龙珠Z / Dragon Ball Z series).
 *
 * Identical to mapper 23 (VRC4b) for PRG banking, mirroring, and scanline IRQ.
 * CHR bank values 0 and 1 redirect to the first and second 1KB page of the
 * embedded 2KB chr_ram buffer instead of CHR-ROM.  All other CHR bank values
 * use CHR-ROM normally.
 *
 * Address decode (VRC4b, same as mapper 23):
 *   $8000       : 8KB PRG bank for $8000-$9FFF, bits[4:0]
 *   $9000/$9001 : 8KB PRG bank for $A000-$BFFF, bits[4:0]  (A1=0)
 *   $9002/$9003 : mirroring bits[1:0]                       (A1=1)
 *   $B000-$E003 : 8×1KB CHR banks (two per $1000 block, nibble pairs)
 *   $F000       : IRQ latch
 *   $F001       : IRQ control (bit1=enable, bit2=mode)
 *   $F002       : IRQ acknowledge
 */

typedef struct {
    uint8_t prg[2];
    uint8_t chr[8];
    uint8_t mirror;
    uint8_t irq_enable;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_mode;
    uint8_t chr_bank_count;
    uint8_t chr_ram[2048]; /* 2KB CHR-RAM; bank 0→offset 0, bank 1→offset 1024 */
} mapper253_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

/*
 * Load a single 1KB CHR slot.
 * Bank values 0 and 1 map into embedded chr_ram; all other values use CHR-ROM.
 */
static void mapper253_load_chr1k(nes_t* nes, mapper253_register_t* r,
                                  uint8_t slot, uint8_t bank) {
    if (bank == 0u || bank == 1u) {
        nes->nes_ppu.pattern_table[slot] = r->chr_ram + (uint16_t)bank * 1024u;
    } else if (r->chr_bank_count > 0u) {
        nes_load_chrrom_1k(nes, slot, (uint8_t)(bank % r->chr_bank_count));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper253_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper253_register_t* r = (mapper253_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper253_register_t));

    r->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 1);
    nes_load_prgrom_8k(nes, 2, (uint8_t)(prg_banks - 2u));
    nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_banks - 1u));

    for (int i = 0; i < 8; i++) {
        mapper253_load_chr1k(nes, r, (uint8_t)i, r->chr[i]);
    }
}

/*
 * CHR write helper for $B000-$E003.
 * Each $1000 block covers two 1KB CHR banks.
 * A0 selects nibble (0=low4, 1=high4); A1 selects bank within the block.
 */
static void mapper253_write_chr(mapper253_register_t* r, nes_t* nes,
                                 uint16_t addr, uint8_t data) {
    uint8_t nibble = (uint8_t)(addr & 1u);
    uint8_t sub    = (uint8_t)((addr >> 1u) & 1u);
    uint8_t block  = (uint8_t)((addr >> 12u) - 0xBu); /* 0=$B, 1=$C, 2=$D, 3=$E */
    uint8_t idx    = (uint8_t)(block * 2u + sub);
    if (nibble == 0u) {
        r->chr[idx] = (r->chr[idx] & 0xF0u) | (data & 0x0Fu);
    } else {
        r->chr[idx] = (r->chr[idx] & 0x0Fu) | (uint8_t)((data & 0x0Fu) << 4u);
    }
    mapper253_load_chr1k(nes, r, idx, r->chr[idx]);
}

static const nes_mirror_type_t vrc4_mirror_table[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

/*
 * $8000       : PRG bank 0, bits[4:0]
 * $9000/$9001 : PRG bank 1, bits[4:0]  (A1=0)
 * $9002/$9003 : mirroring, bits[1:0]   (A1=1)
 * $B000-$E003 : CHR 1KB banks (nibble pairs)
 * $F000-$F002 : IRQ latch / control / acknowledge
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper253_register_t* r = (mapper253_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u:
        r->prg[0] = data & 0x1Fu;
        nes_load_prgrom_8k(nes, 0, r->prg[0]);
        break;
    case 0x9000u:
        if (address & 0x0002u) { /* $9002/$9003: mirroring */
            r->mirror = data & 0x03u;
            if (nes->nes_rom.four_screen == 0) {
                nes_ppu_screen_mirrors(nes, vrc4_mirror_table[r->mirror]);
            }
        } else { /* $9000/$9001: PRG bank 1 */
            r->prg[1] = data & 0x1Fu;
            nes_load_prgrom_8k(nes, 1, r->prg[1]);
        }
        break;
    case 0xB000u:
    case 0xC000u:
    case 0xD000u:
    case 0xE000u:
        mapper253_write_chr(r, nes, address, data);
        break;
    case 0xF000u:
        switch (address & 0x0003u) {
        case 0u:
            r->irq_latch = data;
            break;
        case 1u:
            r->irq_mode = (uint8_t)((data >> 2u) & 1u);
            if (data & 0x02u) {
                r->irq_enable  = 1u;
                r->irq_counter = r->irq_latch;
            } else {
                r->irq_enable = 0u;
            }
            break;
        case 2u:
            r->irq_enable = 0u;
            nes->nes_cpu.irq_pending = 0;
            break;
        default:
            break;
        }
        break;
    default:
        break;
    }
}

/* Decrement scanline IRQ counter; fire when it wraps through zero. */
static void nes_mapper_hsync(nes_t* nes) {
    mapper253_register_t* r = (mapper253_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (r->irq_counter == 0u) {
        r->irq_counter = r->irq_latch;
        nes_cpu_irq(nes);
    } else {
        r->irq_counter--;
    }
}

int nes_mapper253_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

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

/* Registered only when NES_ENABLE_HEAVY_MAPPERS is set */

/* https://www.nesdev.org/wiki/VRC7
 * Mapper 85 - VRC7 (Konami VRC7).
 * PRG: three 8KB switchable banks ($8000, $A000, $C000) + fixed last 8KB at $E000.
 * CHR: 8x1KB banks at $A000-$D010 (address bit4 selects high/low bank-in-pair).
 * Mirroring: $E000 bits[3:2] (0=V, 1=H, 2=1scr0, 3=1scr1).
 * Scanline IRQ: $E010 latch, $F000 control, $F010 acknowledge.
 * Audio ($9010/$9030): not emulated.
 */

typedef struct {
    uint8_t prg[3];         /* 8KB PRG banks for $8000, $A000, $C000 */
    uint8_t chr[8];         /* 1KB CHR banks */
    uint8_t mirror;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_enable;
    uint8_t irq_reload;     /* bit0 of $F000: re-enable after acknowledge */
} mapper85_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper85_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper85_register_t* r = (mapper85_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper85_register_t));

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 0);
    nes_load_prgrom_8k(nes, 2, 0);
    nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_banks - 1));

    if (nes->nes_rom.chr_rom_size > 0) {
        for (int i = 0; i < 8; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)i, 0);
        }
    }
}

static const nes_mirror_type_t vrc7_mirror_table[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

/*
 * VRC7 register map (A4 selects offset within pair):
 *   $8000        : 8KB PRG bank for $8000-$9FFF
 *   $8010        : 8KB PRG bank for $A000-$BFFF
 *   $9000        : 8KB PRG bank for $C000-$DFFF
 *   $9010        : FM audio address register - skip
 *   $9030        : FM audio data register - skip
 *   $A000        : CHR bank 0 (PPU $0000)
 *   $A010        : CHR bank 1 (PPU $0400)
 *   $B000        : CHR bank 2 (PPU $0800)
 *   $B010        : CHR bank 3 (PPU $0C00)
 *   $C000        : CHR bank 4 (PPU $1000)
 *   $C010        : CHR bank 5 (PPU $1400)
 *   $D000        : CHR bank 6 (PPU $1800)
 *   $D010        : CHR bank 7 (PPU $1C00)
 *   $E000        : mirroring bits[3:2]
 *   $E010        : IRQ latch
 *   $F000        : IRQ control (bit0=reload-on-ack, bit1=enable, bit2=mode ignored)
 *   $F010        : IRQ acknowledge
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper85_register_t* r = (mapper85_register_t*)nes->nes_mapper.mapper_register;

    /* Use upper nibble + bit4 to decode register */
    switch (address & 0xF010u) {
    case 0x8000u:
        r->prg[0] = data & 0x3Fu;
        nes_load_prgrom_8k(nes, 0, r->prg[0]);
        break;
    case 0x8010u:
        r->prg[1] = data & 0x3Fu;
        nes_load_prgrom_8k(nes, 1, r->prg[1]);
        break;
    case 0x9000u:
        r->prg[2] = data & 0x3Fu;
        nes_load_prgrom_8k(nes, 2, r->prg[2]);
        break;
    /* $9010 / $9030: FM audio - skip */
    case 0xA000u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[0] = data;
        nes_load_chrrom_1k(nes, 0, r->chr[0]);
        break;
    case 0xA010u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[1] = data;
        nes_load_chrrom_1k(nes, 1, r->chr[1]);
        break;
    case 0xB000u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[2] = data;
        nes_load_chrrom_1k(nes, 2, r->chr[2]);
        break;
    case 0xB010u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[3] = data;
        nes_load_chrrom_1k(nes, 3, r->chr[3]);
        break;
    case 0xC000u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[4] = data;
        nes_load_chrrom_1k(nes, 4, r->chr[4]);
        break;
    case 0xC010u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[5] = data;
        nes_load_chrrom_1k(nes, 5, r->chr[5]);
        break;
    case 0xD000u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[6] = data;
        nes_load_chrrom_1k(nes, 6, r->chr[6]);
        break;
    case 0xD010u:
        if (nes->nes_rom.chr_rom_size == 0) break;
        r->chr[7] = data;
        nes_load_chrrom_1k(nes, 7, r->chr[7]);
        break;
    case 0xE000u:
        r->mirror = (data >> 2) & 0x03u;
        if (nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes, vrc7_mirror_table[r->mirror]);
        }
        break;
    case 0xE010u:
        r->irq_latch = data;
        break;
    case 0xF000u:
        r->irq_reload = data & 0x01u;
        if (data & 0x02u) {
            r->irq_enable  = 1;
            r->irq_counter = r->irq_latch;
        } else {
            r->irq_enable = 0;
        }
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0xF010u:
        nes->nes_cpu.irq_pending = 0;
        if (r->irq_reload) {
            r->irq_enable  = 1;
            r->irq_counter = r->irq_latch;
        } else {
            r->irq_enable = 0;
        }
        break;
    default:
        break;
    }
}

/* Decrement scanline IRQ counter; fire when it wraps through zero. */
static void nes_mapper_hsync(nes_t* nes) {
    mapper85_register_t* r = (mapper85_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (r->irq_counter == 0) {
        r->irq_counter = r->irq_latch;
        nes_cpu_irq(nes);
    } else {
        r->irq_counter--;
    }
}

int nes_mapper85_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

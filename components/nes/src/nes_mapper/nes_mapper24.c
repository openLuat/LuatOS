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

/* https://www.nesdev.org/wiki/VRC6
 * Mapper 24 - VRC6a (Konami VRC6).
 * PRG: 16KB switchable at $8000, 8KB switchable at $C000, fixed last 8KB at $E000.
 * CHR: 8x1KB banks at $D000-$E003.
 * Mirroring: $B003 bits[3:2].
 * IRQ: $F000-$F002, CPU-clocked with scanline mode ticking every 341 PPU dots.
 * Audio ($9000-$B002): not emulated.
 */

typedef struct {
    uint8_t prg16;          /* 16KB PRG bank for $8000-$BFFF */
    uint8_t prg8;           /*  8KB PRG bank for $C000-$DFFF */
    uint8_t chr[8];         /* 1KB CHR banks */
    uint8_t mirror;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_enable;
    uint8_t irq_enable_ack; /* bit0 of $F001: re-enable after acknowledge */
    uint8_t irq_cycle_mode;
    uint16_t irq_cycle_accum;
} mapper24_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper24_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper24_register_t* r = (mapper24_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper24_register_t));

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 2, 0);
    nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_banks - 1));

    if (nes->nes_rom.chr_rom_size > 0) {
        for (int i = 0; i < 8; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)i, 0);
        }
    }
}

static const nes_mirror_type_t vrc6_mirror_table[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

/*
 * $8000        : 16KB PRG bank select for $8000-$BFFF, bits[3:0]
 * $B003        : mirroring bits[3:2]  (0=V, 1=H, 2=1scr0, 3=1scr1)
 * $C000        : 8KB PRG bank select for $C000-$DFFF, bits[4:0]
 * $D000-$E003  : 8x1KB CHR banks (VRC6a: A1:A0 direct)
 * $F000        : IRQ latch
 * $F001        : IRQ control (bit0=enable-after-ack, bit1=enable, bit2=cycle mode)
 * $F002        : IRQ acknowledge
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper24_register_t* r = (mapper24_register_t*)nes->nes_mapper.mapper_register;

    switch (address & 0xF000u) {
    case 0x8000u:
        r->prg16 = data & 0x0Fu;
        nes_load_prgrom_16k(nes, 0, r->prg16);
        break;
    case 0xB000u:
        if ((address & 0x0003u) == 3u) {
            r->mirror = (data >> 2) & 0x03u;
            if (nes->nes_rom.four_screen == 0) {
                nes_ppu_screen_mirrors(nes, vrc6_mirror_table[r->mirror]);
            }
        }
        /* $B000-$B002: pulse2 / sawtooth audio regs - skip */
        break;
    case 0xC000u:
        if ((address & 0x0003u) == 0u) {
            r->prg8 = data & 0x1Fu;
            nes_load_prgrom_8k(nes, 2, r->prg8);
        }
        /* $C001-$C002: pulse2 audio - skip */
        break;
    case 0xD000u:
    case 0xE000u: {
        if (nes->nes_rom.chr_rom_size == 0) break;
        /* VRC6a: idx = (block)*4 + (addr & 3), but only 0-3 per block → 8 total */
        uint8_t block = (uint8_t)((address >> 12) - 0xDu); /* 0 or 1 */
        uint8_t sub   = (uint8_t)(address & 0x0003u);
        uint8_t idx   = (uint8_t)(block * 4u + sub);
        r->chr[idx] = data;
        const uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
        nes_load_chrrom_1k(nes, idx, (uint8_t)(r->chr[idx] % chr_banks));
        break;
    }
    case 0xF000u:
        switch (address & 0x0003u) {
        case 0u:
            r->irq_latch = data;
            nes->nes_cpu.irq_pending = 0;
            break;
        case 1u:
            r->irq_cycle_accum = 0;
            r->irq_cycle_mode = data & 0x04u;
            r->irq_enable = data & 0x02u;
            r->irq_enable_ack = data & 0x01u;
            if (data & 0x02u) {
                r->irq_counter = r->irq_latch;
            }
            nes->nes_cpu.irq_pending = 0;
            break;
        case 2u:
            nes->nes_cpu.irq_pending = 0;
            r->irq_enable = r->irq_enable_ack;
            break;
        default:
            break;
        }
        break;
    default:
        break;
    }
}

static void mapper24_irq_tick(nes_t* nes) {
    mapper24_register_t* r = (mapper24_register_t*)nes->nes_mapper.mapper_register;
    if (r->irq_counter == 0xFFu) {
        r->irq_counter = r->irq_latch;
        nes_cpu_irq(nes);
    } else {
        r->irq_counter++;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper24_register_t* r = (mapper24_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (r->irq_cycle_mode) {
        while (cycles--) {
            mapper24_irq_tick(nes);
        }
        return;
    }

    r->irq_cycle_accum = (uint16_t)(r->irq_cycle_accum + cycles * 3u);
    while (r->irq_cycle_accum >= 341u) {
        r->irq_cycle_accum = (uint16_t)(r->irq_cycle_accum - 341u);
        mapper24_irq_tick(nes);
    }
}

int nes_mapper24_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

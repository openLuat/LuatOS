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

/* https://www.nesdev.org/wiki/INES_Mapper_064 — Tengen RAMBO-1 */

typedef struct {
    uint8_t cmd;            /* $8000 bank select register */
    uint8_t regs[11];       /* 0-5/8/9 CHR, 6/7/10 PRG */
    uint8_t irq_mode;       /* 0: scanline mode, 1: CPU-cycle mode */
    uint8_t irq_enable;
    uint8_t irq_counter;
    uint8_t irq_latch;
    uint8_t reload_mode;
    uint16_t irq_cycle_accum;
} nes_mapper64_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper64_update_banks(nes_t* nes) {
    nes_mapper64_t* m = (nes_mapper64_t*)nes->nes_mapper.mapper_register;
    const uint8_t prg_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);

    /* PRG: regs 6/7/F swappable at $8000/$A000/$C000; $E000 fixed to last */
    nes_load_prgrom_8k(nes, 0, m->regs[6] % prg_count);
    nes_load_prgrom_8k(nes, 1, m->regs[7] % prg_count);
    nes_load_prgrom_8k(nes, 2, m->regs[10] % prg_count);
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_count - 1));

    if (nes->nes_rom.chr_rom_size == 0) return;
    const uint8_t chr_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);

    /*
     * RAMBO-1 CHR layout:
     *   cmd bit 5 = 0: regs 0/1 are 2KB banks at $0000/$0800.
     *   cmd bit 5 = 1: regs 0/8/1/9 are 1KB banks at $0000/$0400/$0800/$0C00.
     *   regs 2-5 are always 1KB banks at $1000-$1FFF.
     */
    if (m->cmd & 0x20u) {
        nes_load_chrrom_1k(nes, 0, m->regs[0] % chr_count);
        nes_load_chrrom_1k(nes, 1, m->regs[8] % chr_count);
        nes_load_chrrom_1k(nes, 2, m->regs[1] % chr_count);
        nes_load_chrrom_1k(nes, 3, m->regs[9] % chr_count);
    } else {
        nes_load_chrrom_1k(nes, 0, (uint8_t)((m->regs[0] & 0xFEu) % chr_count));
        nes_load_chrrom_1k(nes, 1, (uint8_t)((m->regs[0] | 0x01u) % chr_count));
        nes_load_chrrom_1k(nes, 2, (uint8_t)((m->regs[1] & 0xFEu) % chr_count));
        nes_load_chrrom_1k(nes, 3, (uint8_t)((m->regs[1] | 0x01u) % chr_count));
    }
    nes_load_chrrom_1k(nes, 4, m->regs[2] % chr_count);
    nes_load_chrrom_1k(nes, 5, m->regs[3] % chr_count);
    nes_load_chrrom_1k(nes, 6, m->regs[4] % chr_count);
    nes_load_chrrom_1k(nes, 7, m->regs[5] % chr_count);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper64_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper64_t* m = (nes_mapper64_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(nes_mapper64_t));
    nes_memset(m->regs, 0xFF, sizeof(m->regs));

    mapper64_update_banks(nes);

    if (nes->nes_rom.mirroring_type) {
        nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);
    } else {
        nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);
    }
}

/*
 * $8000 (even): Bank select
 *   bits[3:0]: register index (0-9, F used)
 *   bit[5]:    CHR mode (0: two 2KB banks at $0000/$0800, 1: four 1KB banks)
 * $8001 (odd):  Bank data written to register indexed by last $8000 write
 * $A000 (even): Mirroring — bit[0]: 0=V, 1=H
 * $C000 (even): IRQ latch (8-bit)
 * $C001 (odd):  IRQ reload and mode select (bit 0: CPU-cycle mode)
 * $E000 (even): IRQ disable + acknowledge
 * $E001 (odd):  IRQ enable
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper64_t* m = (nes_mapper64_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF001u) {
    case 0x8000:
        m->cmd = data;
        break;
    case 0x8001: {
        const uint8_t reg = m->cmd & 0x0Fu;
        if (reg < 10u) {
            m->regs[reg] = data;
        } else if (reg == 0x0Fu) {
            m->regs[10] = data;
        }
        mapper64_update_banks(nes);
        break;
    }
    case 0xA000:
        nes_ppu_screen_mirrors(nes, (data & 0x1u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        break;
    case 0xC000:
        m->irq_latch = data;
        if (m->reload_mode == 1u) {
            m->irq_counter = m->irq_latch;
        }
        break;
    case 0xC001:
        m->reload_mode = 1;
        m->irq_counter = m->irq_latch;
        m->irq_mode = data & 0x01u;
        break;
    case 0xE000:
        m->irq_enable = 0;
        nes->nes_cpu.irq_pending = 0;
        if (m->reload_mode == 1u) {
            m->irq_counter = m->irq_latch;
        }
        break;
    case 0xE001:
        m->irq_enable = 1;
        if (m->reload_mode == 1u) {
            m->irq_counter = m->irq_latch;
        }
        break;
    default:
        break;
    }
}

static void mapper64_clock_irq(nes_t* nes, uint8_t reload_on_scanline_irq) {
    nes_mapper64_t* m = (nes_mapper64_t*)nes->nes_mapper.mapper_register;
    m->irq_counter--;
    if (m->irq_counter == 0xFFu && m->irq_enable) {
        if (reload_on_scanline_irq) {
            m->reload_mode = 1;
        }
        nes_cpu_irq(nes);
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    nes_mapper64_t* m = (nes_mapper64_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_mode) return;

    m->irq_cycle_accum = (uint16_t)(m->irq_cycle_accum + cycles);
    while (m->irq_cycle_accum >= 4u) {
        m->irq_cycle_accum = (uint16_t)(m->irq_cycle_accum - 4u);
        mapper64_clock_irq(nes, 0);
    }
}

static void nes_mapper_hsync(nes_t* nes) {
    nes_mapper64_t* m = (nes_mapper64_t*)nes->nes_mapper.mapper_register;
    if (m->irq_mode) return;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;

    m->reload_mode = 0;
    mapper64_clock_irq(nes, 1);
}

int nes_mapper64_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

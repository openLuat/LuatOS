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
 * Mapper 26 - VRC6b (Konami VRC6 address-swapped variant).
 * Identical to mapper 24 (VRC6a) except address lines A0 and A1 are swapped.
 * Normalization: swap bit0 and bit1 of the address, then apply VRC6a logic.
 * PRG: 16KB switchable at $8000, 8KB switchable at $C000, fixed last 8KB at $E000.
 * CHR: 8x1KB banks.
 * Mirroring: $B003 bits[3:2].
 * WRAM: 8KB at $6000-$7FFF.
 * IRQ: $F000-$F002 (normalized), CPU-clocked like VRC6a.
 * Audio: not emulated.
 */

typedef struct {
    uint8_t prg16;
    uint8_t prg8;
    uint8_t chr[8];
    uint8_t mirror;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_enable;
    uint8_t irq_enable_ack;
    uint8_t irq_cycle_mode;
    uint16_t irq_cycle_accum;
} mapper26_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper26_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper26_register_t* r = (mapper26_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper26_register_t));

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 2, 0);
    nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_banks - 1));

    if (nes->nes_rom.chr_rom_size > 0) {
        for (int i = 0; i < 8; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)i, 0);
        }
    }

    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        } else {
            NES_LOG_ERROR("mapper26: failed to allocate SRAM\n");
        }
    }
}

static const nes_mirror_type_t vrc6b_mirror_table[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

/* Swap address bits 0 and 1 to convert VRC6b addresses to VRC6a-equivalent. */
static inline uint16_t vrc6b_normalize(uint16_t addr) {
    return (uint16_t)((addr & 0xFFFCu) | ((addr & 1u) << 1) | ((addr >> 1) & 1u));
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper26_register_t* r = (mapper26_register_t*)nes->nes_mapper.mapper_register;
    uint16_t addr = vrc6b_normalize(address);

    switch (addr & 0xF000u) {
    case 0x8000u:
        r->prg16 = data & 0x0Fu;
        nes_load_prgrom_16k(nes, 0, r->prg16);
        break;
    case 0xB000u:
        if ((addr & 0x0003u) == 3u) {
            r->mirror = (data >> 2) & 0x03u;
            if (nes->nes_rom.four_screen == 0) {
                nes_ppu_screen_mirrors(nes, vrc6b_mirror_table[r->mirror]);
            }
        }
        /* $B000-$B002: pulse2 / sawtooth audio regs - skip */
        break;
    case 0xC000u:
        if ((addr & 0x0003u) == 0u) {
            r->prg8 = data & 0x1Fu;
            nes_load_prgrom_8k(nes, 2, r->prg8);
        }
        /* $C001-$C002: audio - skip */
        break;
    case 0xD000u:
    case 0xE000u: {
        if (nes->nes_rom.chr_rom_size == 0) break;
        uint8_t block = (uint8_t)((addr >> 12) - 0xDu);
        uint8_t sub   = (uint8_t)(addr & 0x0003u);
        uint8_t idx   = (uint8_t)(block * 4u + sub);
        r->chr[idx] = data;
        const uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
        nes_load_chrrom_1k(nes, idx, (uint8_t)(r->chr[idx] % chr_banks));
        break;
    }
    case 0xF000u:
        switch (addr & 0x0003u) {
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

static void mapper26_irq_tick(nes_t* nes) {
    mapper26_register_t* r = (mapper26_register_t*)nes->nes_mapper.mapper_register;
    if (r->irq_counter == 0xFFu) {
        r->irq_counter = r->irq_latch;
        nes_cpu_irq(nes);
    } else {
        r->irq_counter++;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper26_register_t* r = (mapper26_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (r->irq_cycle_mode) {
        while (cycles--) {
            mapper26_irq_tick(nes);
        }
        return;
    }

    r->irq_cycle_accum = (uint16_t)(r->irq_cycle_accum + cycles * 3u);
    while (r->irq_cycle_accum >= 341u) {
        r->irq_cycle_accum = (uint16_t)(r->irq_cycle_accum - 341u);
        mapper26_irq_tick(nes);
    }
}

int nes_mapper26_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

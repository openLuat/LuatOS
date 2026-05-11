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

/* https://www.nesdev.org/wiki/INES_Mapper_158
 * Mapper 158 — Tengen 800037 (RAMBO-1 variant).
 * Identical to mapper 64 (RAMBO-1) but with reversed IRQ polarity:
 * IRQ fires when counter reaches 0 on the first CHR fetch after reload.
 * For MCU simplicity, use same bank mapping as mapper 64 with standard IRQ.
 */

typedef struct {
    uint8_t bank_select;
    uint8_t bank_values[12];
    uint8_t mirroring;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_reload;
    uint8_t irq_enabled;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper158_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper158_update_banks(nes_t* nes) {
    mapper158_t* m = (mapper158_t*)nes->nes_mapper.mapper_register;
    uint8_t prg8 = m->prg_bank_count;
    if (prg8 == 0u) prg8 = 1u;
    uint8_t chr = m->chr_bank_count;
    if (chr == 0u) chr = 1u;

    uint8_t prg_mode = (m->bank_select >> 6u) & 0x01u;
    if (prg_mode == 0u) {
        nes_load_prgrom_8k(nes, 0, m->bank_values[6] % prg8);
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % prg8);
        nes_load_prgrom_8k(nes, 2, (uint8_t)((prg8 - 2u) % prg8));
        nes_load_prgrom_8k(nes, 3, (uint8_t)((prg8 - 1u) % prg8));
    } else {
        nes_load_prgrom_8k(nes, 0, (uint8_t)((prg8 - 2u) % prg8));
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % prg8);
        nes_load_prgrom_8k(nes, 2, m->bank_values[6] % prg8);
        nes_load_prgrom_8k(nes, 3, (uint8_t)((prg8 - 1u) % prg8));
    }

    uint8_t chr_mode = (m->bank_select >> 7u) & 0x01u;
    if (chr_mode == 0u) {
        nes_load_chrrom_1k(nes, 0, (uint8_t)((m->bank_values[0] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 1, (uint8_t)((m->bank_values[0] | 0x01u) % chr));
        nes_load_chrrom_1k(nes, 2, (uint8_t)((m->bank_values[1] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 3, (uint8_t)((m->bank_values[1] | 0x01u) % chr));
        nes_load_chrrom_1k(nes, 4, m->bank_values[2] % chr);
        nes_load_chrrom_1k(nes, 5, m->bank_values[3] % chr);
        nes_load_chrrom_1k(nes, 6, m->bank_values[4] % chr);
        nes_load_chrrom_1k(nes, 7, m->bank_values[5] % chr);
    } else {
        nes_load_chrrom_1k(nes, 0, m->bank_values[2] % chr);
        nes_load_chrrom_1k(nes, 1, m->bank_values[3] % chr);
        nes_load_chrrom_1k(nes, 2, m->bank_values[4] % chr);
        nes_load_chrrom_1k(nes, 3, m->bank_values[5] % chr);
        nes_load_chrrom_1k(nes, 4, (uint8_t)((m->bank_values[0] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 5, (uint8_t)((m->bank_values[0] | 0x01u) % chr));
        nes_load_chrrom_1k(nes, 6, (uint8_t)((m->bank_values[1] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 7, (uint8_t)((m->bank_values[1] | 0x01u) % chr));
    }

    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, m->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper158_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper158_t* m = (mapper158_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper158_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper158_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper158_t* m = (mapper158_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001u) {
    case 0x8000u: m->bank_select = data; mapper158_update_banks(nes); break;
    case 0x8001u:
        if ((m->bank_select & 0x0Fu) < 8u)
            m->bank_values[m->bank_select & 0x0Fu] = data;
        else
            m->bank_values[m->bank_select & 0x0Fu] = data;
        mapper158_update_banks(nes);
        break;
    case 0xA000u: m->mirroring = data & 0x01u; mapper158_update_banks(nes); break;
    case 0xC000u: m->irq_latch   = data; break;
    case 0xC001u: m->irq_reload  = 1u; break;
    case 0xE000u: m->irq_enabled = 0u; nes->nes_cpu.irq_pending = 0u; break;
    case 0xE001u: m->irq_enabled = 1u; break;
    default: break;
    }
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper158_t* m = (mapper158_t*)nes->nes_mapper.mapper_register;
    if (m->irq_reload || m->irq_counter == 0u) {
        m->irq_counter = m->irq_latch;
        m->irq_reload  = 0u;
    } else {
        m->irq_counter--;
    }
    if (m->irq_counter == 0u && m->irq_enabled)
        nes_cpu_irq(nes);
}

int nes_mapper158_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

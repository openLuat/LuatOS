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

/* https://www.nesdev.org/wiki/INES_Mapper_252
 * Mapper 252 — VRC4 pirate / Contra Fighter pirate.
 * VRC4-like register layout on a pirate board.
 * Simplified as VRC4 analog.
 */

typedef struct {
    uint8_t prg[2];
    uint8_t chr[8];
    uint8_t mirror;
    uint8_t irq_enable;
    uint8_t irq_mode;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper252_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper252_update_banks(nes_t* nes) {
    mapper252_t* m = (mapper252_t*)nes->nes_mapper.mapper_register;
    uint8_t last  = (uint8_t)(m->prg_bank_count - 1u);
    uint8_t slast = (uint8_t)(m->prg_bank_count - 2u);
    nes_load_prgrom_8k(nes, 0, m->prg[0] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 2, slast);
    nes_load_prgrom_8k(nes, 3, last);

    if (m->chr_bank_count > 0u) {
        for (uint8_t i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, (uint8_t)(m->chr[i] % m->chr_bank_count));
    }
    if (nes->nes_rom.four_screen == 0) {
        switch (m->mirror & 0x03u) {
        case 0u: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
        case 1u: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
        case 2u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
        default: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
        }
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper252_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper252_t* m = (mapper252_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper252_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper252_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper252_t* m = (mapper252_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u: m->prg[0] = data & 0x1Fu; mapper252_update_banks(nes); break;
    case 0x9000u:
        if (address & 0x0002u) { /* $9002 */ }
        else m->mirror = data & 0x03u;
        mapper252_update_banks(nes);
        break;
    case 0xA000u: m->prg[1] = data & 0x1Fu; mapper252_update_banks(nes); break;
    case 0xB000u: {
        uint8_t slot = (uint8_t)((address >> 1u) & 0x03u);
        if (address & 1u) m->chr[slot] = (uint8_t)((m->chr[slot] & 0x0Fu) | (data << 4u));
        else              m->chr[slot] = (uint8_t)((m->chr[slot] & 0xF0u) | (data & 0x0Fu));
        mapper252_update_banks(nes);
        break;
    }
    case 0xC000u: {
        uint8_t slot = (uint8_t)(((address >> 1u) & 0x03u) + 4u);
        if (address & 1u) m->chr[slot] = (uint8_t)((m->chr[slot] & 0x0Fu) | (data << 4u));
        else              m->chr[slot] = (uint8_t)((m->chr[slot] & 0xF0u) | (data & 0x0Fu));
        mapper252_update_banks(nes);
        break;
    }
    case 0xD000u: m->irq_latch = (uint8_t)((m->irq_latch & 0xF0u) | (data & 0x0Fu)); break;
    case 0xE000u:
        if (!(address & 2u)) m->irq_latch = (uint8_t)((m->irq_latch & 0x0Fu) | (data << 4u));
        else {
            m->irq_mode    = data & 0x04u;
            m->irq_enable  = data & 0x02u;
            if (m->irq_enable) m->irq_counter = m->irq_latch;
            else nes->nes_cpu.irq_pending = 0;
        }
        break;
    case 0xF000u:
        m->irq_enable = data & 0x01u;
        nes->nes_cpu.irq_pending = 0;
        break;
    default: break;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper252_t* m = (mapper252_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable) return;
    m->irq_counter = (uint8_t)(m->irq_counter + cycles);
    if (m->irq_counter >= 0xFFu) {
        m->irq_counter = m->irq_latch;
        nes_cpu_irq(nes);
    }
}

int nes_mapper252_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

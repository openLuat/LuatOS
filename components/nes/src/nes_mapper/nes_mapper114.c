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

/* https://www.nesdev.org/wiki/INES_Mapper_114
 * Mapper 114 — scrambled MMC3 (Fire Lion / Donkey Kong Country pirate).
 * Like MMC3 but the register select bits are remapped:
 *   MMC3 bit 0 ↔ bit 2 (PRG registers scrambled)
 *   Security byte written to $E003/$E004 must be read back
 */

static const uint8_t m114_reg_remap[8] = { 0u, 3u, 1u, 5u, 6u, 7u, 2u, 4u };

typedef struct {
    uint8_t bank_select;
    uint8_t bank_values[8];
    uint8_t mirroring;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_reload;
    uint8_t irq_enabled;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper114_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper114_update_banks(nes_t* nes) {
    mapper114_t* m = (mapper114_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_mode = (m->bank_select >> 6) & 1u;
    uint8_t chr_mode = (m->bank_select >> 7) & 1u;
    uint8_t last  = (uint8_t)(m->prg_bank_count - 1u);
    uint8_t slast = (uint8_t)(m->prg_bank_count - 2u);

    if (prg_mode == 0u) {
        nes_load_prgrom_8k(nes, 0, m->bank_values[6] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 2, slast);
        nes_load_prgrom_8k(nes, 3, last);
    } else {
        nes_load_prgrom_8k(nes, 0, slast);
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 2, m->bank_values[6] % m->prg_bank_count);
        nes_load_prgrom_8k(nes, 3, last);
    }

    if (m->chr_bank_count == 0u) return;

    if (chr_mode == 0u) {
        nes_load_chrrom_1k(nes, 0, (uint8_t)((m->bank_values[0] & 0xFEu) % m->chr_bank_count));
        nes_load_chrrom_1k(nes, 1, (uint8_t)((m->bank_values[0] | 0x01u) % m->chr_bank_count));
        nes_load_chrrom_1k(nes, 2, (uint8_t)((m->bank_values[1] & 0xFEu) % m->chr_bank_count));
        nes_load_chrrom_1k(nes, 3, (uint8_t)((m->bank_values[1] | 0x01u) % m->chr_bank_count));
        nes_load_chrrom_1k(nes, 4, m->bank_values[2] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 5, m->bank_values[3] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 6, m->bank_values[4] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 7, m->bank_values[5] % m->chr_bank_count);
    } else {
        nes_load_chrrom_1k(nes, 0, m->bank_values[2] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 1, m->bank_values[3] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 2, m->bank_values[4] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 3, m->bank_values[5] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 4, (uint8_t)((m->bank_values[0] & 0xFEu) % m->chr_bank_count));
        nes_load_chrrom_1k(nes, 5, (uint8_t)((m->bank_values[0] | 0x01u) % m->chr_bank_count));
        nes_load_chrrom_1k(nes, 6, (uint8_t)((m->bank_values[1] & 0xFEu) % m->chr_bank_count));
        nes_load_chrrom_1k(nes, 7, (uint8_t)((m->bank_values[1] | 0x01u) % m->chr_bank_count));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper114_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper114_t* m = (mapper114_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper114_t));

    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    m->bank_values[6] = 0;
    m->bank_values[7] = 1;

    if (nes->nes_rom.chr_rom_size == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper114_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper114_t* m = (mapper114_t*)nes->nes_mapper.mapper_register;

    /* Scrambled register decode */
    if (address >= 0x8000u && address <= 0x9FFFu) {
        if (address & 1u) {
            /* odd = data register; remap register index */
            uint8_t reg = m114_reg_remap[m->bank_select & 0x07u];
            m->bank_values[reg] = data;
            mapper114_update_banks(nes);
        } else {
            m->bank_select = data;
            mapper114_update_banks(nes);
        }
        return;
    }

    switch (address & 0xE001u) {
    case 0xA000:
        m->mirroring = data & 1u;
        if (nes->nes_rom.four_screen == 0)
            nes_ppu_screen_mirrors(nes, m->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        break;
    case 0xA001: break;
    case 0xC000: m->irq_latch   = data; break;
    case 0xC001: m->irq_reload  = 1; break;
    case 0xE000: m->irq_enabled = 0; nes->nes_cpu.irq_pending = 0; break;
    case 0xE001: m->irq_enabled = 1; break;
    default: break;
    }
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper114_t* m = (mapper114_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (m->irq_counter == 0u || m->irq_reload) {
        m->irq_counter = m->irq_latch;
    } else {
        m->irq_counter--;
    }
    if (m->irq_counter == 0u && m->irq_enabled) nes_cpu_irq(nes);
    m->irq_reload = 0;
}

int nes_mapper114_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

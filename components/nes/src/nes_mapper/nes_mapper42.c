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

/* https://www.nesdev.org/wiki/INES_Mapper_042
 * Mapper 42 — Mario Baby (Ai Senshi Nicol pirate).
 * 32KB PRG at $8000 fixed to last 32KB.
 * 8KB CHR bank via bits[3:0] of write to $E000-$FFFF.
 * 8KB PRG bank mapped to $6000-$7FFF via bits[3:0] of write to $E000.
 * IRQ fires after 32768 CPU clocks.
 */

typedef struct {
    uint8_t chr_bank;
    uint8_t prg_bank;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
    uint8_t irq_enable;
    uint16_t irq_counter;
} mapper42_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper42_update_banks(nes_t* nes) {
    mapper42_t* m = (mapper42_t*)nes->nes_mapper.mapper_register;
    uint8_t last = (uint8_t)(m->prg_bank_count - 1u);
    uint8_t slast = (uint8_t)(m->prg_bank_count >= 2u ? m->prg_bank_count - 2u : 0u);
    /* Fixed 32KB PRG at $8000 = last 4 banks */
    nes_load_prgrom_8k(nes, 0, (uint8_t)(m->prg_bank % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 1, (uint8_t)(last - 3u));
    nes_load_prgrom_8k(nes, 2, slast);
    nes_load_prgrom_8k(nes, 3, last);
    if (m->chr_bank_count > 0u) {
        uint8_t chr8 = (uint8_t)(m->chr_bank_count / 8u);
        if (chr8 == 0u) chr8 = 1u;
        nes_load_chrrom_8k(nes, 0, (uint8_t)(m->chr_bank % chr8));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper42_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper42_t* m = (mapper42_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper42_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper42_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper42_t* m = (mapper42_t*)nes->nes_mapper.mapper_register;
    if (address >= 0xE000u) {
        m->chr_bank = data & 0x0Fu;
        m->prg_bank = (data >> 4u) & 0x0Fu;
        mapper42_update_banks(nes);
    } else if (address >= 0x8000u) {
        if (address & 0x2000u) {
            /* $A000 area: IRQ control */
            if (data & 1u) {
                m->irq_enable = 1;
                m->irq_counter = 0;
            } else {
                m->irq_enable = 0;
                nes->nes_cpu.irq_pending = 0;
            }
        }
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper42_t* m = (mapper42_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable) return;
    m->irq_counter = (uint16_t)(m->irq_counter + cycles);
    if (m->irq_counter >= 0x8000u) {
        m->irq_counter = (uint16_t)(m->irq_counter & 0x7FFFu);
        nes_cpu_irq(nes);
    }
}

int nes_mapper42_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

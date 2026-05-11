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

/* https://www.nesdev.org/wiki/INES_Mapper_040
 * Mapper 40 — NTDEC 2722 (pirate Super Mario Bros 2 / Yume Kojo).
 * Fixed PRG at $C000-$FFFF, 8KB window at $6000-$7FFF banked.
 * IRQ fires after 4096 CPU cycles, then reloads.
 * PRG 8KB bank written to $8000-$9FFF bits[2:0].
 */

typedef struct {
    uint8_t prg_bank;
    uint8_t prg_bank_count;
    uint8_t irq_enable;
    uint16_t irq_counter;
} mapper40_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper40_update_banks(nes_t* nes) {
    mapper40_t* m = (mapper40_t*)nes->nes_mapper.mapper_register;
    uint8_t last  = (uint8_t)(m->prg_bank_count - 1u);
    uint8_t slast = (uint8_t)(m->prg_bank_count - 2u);
    /* $6000: bank[6], $8000: bank[4], $A000: bank[5], $C000: last-1, $E000: last */
    nes_load_prgrom_8k(nes, 0, m->prg_bank % m->prg_bank_count);  /* $8000 */
    nes_load_prgrom_8k(nes, 1, (uint8_t)((m->prg_bank + 1u) % m->prg_bank_count));
    nes_load_prgrom_8k(nes, 2, slast);
    nes_load_prgrom_8k(nes, 3, last);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper40_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper40_t* m = (mapper40_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper40_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    mapper40_update_banks(nes);
    if (nes->nes_rom.chr_rom_size == 0u) nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper40_t* m = (mapper40_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE000u) {
    case 0x8000u:
        m->irq_enable = 0;
        m->irq_counter = 0;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0xA000u:
        m->irq_enable = 1;
        m->irq_counter = 0;
        break;
    case 0xC000u:
        m->prg_bank = data & 0x07u;
        mapper40_update_banks(nes);
        break;
    default: break;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper40_t* m = (mapper40_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable) return;
    m->irq_counter = (uint16_t)(m->irq_counter + cycles);
    if (m->irq_counter >= 4096u) {
        m->irq_counter = (uint16_t)(m->irq_counter - 4096u);
        nes_cpu_irq(nes);
    }
}

int nes_mapper40_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_159
 * Mapper 159 — Bandai 24C01 (Datach: Dragon Ball Z II, etc.).
 * Like mapper 16 but without EEPROM write support.
 * CHR 1KB × 8 banks, PRG 16KB × 2 banks, CPU-cycle IRQ.
 */

typedef struct {
    uint8_t chr[8];
    uint8_t prg;
    uint8_t irq_enable;
    uint16_t irq_counter;
    uint16_t irq_latch;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper159_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper159_update_banks(nes_t* nes) {
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    uint8_t prg16 = (uint8_t)(m->prg_bank_count / 2u);
    if (prg16 == 0u) prg16 = 1u;
    nes_load_prgrom_16k(nes, 0, (uint16_t)(m->prg % prg16));
    nes_load_prgrom_16k(nes, 1, (uint16_t)(prg16 - 1u));
    if (m->chr_bank_count > 0u) {
        for (uint8_t i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, (uint8_t)(m->chr[i] % m->chr_bank_count));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper159_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper159_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    if (m->chr_bank_count == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper159_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    uint8_t reg = (uint8_t)(address & 0x0Fu);
    switch (reg) {
    case 0u: case 1u: case 2u: case 3u:
    case 4u: case 5u: case 6u: case 7u:
        m->chr[reg] = data;
        mapper159_update_banks(nes);
        break;
    case 8u:
        m->prg = data & 0x0Fu;
        mapper159_update_banks(nes);
        break;
    case 9u:  m->irq_latch = (uint16_t)((m->irq_latch & 0xFF00u) | data); break;
    case 10u: m->irq_latch = (uint16_t)((m->irq_latch & 0x00FFu) | ((uint16_t)data << 8u)); break;
    case 11u:
        m->irq_enable  = data & 0x01u;
        m->irq_counter = m->irq_latch;
        nes->nes_cpu.irq_pending = 0;
        break;
    default: break;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper159_t* m = (mapper159_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable) return;
    if (m->irq_counter <= (uint16_t)cycles) {
        m->irq_counter = 0u;
        m->irq_enable  = 0u;
        nes_cpu_irq(nes);
    } else {
        m->irq_counter = (uint16_t)(m->irq_counter - cycles);
    }
}

int nes_mapper159_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

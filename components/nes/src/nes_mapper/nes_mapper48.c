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

/* https://www.nesdev.org/wiki/INES_Mapper_048
 * Mapper 48 — Taito TC190V.
 * PRG: 2 × 8KB at $8000/$A000, fixed 16KB at $C000.
 * CHR: 2 × 2KB at $0000/$0800, 4 × 1KB at $1000-$1C00.
 * $8000: PRG bank 0 (bits[5:0])
 * $8001: PRG bank 1
 * $8002: CHR 2KB bank 0
 * $8003: CHR 2KB bank 1
 * $A000-$A003: CHR 1KB banks 0-3 at $1000-$1C00
 * $C000: mirror control (bit6: V/H)
 * $C001: IRQ latch
 * $C002: IRQ reset
 * $C003: IRQ enable
 */

typedef struct {
    uint8_t prg[2];
    uint8_t chr2[2];
    uint8_t chr1[4];
    uint8_t mirror;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_enabled;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper48_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper48_update_banks(nes_t* nes) {
    mapper48_t* m = (mapper48_t*)nes->nes_mapper.mapper_register;
    uint8_t last  = (uint8_t)(m->prg_bank_count - 1u);
    uint8_t slast = (uint8_t)(m->prg_bank_count - 2u);

    nes_load_prgrom_8k(nes, 0, m->prg[0] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % m->prg_bank_count);
    nes_load_prgrom_8k(nes, 2, slast);
    nes_load_prgrom_8k(nes, 3, last);

    if (m->chr_bank_count == 0u) return;
    nes_load_chrrom_1k(nes, 0, (uint8_t)((m->chr2[0] * 2u) % m->chr_bank_count));
    nes_load_chrrom_1k(nes, 1, (uint8_t)((m->chr2[0] * 2u + 1u) % m->chr_bank_count));
    nes_load_chrrom_1k(nes, 2, (uint8_t)((m->chr2[1] * 2u) % m->chr_bank_count));
    nes_load_chrrom_1k(nes, 3, (uint8_t)((m->chr2[1] * 2u + 1u) % m->chr_bank_count));
    for (uint8_t i = 0u; i < 4u; i++)
        nes_load_chrrom_1k(nes, (uint8_t)(4u + i), m->chr1[i] % m->chr_bank_count);

    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, (m->mirror & 0x40u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper48_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper48_t* m = (mapper48_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper48_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper48_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper48_t* m = (mapper48_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE003u) {
    case 0x8000u: m->prg[0]   = data & 0x3Fu; mapper48_update_banks(nes); break;
    case 0x8001u: m->prg[1]   = data & 0x3Fu; mapper48_update_banks(nes); break;
    case 0x8002u: m->chr2[0]  = data; mapper48_update_banks(nes); break;
    case 0x8003u: m->chr2[1]  = data; mapper48_update_banks(nes); break;
    case 0xA000u: m->chr1[0]  = data; mapper48_update_banks(nes); break;
    case 0xA001u: m->chr1[1]  = data; mapper48_update_banks(nes); break;
    case 0xA002u: m->chr1[2]  = data; mapper48_update_banks(nes); break;
    case 0xA003u: m->chr1[3]  = data; mapper48_update_banks(nes); break;
    case 0xC000u: m->mirror   = data; mapper48_update_banks(nes); break;
    case 0xC001u: m->irq_latch = data; break;
    case 0xC002u: m->irq_counter = m->irq_latch; nes->nes_cpu.irq_pending = 0; break;
    case 0xC003u: m->irq_enabled = 1; break;
    default: break;
    }
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper48_t* m = (mapper48_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enabled) return;
    if (m->irq_counter == 0xFFu) {
        m->irq_counter = m->irq_latch;
        m->irq_enabled = 0;
        nes_cpu_irq(nes);
    } else {
        m->irq_counter++;
    }
}

int nes_mapper48_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

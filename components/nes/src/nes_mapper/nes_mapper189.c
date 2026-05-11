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

/*
 * Mapper 189 - MMC3-based board with external PRG bank register.
 * Reference: FCEUX src/boards/189.cpp
 *
 * PRG: always 32KB, bank selected by expreg[2:0].
 *   expreg = data | (data >> 4), written to $4120-$7FFF.
 * CHR: standard MMC3 banking (R0-R5, 1KB/2KB pages).
 * IRQ: standard MMC3 scanline counter.
 * $8000-$FFFF: standard MMC3 registers (CHR bank, mirroring, IRQ) only;
 *   MMC3 PRG bank registers (R6/R7) are ignored — PRG comes from expreg.
 */

typedef struct {
    uint8_t  bank_select;
    uint8_t  bank_values[8];
    uint8_t  mirroring;
    uint8_t  prg_ram_protect;
    uint8_t  irq_latch;
    uint8_t  irq_counter;
    uint8_t  irq_reload;
    uint8_t  irq_enabled;
    uint16_t prg_bank_count;  /* number of 8KB PRG banks */
    uint16_t chr_bank_count;  /* number of 1KB CHR banks */
    uint8_t  expreg;          /* external PRG 32KB bank register */
} mapper189_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper189_update_banks(nes_t* nes) {
    mapper189_t* m = (mapper189_t*)nes->nes_mapper.mapper_register;

    /* PRG: always 32KB, expreg & 7 selects 32KB bank */
    uint16_t prg32_count = m->prg_bank_count / 4u;
    if (prg32_count == 0) prg32_count = 1;
    nes_load_prgrom_32k(nes, 0, (uint16_t)((m->expreg & 7u) % prg32_count));

    if (nes->nes_rom.chr_rom_size == 0) return;

    /* CHR: standard MMC3 */
    uint8_t chr_mode = (m->bank_select >> 7) & 1u;
    if (chr_mode == 0) {
        nes_load_chrrom_1k(nes, 0, (m->bank_values[0] & 0xFEu) % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 1, (m->bank_values[0] | 0x01u) % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 2, (m->bank_values[1] & 0xFEu) % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 3, (m->bank_values[1] | 0x01u) % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 4, m->bank_values[2] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 5, m->bank_values[3] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 6, m->bank_values[4] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 7, m->bank_values[5] % m->chr_bank_count);
    } else {
        nes_load_chrrom_1k(nes, 0, m->bank_values[2] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 1, m->bank_values[3] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 2, m->bank_values[4] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 3, m->bank_values[5] % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 4, (m->bank_values[0] & 0xFEu) % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 5, (m->bank_values[0] | 0x01u) % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 6, (m->bank_values[1] & 0xFEu) % m->chr_bank_count);
        nes_load_chrrom_1k(nes, 7, (m->bank_values[1] | 0x01u) % m->chr_bank_count);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper189_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper189_t* m = (mapper189_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper189_t));

    m->prg_bank_count = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);

    if (nes->nes_rom.chr_rom_size == 0)
        nes_load_chrrom_8k(nes, 0, 0);

    mapper189_update_banks(nes);
}

/* $8000-$FFFF: standard MMC3 CHR/mirroring/IRQ registers (PRG R6/R7 ignored) */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper189_t* m = (mapper189_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001u) {
    case 0x8000:
        m->bank_select = data;
        mapper189_update_banks(nes);
        break;
    case 0x8001:
        m->bank_values[m->bank_select & 0x07u] = data;
        mapper189_update_banks(nes);
        break;
    case 0xA000:
        m->mirroring = data & 1u;
        if (nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes, m->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        }
        break;
    case 0xA001:
        m->prg_ram_protect = data;
        break;
    case 0xC000:
        m->irq_latch = data;
        break;
    case 0xC001:
        m->irq_counter = 0;
        m->irq_reload = 1;
        break;
    case 0xE000:
        m->irq_enabled = 0;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0xE001:
        m->irq_enabled = 1;
        break;
    }
}

/* $4020-$5FFF: external PRG bank register (covers $4120-$5FFF part of $4120-$7FFF) */
static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    if (address < 0x4120u) return;
    mapper189_t* m = (mapper189_t*)nes->nes_mapper.mapper_register;
    m->expreg = data | (uint8_t)(data >> 4u);
    mapper189_update_banks(nes);
}

/* $6000-$7FFF: external PRG bank register (covers $6000-$7FFF part of $4120-$7FFF) */
static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    mapper189_t* m = (mapper189_t*)nes->nes_mapper.mapper_register;
    m->expreg = data | (uint8_t)(data >> 4u);
    mapper189_update_banks(nes);
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper189_t* m = (mapper189_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;

    if (m->irq_counter == 0 || m->irq_reload) {
        m->irq_counter = m->irq_latch;
        m->irq_reload = 0;
        /* reload to 0 does NOT fire IRQ */
    } else {
        m->irq_counter--;
        if (m->irq_counter == 0 && m->irq_enabled) {
            nes_cpu_irq(nes);
        }
    }
}

int nes_mapper189_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_045
 * Mapper 45 — Star Prolog/Yanchong (MMC3 + 4-register outer bank).
 * Sequential writes to $6000-$7FFF advance a 4-register FIFO:
 *   reg[0]: CHR outer low bits
 *   reg[1]: PRG outer base
 *   reg[2]: CHR mask / outer high bits
 *   reg[3]: PRG mask / register lock
 * Even $6000-$7FFE writes update the FIFO; odd writes clear the lock bit.
 */

typedef struct {
    uint8_t bank_select;
    uint8_t bank_values[8];
    uint8_t mirroring;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_reload;
    uint8_t irq_enabled;
    uint16_t prg_bank_count;
    uint16_t chr_bank_count;
    uint8_t regs[4];
    uint8_t latch_pos;
    uint8_t protect_index;
} mapper45_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static inline uint16_t mapper45_prg_bank(mapper45_t* m, uint16_t bank) {
    const uint16_t mask = (uint16_t)(0x3Fu ^ (m->regs[3] & 0x3Fu));
    uint16_t page = (uint16_t)((bank & mask) | m->regs[1]);
    return m->prg_bank_count ? (uint16_t)(page % m->prg_bank_count) : 0u;
}

static inline uint16_t mapper45_chr_bank(mapper45_t* m, uint16_t bank) {
    const uint8_t chr_mask_bits = (uint8_t)(m->regs[2] & 0x0Fu);
    const uint16_t chr_mask = (chr_mask_bits < 8u) ? 0u : (uint16_t)(0x00FFu >> (0x0Fu - chr_mask_bits));
    uint16_t page = (uint16_t)((bank & chr_mask) | m->regs[0] | ((uint16_t)(m->regs[2] & 0xF0u) << 4));
    return m->chr_bank_count ? (uint16_t)(page % m->chr_bank_count) : 0u;
}

static void mapper45_load_chrrom_1k(nes_t* nes, mapper45_t* m, uint8_t slot, uint16_t bank) {
    nes_load_chrrom_1k(nes, slot, mapper45_chr_bank(m, bank));
}

static void mapper45_update_banks(nes_t* nes) {
    mapper45_t* m = (mapper45_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_mode = (m->bank_select >> 6) & 1u;
    uint8_t chr_mode = (m->bank_select >> 7) & 1u;

    if (prg_mode == 0u) {
        nes_load_prgrom_8k(nes, 0, mapper45_prg_bank(m, m->bank_values[6]));
        nes_load_prgrom_8k(nes, 1, mapper45_prg_bank(m, m->bank_values[7]));
        nes_load_prgrom_8k(nes, 2, mapper45_prg_bank(m, 0x3Eu));
        nes_load_prgrom_8k(nes, 3, mapper45_prg_bank(m, 0x3Fu));
    } else {
        nes_load_prgrom_8k(nes, 0, mapper45_prg_bank(m, 0x3Eu));
        nes_load_prgrom_8k(nes, 1, mapper45_prg_bank(m, m->bank_values[7]));
        nes_load_prgrom_8k(nes, 2, mapper45_prg_bank(m, m->bank_values[6]));
        nes_load_prgrom_8k(nes, 3, mapper45_prg_bank(m, 0x3Fu));
    }

    if (m->chr_bank_count == 0u) return;

    if (chr_mode == 0u) {
        mapper45_load_chrrom_1k(nes, m, 0, m->bank_values[0] & 0xFEu);
        mapper45_load_chrrom_1k(nes, m, 1, m->bank_values[0] | 0x01u);
        mapper45_load_chrrom_1k(nes, m, 2, m->bank_values[1] & 0xFEu);
        mapper45_load_chrrom_1k(nes, m, 3, m->bank_values[1] | 0x01u);
        mapper45_load_chrrom_1k(nes, m, 4, m->bank_values[2]);
        mapper45_load_chrrom_1k(nes, m, 5, m->bank_values[3]);
        mapper45_load_chrrom_1k(nes, m, 6, m->bank_values[4]);
        mapper45_load_chrrom_1k(nes, m, 7, m->bank_values[5]);
    } else {
        mapper45_load_chrrom_1k(nes, m, 0, m->bank_values[2]);
        mapper45_load_chrrom_1k(nes, m, 1, m->bank_values[3]);
        mapper45_load_chrrom_1k(nes, m, 2, m->bank_values[4]);
        mapper45_load_chrrom_1k(nes, m, 3, m->bank_values[5]);
        mapper45_load_chrrom_1k(nes, m, 4, m->bank_values[0] & 0xFEu);
        mapper45_load_chrrom_1k(nes, m, 5, m->bank_values[0] | 0x01u);
        mapper45_load_chrrom_1k(nes, m, 6, m->bank_values[1] & 0xFEu);
        mapper45_load_chrrom_1k(nes, m, 7, m->bank_values[1] | 0x01u);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper45_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper45_t* m = (mapper45_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper45_t));

    m->prg_bank_count = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    m->bank_values[0] = 0;
    m->bank_values[1] = 2;
    m->bank_values[2] = 4;
    m->bank_values[3] = 5;
    m->bank_values[4] = 6;
    m->bank_values[5] = 7;
    m->bank_values[6] = 0;
    m->bank_values[7] = 1;
    m->regs[2] = 0x0Fu;

    if (nes->nes_rom.chr_rom_size == 0u) nes_load_chrrom_8k(nes, 0, 0);
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        } else {
            NES_LOG_ERROR("mapper45: failed to allocate WRAM\n");
        }
    }
    mapper45_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper45_t* m = (mapper45_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001u) {
    case 0x8000: m->bank_select = data; mapper45_update_banks(nes); break;
    case 0x8001: {
        uint8_t reg = m->bank_select & 0x07u;
        m->bank_values[reg] = data;
        mapper45_update_banks(nes);
        break;
    }
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

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper45_t* m = (mapper45_t*)nes->nes_mapper.mapper_register;
    (void)address;
    if ((m->regs[3] & 0x40u) == 0u) {
        m->regs[m->latch_pos & 3u] = data;
        m->latch_pos = (m->latch_pos + 1u) & 3u;
        mapper45_update_banks(nes);
    }
}

static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    mapper45_t* m = (mapper45_t*)nes->nes_mapper.mapper_register;
    if ((address & 0xF000u) == 0x5000u) {
        const uint16_t bit = (uint16_t)(1u << ((m->protect_index & 7u) + 4u));
        return (address & (uint16_t)(bit | (bit - 1u))) ? 1u : 0u;
    }
    return 0;
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper45_t* m = (mapper45_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (m->irq_counter == 0u || m->irq_reload) {
        m->irq_counter = m->irq_latch;
    } else {
        m->irq_counter--;
    }
    if (m->irq_counter == 0u && m->irq_enabled) nes_cpu_irq(nes);
    m->irq_reload = 0;
}

int nes_mapper45_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_read_apu = nes_mapper_read_apu;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

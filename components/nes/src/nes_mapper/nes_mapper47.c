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

/* https://www.nesdev.org/wiki/INES_Mapper_047
 * Mapper 47 — NES-QJ (Nintendo Super Spike V'Ball + Nintendo World Cup multicart).
 * MMC3 + 1-bit outer bank from SRAM writes at $6000-$7FFF.
 * bit[0]: selects which 128KB PRG / 128KB CHR half to use.
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
    uint8_t outer;
    uint8_t wram_enable;
    uint8_t wram_write_protect;
} mapper47_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper47_update_banks(nes_t* nes) {
    mapper47_t* m = (mapper47_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_mode = (m->bank_select >> 6) & 1u;
    uint8_t chr_mode = (m->bank_select >> 7) & 1u;
    uint16_t half_prg = m->prg_bank_count / 2u;
    uint16_t half_chr = m->chr_bank_count / 2u;
    if (half_prg == 0u) half_prg = 1u;
    if (half_chr == 0u) half_chr = 1u;
    uint16_t prg_off  = (uint16_t)((m->outer & 1u) * half_prg);
    uint16_t chr_off  = (uint16_t)((m->outer & 1u) * half_chr);
    uint16_t last  = prg_off + half_prg - 1u;
    uint16_t slast = prg_off + half_prg - 2u;

    if (prg_mode == 0u) {
        nes_load_prgrom_8k(nes, 0, prg_off + (m->bank_values[6] & 0x0Fu));
        nes_load_prgrom_8k(nes, 1, prg_off + (m->bank_values[7] & 0x0Fu));
        nes_load_prgrom_8k(nes, 2, slast);
        nes_load_prgrom_8k(nes, 3, last);
    } else {
        nes_load_prgrom_8k(nes, 0, slast);
        nes_load_prgrom_8k(nes, 1, prg_off + (m->bank_values[7] & 0x0Fu));
        nes_load_prgrom_8k(nes, 2, prg_off + (m->bank_values[6] & 0x0Fu));
        nes_load_prgrom_8k(nes, 3, last);
    }

    if (m->chr_bank_count == 0u) return;

    if (chr_mode == 0u) {
        nes_load_chrrom_1k(nes, 0, chr_off + (m->bank_values[0] & 0x7Eu));
        nes_load_chrrom_1k(nes, 1, chr_off + (m->bank_values[0] | 0x01u));
        nes_load_chrrom_1k(nes, 2, chr_off + (m->bank_values[1] & 0x7Eu));
        nes_load_chrrom_1k(nes, 3, chr_off + (m->bank_values[1] | 0x01u));
        nes_load_chrrom_1k(nes, 4, chr_off + (m->bank_values[2] & 0x7Fu));
        nes_load_chrrom_1k(nes, 5, chr_off + (m->bank_values[3] & 0x7Fu));
        nes_load_chrrom_1k(nes, 6, chr_off + (m->bank_values[4] & 0x7Fu));
        nes_load_chrrom_1k(nes, 7, chr_off + (m->bank_values[5] & 0x7Fu));
    } else {
        nes_load_chrrom_1k(nes, 0, chr_off + (m->bank_values[2] & 0x7Fu));
        nes_load_chrrom_1k(nes, 1, chr_off + (m->bank_values[3] & 0x7Fu));
        nes_load_chrrom_1k(nes, 2, chr_off + (m->bank_values[4] & 0x7Fu));
        nes_load_chrrom_1k(nes, 3, chr_off + (m->bank_values[5] & 0x7Fu));
        nes_load_chrrom_1k(nes, 4, chr_off + (m->bank_values[0] & 0x7Eu));
        nes_load_chrrom_1k(nes, 5, chr_off + (m->bank_values[0] | 0x01u));
        nes_load_chrrom_1k(nes, 6, chr_off + (m->bank_values[1] & 0x7Eu));
        nes_load_chrrom_1k(nes, 7, chr_off + (m->bank_values[1] | 0x01u));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper47_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper47_t* m = (mapper47_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper47_t));

    m->prg_bank_count = (uint16_t)nes->nes_rom.prg_rom_size * 2u;
    m->chr_bank_count = (uint16_t)nes->nes_rom.chr_rom_size * 8u;
    m->bank_values[6] = 0;
    m->bank_values[7] = 1;

    if (nes->nes_rom.chr_rom_size == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper47_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper47_t* m = (mapper47_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001u) {
    case 0x8000: m->bank_select = data; mapper47_update_banks(nes); break;
    case 0x8001: {
        uint8_t reg = m->bank_select & 0x07u;
        m->bank_values[reg] = data;
        mapper47_update_banks(nes);
        break;
    }
    case 0xA000:
        m->mirroring = data & 1u;
        if (nes->nes_rom.four_screen == 0)
            nes_ppu_screen_mirrors(nes, m->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        break;
    case 0xA001:
        m->wram_enable = (data & 0x80u) ? 1u : 0u;
        m->wram_write_protect = (data & 0x40u) ? 1u : 0u;
        break;
    case 0xC000: m->irq_latch   = data; break;
    case 0xC001: m->irq_reload  = 1; break;
    case 0xE000: m->irq_enabled = 0; nes->nes_cpu.irq_pending = 0; break;
    case 0xE001: m->irq_enabled = 1; break;
    default: break;
    }
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper47_t* m = (mapper47_t*)nes->nes_mapper.mapper_register;
    (void)address;
    if (m->wram_enable && !m->wram_write_protect) {
        m->outer = data & 0x01u;
        mapper47_update_banks(nes);
    }
}

static uint8_t nes_mapper_read_sram(nes_t* nes, uint16_t address) {
    mapper47_t* m = (mapper47_t*)nes->nes_mapper.mapper_register;
    (void)address;
    return m->outer;
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper47_t* m = (mapper47_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (m->irq_counter == 0u || m->irq_reload) {
        m->irq_counter = m->irq_latch;
    } else {
        m->irq_counter--;
    }
    if (m->irq_counter == 0u && m->irq_enabled) nes_cpu_irq(nes);
    m->irq_reload = 0;
}

int nes_mapper47_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_read_sram = nes_mapper_read_sram;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

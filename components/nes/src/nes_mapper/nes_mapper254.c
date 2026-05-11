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

/* https://www.nesdev.org/wiki/INES_Mapper_254
 * Mapper 254 — pirate MMC3 variant with CHR-RAM.
 * Like MMC3 but uses CHR-RAM only, with a security register at $6001 that
 * affects game boot. Security: first read to $6000 returns XOR'd value.
 * Simplified: treat as standard MMC3 with CHR-RAM.
 */

typedef struct {
    uint8_t bank_select;
    uint8_t bank_values[8];
    uint8_t mirroring;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_reload;
    uint8_t irq_enabled;
    uint8_t prg_bank_count;
    uint8_t security_reg;
    uint8_t chr_ram[8192];
} mapper254_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper254_update_banks(nes_t* nes) {
    mapper254_t* m = (mapper254_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_mode = (m->bank_select >> 6) & 1u;
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

    /* CHR-RAM: 8 × 1KB pages within 8KB buffer */
    uint8_t chr_mode = (m->bank_select >> 7) & 1u;
    if (chr_mode == 0u) {
        nes->nes_ppu.pattern_table[0] = m->chr_ram + (m->bank_values[0] & 0xFEu & 0x07u) * 1024u;
        nes->nes_ppu.pattern_table[1] = m->chr_ram + (m->bank_values[0] | 0x01u  & 0x07u) * 1024u;
        nes->nes_ppu.pattern_table[2] = m->chr_ram + (m->bank_values[1] & 0xFEu & 0x07u) * 1024u;
        nes->nes_ppu.pattern_table[3] = m->chr_ram + (m->bank_values[1] | 0x01u  & 0x07u) * 1024u;
        for (int i = 0; i < 4; i++)
            nes->nes_ppu.pattern_table[4 + i] = m->chr_ram + (m->bank_values[2 + i] & 0x07u) * 1024u;
    } else {
        for (int i = 0; i < 4; i++)
            nes->nes_ppu.pattern_table[i] = m->chr_ram + (m->bank_values[2 + i] & 0x07u) * 1024u;
        nes->nes_ppu.pattern_table[4] = m->chr_ram + (m->bank_values[0] & 0xFEu & 0x07u) * 1024u;
        nes->nes_ppu.pattern_table[5] = m->chr_ram + (m->bank_values[0] | 0x01u  & 0x07u) * 1024u;
        nes->nes_ppu.pattern_table[6] = m->chr_ram + (m->bank_values[1] & 0xFEu & 0x07u) * 1024u;
        nes->nes_ppu.pattern_table[7] = m->chr_ram + (m->bank_values[1] | 0x01u  & 0x07u) * 1024u;
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper254_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper254_t* m = (mapper254_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper254_t));

    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->bank_values[6] = 0;
    m->bank_values[7] = 1;
    mapper254_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper254_t* m = (mapper254_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001u) {
    case 0x8000: m->bank_select = data; mapper254_update_banks(nes); break;
    case 0x8001: {
        uint8_t reg = m->bank_select & 0x07u;
        m->bank_values[reg] = data;
        mapper254_update_banks(nes);
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
    mapper254_t* m = (mapper254_t*)nes->nes_mapper.mapper_register;
    if (address == 0x6001u) m->security_reg = data;
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper254_t* m = (mapper254_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (m->irq_counter == 0u || m->irq_reload) {
        m->irq_counter = m->irq_latch;
    } else {
        m->irq_counter--;
    }
    if (m->irq_counter == 0u && m->irq_enabled) nes_cpu_irq(nes);
    m->irq_reload = 0;
}

int nes_mapper254_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

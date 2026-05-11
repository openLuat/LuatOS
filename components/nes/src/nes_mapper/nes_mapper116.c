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

/* https://www.nesdev.org/wiki/INES_Mapper_116
 * Mapper 116 — SOMARI-P (Huang Di / Somari pirate).
 * Hybrid: mode bit selects between VRC2, MMC1, and MMC3 submodes.
 * For MCU: implement simplified mode 1 (MMC3-like default).
 * Mode stored in outer register at $8000/$A000 bit7.
 */

typedef struct {
    uint8_t mode;
    /* MMC3 state */
    uint8_t bank_select;
    uint8_t bank_values[8];
    uint8_t mirroring;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_reload;
    uint8_t irq_enabled;
    /* MMC1 state */
    uint8_t mmc1_shift;
    uint8_t mmc1_count;
    uint8_t mmc1_regs[4];
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper116_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper116_update_mmc3(nes_t* nes) {
    mapper116_t* m = (mapper116_t*)nes->nes_mapper.mapper_register;
    uint8_t prg8 = m->prg_bank_count;
    if (prg8 == 0u) prg8 = 1u;
    uint8_t chr = m->chr_bank_count;
    if (chr == 0u) chr = 1u;

    uint8_t prg_mode = (m->bank_select >> 6u) & 0x01u;
    if (prg_mode == 0u) {
        nes_load_prgrom_8k(nes, 0, m->bank_values[6] % prg8);
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % prg8);
        nes_load_prgrom_8k(nes, 2, (uint8_t)((prg8 - 2u) % prg8));
        nes_load_prgrom_8k(nes, 3, (uint8_t)((prg8 - 1u) % prg8));
    } else {
        nes_load_prgrom_8k(nes, 0, (uint8_t)((prg8 - 2u) % prg8));
        nes_load_prgrom_8k(nes, 1, m->bank_values[7] % prg8);
        nes_load_prgrom_8k(nes, 2, m->bank_values[6] % prg8);
        nes_load_prgrom_8k(nes, 3, (uint8_t)((prg8 - 1u) % prg8));
    }
    uint8_t chr_mode = (m->bank_select >> 7u) & 0x01u;
    uint8_t* bv = m->bank_values;
    if (chr_mode == 0u) {
        nes_load_chrrom_1k(nes, 0, (uint8_t)((bv[0] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 1, (uint8_t)((bv[0] | 0x01u) % chr));
        nes_load_chrrom_1k(nes, 2, (uint8_t)((bv[1] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 3, (uint8_t)((bv[1] | 0x01u) % chr));
        nes_load_chrrom_1k(nes, 4, bv[2] % chr);
        nes_load_chrrom_1k(nes, 5, bv[3] % chr);
        nes_load_chrrom_1k(nes, 6, bv[4] % chr);
        nes_load_chrrom_1k(nes, 7, bv[5] % chr);
    } else {
        nes_load_chrrom_1k(nes, 0, bv[2] % chr);
        nes_load_chrrom_1k(nes, 1, bv[3] % chr);
        nes_load_chrrom_1k(nes, 2, bv[4] % chr);
        nes_load_chrrom_1k(nes, 3, bv[5] % chr);
        nes_load_chrrom_1k(nes, 4, (uint8_t)((bv[0] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 5, (uint8_t)((bv[0] | 0x01u) % chr));
        nes_load_chrrom_1k(nes, 6, (uint8_t)((bv[1] & 0xFEu) % chr));
        nes_load_chrrom_1k(nes, 7, (uint8_t)((bv[1] | 0x01u) % chr));
    }
    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, m->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper116_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper116_t* m = (mapper116_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper116_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    m->mode = 1u;  /* start in MMC3 mode */
    mapper116_update_mmc3(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper116_t* m = (mapper116_t*)nes->nes_mapper.mapper_register;
    /* mode select via bit7 of certain writes */
    if (data & 0x80u) m->mode = (data >> 5u) & 0x03u;

    if (m->mode == 1u) {
        /* MMC3 */
        switch (address & 0xE001u) {
        case 0x8000u: m->bank_select = data; mapper116_update_mmc3(nes); break;
        case 0x8001u:
            if ((m->bank_select & 0x07u) < 8u)
                m->bank_values[m->bank_select & 0x07u] = data;
            mapper116_update_mmc3(nes);
            break;
        case 0xA000u: m->mirroring = data & 0x01u; mapper116_update_mmc3(nes); break;
        case 0xC000u: m->irq_latch   = data; break;
        case 0xC001u: m->irq_reload  = 1u; break;
        case 0xE000u: m->irq_enabled = 0u; nes->nes_cpu.irq_pending = 0u; break;
        case 0xE001u: m->irq_enabled = 1u; break;
        default: break;
        }
    } else {
        /* For modes 0/2/3 (VRC2/MMC1 variants): fall back to simplified PRG 32K */
        nes_load_prgrom_32k(nes, 0, 0);
    }
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper116_t* m = (mapper116_t*)nes->nes_mapper.mapper_register;
    if (m->mode != 1u) return;
    if (m->irq_reload || m->irq_counter == 0u) {
        m->irq_counter = m->irq_latch;
        m->irq_reload  = 0u;
    } else {
        m->irq_counter--;
    }
    if (m->irq_counter == 0u && m->irq_enabled)
        nes_cpu_irq(nes);
}

int nes_mapper116_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

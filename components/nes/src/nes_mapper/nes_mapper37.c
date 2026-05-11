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

/* https://www.nesdev.org/wiki/INES_Mapper_037
 * Mapper 37 — PAL-ZZ board: Super Mario Bros./Tetris/Nintendo World Cup multicart.
 * Outer register at $6000-$7FFF (gated by $A001 wram_enable):
 *   bits[2:0] = exreg
 * PRG formula (BizHawk Mapper037):
 *   prg_base = (exreg<<2 & 0x10) | ((exreg&3)==3 ? 8 : 0)
 *   prg_mask = (exreg<<1) | 7
 *   inner_bank = prg_base | (mmc3_inner_bank & prg_mask)
 * CHR formula:
 *   chr_bank = mmc3_inner_chr | (exreg<<5 & 0x80)
 */

typedef struct {
    uint8_t bank_select;
    uint8_t bank_values[8];
    uint8_t mirroring;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_reload;
    uint8_t irq_enabled;
    uint8_t outer;        /* exreg bits[2:0] */
    uint8_t wram_enable;  /* $A001 bit7 */
} mapper37_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper37_update_banks(nes_t* nes) {
    mapper37_t* m = (mapper37_t*)nes->nes_mapper.mapper_register;
    uint8_t ex = m->outer;
    uint8_t prg_mode = (m->bank_select >> 6) & 1u;
    uint8_t chr_mode = (m->bank_select >> 7) & 1u;

    /*
     * PRG bank formula (BizHawk Mapper037):
     *   prg_base = (exreg<<2 & 0x10) | ((exreg&3)==3 ? 8 : 0)
     *   prg_mask = (exreg<<1) | 7
     *   effective_bank = prg_base | (inner_bank & prg_mask)
     *
     * exreg 0,1,2: base=0,  mask=7  → inner&7 → banks 0-7   (first 64KB)
     * exreg 3:     base=8,  mask=7  → 8|(inner&7) → banks 8-15 (second 64KB)
     * exreg 4,5,6: base=16, mask=15 → 16|(inner&15) → banks 16-31 (second 128KB)
     * exreg 7:     base=24, mask=15 → 24|(inner&15) → banks 24-31 (last 64KB)
     */
    uint8_t prg_base = (uint8_t)(((uint8_t)(ex << 2u) & 0x10u) | ((ex & 3u) == 3u ? 8u : 0u));
    uint8_t prg_mask = (uint8_t)((ex << 1u) | 7u);

    uint16_t total_prg = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    uint8_t last  = (uint8_t)(total_prg - 1u);
    uint8_t slast = (uint8_t)(total_prg - 2u);

    if (prg_mode == 0u) {
        nes_load_prgrom_8k(nes, 0, (uint8_t)(prg_base | (m->bank_values[6] & prg_mask)));
        nes_load_prgrom_8k(nes, 1, (uint8_t)(prg_base | (m->bank_values[7] & prg_mask)));
        nes_load_prgrom_8k(nes, 2, (uint8_t)(prg_base | (slast & prg_mask)));
        nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_base | (last  & prg_mask)));
    } else {
        nes_load_prgrom_8k(nes, 0, (uint8_t)(prg_base | (slast & prg_mask)));
        nes_load_prgrom_8k(nes, 1, (uint8_t)(prg_base | (m->bank_values[7] & prg_mask)));
        nes_load_prgrom_8k(nes, 2, (uint8_t)(prg_base | (m->bank_values[6] & prg_mask)));
        nes_load_prgrom_8k(nes, 3, (uint8_t)(prg_base | (last  & prg_mask)));
    }

    if (nes->nes_rom.chr_rom_size == 0u) return;

    /*
     * CHR bank formula (BizHawk):
     *   effective_chr = inner_chr_bank | (exreg<<5 & 0x80)
     * exreg bit2=0: CHR banks 0-127 (first 128KB)
     * exreg bit2=1: CHR banks 128-255 (second 128KB)
     */
    uint16_t chr_hi = (uint16_t)((uint8_t)(ex << 5u) & 0x80u);

    if (chr_mode == 0u) {
        nes_load_chrrom_1k(nes, 0, chr_hi | (m->bank_values[0] & 0xFEu));
        nes_load_chrrom_1k(nes, 1, chr_hi | (m->bank_values[0] | 0x01u));
        nes_load_chrrom_1k(nes, 2, chr_hi | (m->bank_values[1] & 0xFEu));
        nes_load_chrrom_1k(nes, 3, chr_hi | (m->bank_values[1] | 0x01u));
        nes_load_chrrom_1k(nes, 4, chr_hi | m->bank_values[2]);
        nes_load_chrrom_1k(nes, 5, chr_hi | m->bank_values[3]);
        nes_load_chrrom_1k(nes, 6, chr_hi | m->bank_values[4]);
        nes_load_chrrom_1k(nes, 7, chr_hi | m->bank_values[5]);
    } else {
        nes_load_chrrom_1k(nes, 0, chr_hi | m->bank_values[2]);
        nes_load_chrrom_1k(nes, 1, chr_hi | m->bank_values[3]);
        nes_load_chrrom_1k(nes, 2, chr_hi | m->bank_values[4]);
        nes_load_chrrom_1k(nes, 3, chr_hi | m->bank_values[5]);
        nes_load_chrrom_1k(nes, 4, chr_hi | (m->bank_values[0] & 0xFEu));
        nes_load_chrrom_1k(nes, 5, chr_hi | (m->bank_values[0] | 0x01u));
        nes_load_chrrom_1k(nes, 6, chr_hi | (m->bank_values[1] & 0xFEu));
        nes_load_chrrom_1k(nes, 7, chr_hi | (m->bank_values[1] | 0x01u));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper37_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper37_t* m = (mapper37_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper37_t));

    m->bank_values[6] = 0;
    m->bank_values[7] = 1;

    if (nes->nes_rom.chr_rom_size == 0u) nes_load_chrrom_8k(nes, 0, 0);
    mapper37_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper37_t* m = (mapper37_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001u) {
    case 0x8000: m->bank_select = data; mapper37_update_banks(nes); break;
    case 0x8001: {
        uint8_t reg = m->bank_select & 0x07u;
        m->bank_values[reg] = data;
        mapper37_update_banks(nes);
        break;
    }
    case 0xA000:
        m->mirroring = data & 1u;
        if (nes->nes_rom.four_screen == 0)
            nes_ppu_screen_mirrors(nes, m->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        break;
    case 0xA001:
        m->wram_enable = (data & 0x80u) ? 1u : 0u;
        break;
    case 0xC000: m->irq_latch   = data; break;
    case 0xC001: m->irq_reload  = 1; break;
    case 0xE000: m->irq_enabled = 0; nes->nes_cpu.irq_pending = 0; break;
    case 0xE001: m->irq_enabled = 1; break;
    default: break;
    }
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper37_t* m = (mapper37_t*)nes->nes_mapper.mapper_register;
    (void)address;
    if (!m->wram_enable) return;
    m->outer = data & 0x07u;
    mapper37_update_banks(nes);
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper37_t* m = (mapper37_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;
    if (m->irq_counter == 0u || m->irq_reload) {
        m->irq_reload  = 0;
        m->irq_counter = m->irq_latch;
    } else {
        m->irq_counter--;
    }
    if (m->irq_counter == 0u && m->irq_enabled) nes_cpu_irq(nes);
}

int nes_mapper37_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

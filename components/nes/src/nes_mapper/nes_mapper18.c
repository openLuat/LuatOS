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

/* https://www.nesdev.org/wiki/INES_Mapper_018 */

typedef struct {
    uint8_t  prg[3];        /* 8KB PRG bank indices for $8000/$A000/$C000 */
    uint8_t  chr[8];        /* 1KB CHR bank indices */
    uint8_t  irq_enable;
    uint16_t irq_counter;   /* Live CPU-cycle down-counter */
    uint16_t irq_latch;     /* Reloaded by $F000 */
    uint16_t irq_mask;      /* Counter width selected by $F001 */
} nes_mapper18_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper18_update_prg(nes_t* nes) {
    nes_mapper18_t* m = (nes_mapper18_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_8k(nes, 0, m->prg[0] % prg_count);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % prg_count);
    nes_load_prgrom_8k(nes, 2, m->prg[2] % prg_count);
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_count - 1)); /* fixed last 8KB */
}

static void mapper18_update_chr(nes_t* nes) {
    nes_mapper18_t* m = (nes_mapper18_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_rom.chr_rom_size == 0) return;
    uint8_t chr_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8);
    for (int i = 0; i < 8; i++) {
        nes_load_chrrom_1k(nes, (uint8_t)i, m->chr[i] % chr_count);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper18_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper18_t* m = (nes_mapper18_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(nes_mapper18_t));

    m->prg[0] = 0; m->prg[1] = 1; m->prg[2] = 2;
    m->irq_mask = 0xFFFFu;
    for (int i = 0; i < 8; i++) m->chr[i] = (uint8_t)i;

    if (nes->nes_rom.save_ram && nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        } else {
            NES_LOG_ERROR("mapper18: failed to allocate SRAM\n");
        }
    }

    mapper18_update_prg(nes);
    mapper18_update_chr(nes);

    if (nes->nes_rom.mirroring_type) {
        nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);
    } else {
        nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);
    }
}

static void mapper18_reload_irq(nes_t* nes) {
    nes_mapper18_t* m = (nes_mapper18_t*)nes->nes_mapper.mapper_register;
    nes->nes_cpu.irq_pending = 0;
    m->irq_counter = m->irq_latch;
}

/*
 * Each register is 8-bits wide but written in two 4-bit nibble writes.
 * Address bit[0] selects low (0) or high (1) nibble; bits[3:1] select sub-reg.
 *
 * $8000/$8001: 8KB PRG bank at $8000 (prg[0])
 * $8002/$8003: 8KB PRG bank at $A000 (prg[1])
 * $9000/$9001: 8KB PRG bank at $C000 (prg[2])
 * $9002/$9003: reserved
 * $A000-$D003: 1KB CHR banks 0-7 (two nibble-writes per CHR register)
 * $E000/$E001: IRQ latch bits [7:0]  (low/high nibble)
 * $E002/$E003: IRQ latch bits [15:8] (low/high nibble)
 * $F000:       IRQ acknowledge and reload counter from latch
 * $F001:       IRQ control (bit0 enable, bits1-3 select counter width)
 * $F002:       Mirroring (0=H, 1=V, 2=single0, 3=single1)
 * $F003:       External sound command (ignored)
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper18_t* m = (nes_mapper18_t*)nes->nes_mapper.mapper_register;
    uint8_t nibble_sel = address & 1u;  /* 0=low nibble, 1=high nibble */

    switch (address & 0xF000) {
    case 0x8000: {
        /* $8000/$8001: prg[0],  $8002/$8003: prg[1] */
        uint8_t idx = (address >> 1) & 1u;
        if (!nibble_sel)
            m->prg[idx] = (uint8_t)((m->prg[idx] & 0xF0u) | (data & 0x0Fu));
        else
            m->prg[idx] = (uint8_t)((m->prg[idx] & 0x0Fu) | ((data & 0x0Fu) << 4));
        mapper18_update_prg(nes);
        break;
    }
    case 0x9000:
        /* $9000/$9001: prg[2];  $9002/$9003: reserved */
        if ((address & 0x3u) <= 1u) {
            if (!nibble_sel)
                m->prg[2] = (uint8_t)((m->prg[2] & 0xF0u) | (data & 0x0Fu));
            else
                m->prg[2] = (uint8_t)((m->prg[2] & 0x0Fu) | ((data & 0x0Fu) << 4));
            mapper18_update_prg(nes);
        }
        break;
    case 0xA000: case 0xB000: case 0xC000: case 0xD000: {
        /*
         * Each 0x1000-aligned block covers 2 CHR banks, each bank taking 2 nibble writes.
         * chr_idx = ((address - 0xA000) >> 11) | ((address >> 1) & 1)
         */
        uint8_t chr_idx = (uint8_t)(((address - 0xA000u) >> 11) | ((address >> 1) & 1u));
        if (!nibble_sel)
            m->chr[chr_idx] = (uint8_t)((m->chr[chr_idx] & 0xF0u) | (data & 0x0Fu));
        else
            m->chr[chr_idx] = (uint8_t)((m->chr[chr_idx] & 0x0Fu) | ((data & 0x0Fu) << 4));
        mapper18_update_chr(nes);
        break;
    }
    case 0xE000: {
        /* IRQ latch nibble writes:
         * $E000: bits[3:0],  $E001: bits[7:4],  $E002: bits[11:8],  $E003: bits[15:12] */
        uint8_t shift = (uint8_t)((address & 0x3u) * 4u);
        uint16_t mask = (uint16_t)(~(0x000Fu << shift));
        m->irq_latch = (uint16_t)((m->irq_latch & mask) | ((uint16_t)(data & 0x0Fu) << shift));
        break;
    }
    case 0xF000:
        switch (address & 0x3u) {
        case 0:
            (void)data;
            mapper18_reload_irq(nes);
            break;
        case 1:
            nes->nes_cpu.irq_pending = 0;
            if (data & 0x08u) {
                m->irq_mask = 0x000Fu;
            } else if (data & 0x04u) {
                m->irq_mask = 0x00FFu;
            } else if (data & 0x02u) {
                m->irq_mask = 0x0FFFu;
            } else {
                m->irq_mask = 0xFFFFu;
            }
            m->irq_enable = data & 0x01u;
            break;
        case 2:
            switch (data & 0x3u) {
            case 0: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
            case 1: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
            case 2: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
            case 3: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
            }
            break;
        case 3:
            break;
        }
        break;
    default:
        break;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    nes_mapper18_t* m = (nes_mapper18_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable || cycles == 0) {
        return;
    }

    uint16_t masked = m->irq_counter & m->irq_mask;
    if (masked == 0) {
        return;
    }

    if (cycles >= masked) {
        m->irq_counter = (uint16_t)(m->irq_counter - masked);
        nes_cpu_irq(nes);
    } else {
        m->irq_counter = (uint16_t)(m->irq_counter - cycles);
    }
}

int nes_mapper18_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

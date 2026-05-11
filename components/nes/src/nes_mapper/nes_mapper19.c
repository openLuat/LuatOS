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
 * https://www.nesdev.org/wiki/Namco_163_audio
 * Namco 129/163 — bank switching + IRQ only (no audio expansion).
 */

typedef struct {
    uint8_t  prg[3];        /* 8KB PRG bank indices for $8000/$A000/$C000 */
    uint8_t  chr[8];        /* 1KB CHR bank indices for PPU $0000-$1FFF */
    uint8_t  nta[4];        /* 1KB nametable bank indices for PPU $2000-$2FFF */
    uint8_t  chr_ram_enable;/* $E800 bits 6/7: allow internal NT-RAM as CHR per 4KB half */
    uint8_t  sound_addr;
    uint8_t  iram[0x80];
    uint8_t  irq_enable;
    uint16_t irq_counter;   /* 15-bit up-counter; fires at 0x7FFF */
} nes_mapper19_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper19_update_prg(nes_t* nes) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2);
    nes_load_prgrom_8k(nes, 0, m->prg[0] % prg_count);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % prg_count);
    nes_load_prgrom_8k(nes, 2, m->prg[2] % prg_count);
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_count - 1)); /* fixed last 8KB */
}

static void mapper19_load_chr_bank(nes_t* nes, uint8_t slot, uint8_t bank) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    if (bank >= 0xE0u && ((m->chr_ram_enable >> (slot >> 2)) & 0x01u) == 0u) {
        nes->nes_ppu.pattern_table[slot] = nes->nes_ppu.ppu_vram[bank & 0x01u];
    } else if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_1k(nes, slot, bank);
    }
}

static void mapper19_update_chr(nes_t* nes) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    for (uint8_t i = 0; i < 8; i++) {
        mapper19_load_chr_bank(nes, i, m->chr[i]);
    }
}

static void mapper19_load_nt_bank(nes_t* nes, uint8_t slot, uint8_t bank) {
    if (bank >= 0xE0u || nes->nes_rom.chr_rom_size == 0) {
        nes->nes_ppu.name_table[slot] = nes->nes_ppu.ppu_vram[bank & 0x01u];
    } else {
        uint16_t chr_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
        nes->nes_ppu.name_table[slot] = nes->nes_rom.chr_rom + (uint32_t)1024u * (bank % chr_count);
    }
    nes->nes_ppu.name_table_mirrors[slot] = nes->nes_ppu.name_table[slot];
}

static void mapper19_update_nt(nes_t* nes) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    for (uint8_t i = 0; i < 4; i++) {
        mapper19_load_nt_bank(nes, i, m->nta[i]);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper19_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(nes_mapper19_t));

    m->prg[0] = 0; m->prg[1] = 1; m->prg[2] = 2;
    for (int i = 0; i < 8; i++) m->chr[i] = (uint8_t)i;

    // Initialize NT banks based on ROM header mirroring.
    // Real hardware power-on state is undefined, but games that never write
    // to $C000-$DFFF rely on the initial state matching their expected mirroring.
    if (nes->nes_rom.mirroring_type) {
        // Vertical mirroring (horizontal arrangement / horizontal scrolling):
        // NT0 and NT2 → ppu_vram[0]; NT1 and NT3 → ppu_vram[1]
        m->nta[0] = 0xE0u; m->nta[1] = 0xE1u;
        m->nta[2] = 0xE0u; m->nta[3] = 0xE1u;
    } else {
        // Horizontal mirroring (vertical arrangement / vertical scrolling):
        // NT0 and NT1 → ppu_vram[0]; NT2 and NT3 → ppu_vram[1]
        m->nta[0] = 0xE0u; m->nta[1] = 0xE0u;
        m->nta[2] = 0xE1u; m->nta[3] = 0xE1u;
    }

    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        } else {
            NES_LOG_ERROR("mapper19: failed to allocate SRAM\n");
        }
    }

    mapper19_update_prg(nes);
    mapper19_update_chr(nes);
    mapper19_update_nt(nes);
}

/*
 * $8000-$BFFF: CHR 1KB banks 0-7 at PPU $0000-$1FFF
 *   Slot = (address - $8000) >> 11  (one slot per 0x800 bytes)
 * $C000-$DFFF: nametable banks 0-3 at PPU $2000-$2FFF
 * $E000-$E7FF: 8KB PRG bank at $8000 (bits[5:0])
 * $E800-$EFFF: 8KB PRG bank at $A000 (bits[5:0]), CHR-RAM enable (bits[7:6])
 * $F000-$F7FF: 8KB PRG bank at $C000 (bits[5:0])
 * $F800-$FFFF: internal audio RAM address (audio output not emulated)
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    uint16_t reg = address & 0xF800u;

    if (reg >= 0x8000u && reg <= 0xB800u) {
        uint8_t slot = (uint8_t)((reg - 0x8000u) >> 11);
        m->chr[slot] = data;
        mapper19_load_chr_bank(nes, slot, data);
        return;
    }

    switch (reg) {
    case 0xC000: case 0xC800: case 0xD000: case 0xD800: {
        uint8_t slot = (uint8_t)((reg - 0xC000u) >> 11);
        m->nta[slot] = data;
        mapper19_load_nt_bank(nes, slot, data);
        break;
    }
    case 0xE000:
        m->prg[0] = data & 0x3Fu;
        mapper19_update_prg(nes);
        break;
    case 0xE800:
        m->prg[1] = data & 0x3Fu;
        m->chr_ram_enable = data >> 6;
        mapper19_update_prg(nes);
        mapper19_update_chr(nes);
        break;
    case 0xF000:
        m->prg[2] = data & 0x3Fu;
        mapper19_update_prg(nes);
        break;
    case 0xF800:
        m->sound_addr = data;
        break;
    default:
        break;
    }
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF800u) {
    case 0x4800:
        m->iram[m->sound_addr & 0x7Fu] = data;
        if (m->sound_addr & 0x80u) {
            m->sound_addr = (uint8_t)((m->sound_addr & 0x80u) | ((m->sound_addr + 1u) & 0x7Fu));
        }
        break;
    case 0x5000:
        m->irq_counter = (uint16_t)((m->irq_counter & 0x7F00u) | data);
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0x5800:
        m->irq_counter = (uint16_t)((m->irq_counter & 0x00FFu) | ((uint16_t)(data & 0x7Fu) << 8));
        m->irq_enable = data & 0x80u;
        nes->nes_cpu.irq_pending = 0;
        break;
    default:
        break;
    }
}

static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF800u) {
    case 0x4800: {
        uint8_t data = m->iram[m->sound_addr & 0x7Fu];
        if (m->sound_addr & 0x80u) {
            m->sound_addr = (uint8_t)((m->sound_addr & 0x80u) | ((m->sound_addr + 1u) & 0x7Fu));
        }
        return data;
    }
    case 0x5000:
        return (uint8_t)m->irq_counter;
    case 0x5800:
        return (uint8_t)((m->irq_counter >> 8) | m->irq_enable);
    default:
        return 0;
    }
}

/*
 * 15-bit up-counter increments every CPU cycle.
 * Fires IRQ and resets when it reaches 0x7FFF.
 */
static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    nes_mapper19_t* m = (nes_mapper19_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable) return;
    if ((uint16_t)(0x7FFFu - (m->irq_counter & 0x7FFFu)) <= cycles) {
        m->irq_counter = 0x7FFFu;
        m->irq_enable = 0;
        nes_cpu_irq(nes);
    } else {
        m->irq_counter = (uint16_t)((m->irq_counter + cycles) & 0x7FFFu);
    }
}

int nes_mapper19_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_apu       = nes_mapper_apu;
    nes->nes_mapper.mapper_read_apu  = nes_mapper_read_apu;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

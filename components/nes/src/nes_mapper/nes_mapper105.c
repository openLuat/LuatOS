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

/* https://www.nesdev.org/wiki/INES_Mapper_105
 * Mapper 105 — NES-EVENT (Nintendo World Championships 1990).
 * Based on MMC1 with an additional DIP-switch counter IRQ.
 *
 * Key differences from plain MMC1:
 *   reg[1] ($A000-$BFFF):
 *     bit 4 : IRQ enable (0=enable, 1=disable/reset counter)
 *     bit 3 : mode (0=outer 32KB bank via bits1-2; 1=MMC1 16KB inner bank)
 *     bits1-2: outer 32KB bank select (mode=0)
 *   reg[3] ($E000-$FFFF): inner PRG bank (low 3 bits); bit 3 forced to 1
 *
 * init_state machine (required for the board to activate):
 *   0 → 1 : reg[1] bit4 goes LOW
 *   1 → 2 : reg[1] bit4 goes HIGH
 *   Only state 2 enables full PRG bank switching; states 0/1 map to 32KB bank 0.
 */

typedef struct {
    uint8_t shift;
    uint8_t shift_count;
    uint8_t regs[4];
    uint32_t irq_counter;
    uint8_t irq_enabled;
    uint8_t init_state;     /* 0/1/2 init sequence; see comment above */
    uint16_t prg16_count;   /* number of 16KB PRG banks */
} mapper105_t;

/* IRQ fires when counter reaches 0x20000000 (DIP=0); ~596 seconds @ 1.79 MHz */
#define MAPPER105_IRQ_PERIOD (0x20000000u)

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
    if (nes->nes_rom.sram) {
        nes_free(nes->nes_rom.sram);
        nes->nes_rom.sram = NULL;
    }
}

static void mapper105_update_banks(nes_t* nes) {
    mapper105_t* m = (mapper105_t*)nes->nes_mapper.mapper_register;

    /* --- init state machine: driven by bit 4 of reg[1] --- */
    if (m->init_state == 0u && !(m->regs[1] & 0x10u)) {
        m->init_state = 1u;
    } else if (m->init_state == 1u && (m->regs[1] & 0x10u)) {
        m->init_state = 2u;
    }

    /* --- IRQ control: bit 4 of reg[1] --- */
    if (m->regs[1] & 0x10u) {
        /* bit 4 set → disable IRQ and reset counter */
        m->irq_enabled = 0u;
        m->irq_counter = 0u;
        nes->nes_cpu.irq_pending = 0u;
    } else {
        m->irq_enabled = 1u;
    }

    /* --- PRG bank switching --- */
    if (m->init_state < 2u) {
        /* board not yet fully activated; map first 32KB */
        nes_load_prgrom_32k(nes, 0, 0);
    } else if (m->regs[1] & 0x08u) {
        /* MMC1 inner bank mode: inner bank = (reg[3] & 0x07) | 0x08 (bit 3 forced) */
        uint8_t prg_reg = (uint8_t)((m->regs[3] & 0x07u) | 0x08u);
        uint8_t prg_mode = (m->regs[0] >> 2u) & 0x03u;
        switch (prg_mode) {
        case 0u: case 1u:
            /* 32KB mode: even-align the inner bank */
            nes_load_prgrom_32k(nes, 0, (uint16_t)((prg_reg & 0x0Eu) >> 1u));
            break;
        case 2u:
            /* fix $8000 at inner-half base (bank 8), switch $C000 */
            nes_load_prgrom_16k(nes, 0, 0x08u % m->prg16_count);
            nes_load_prgrom_16k(nes, 1, prg_reg % m->prg16_count);
            break;
        default:
            /* fix $C000 at last bank, switch $8000 */
            nes_load_prgrom_16k(nes, 0, prg_reg % m->prg16_count);
            nes_load_prgrom_16k(nes, 1, (uint16_t)(m->prg16_count - 1u));
            break;
        }
    } else {
        /* outer 32KB bank mode: bits 2-1 of reg[1] select the 32KB bank */
        nes_load_prgrom_32k(nes, 0, (uint16_t)((m->regs[1] & 0x06u) >> 1u));
    }

    /* --- mirroring (same as MMC1) --- */
    if (!nes->nes_rom.four_screen) {
        switch (m->regs[0] & 0x03u) {
        case 0u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
        case 1u: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
        case 2u: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
        default: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
        }
    }

    nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper105_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper105_t* m = (mapper105_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper105_t));

    /* NES-EVENT needs $6000-$7FFF WRAM like MMC1 */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) {
            nes_memset(nes->nes_rom.sram, 0x00, SRAM_SIZE);
        }
    }

    m->prg16_count = (uint16_t)(nes->nes_rom.prg_rom_size);
    if (m->prg16_count == 0u) m->prg16_count = 1u;

    /* power-on: control = $0C (P=3: fix last bank at $C000; M=0: one-screen) */
    m->regs[0] = 0x0Cu;
    /* start with IRQ disabled (bit 4 set); init_state begins at 0 */
    m->regs[1] = 0x10u;

    mapper105_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper105_t* m = (mapper105_t*)nes->nes_mapper.mapper_register;
    if (data & 0x80u) {
        m->shift = 0u;
        m->shift_count = 0u;
        m->regs[0] |= 0x0Cu;
        mapper105_update_banks(nes);
        return;
    }
    m->shift = (uint8_t)((m->shift >> 1u) | ((data & 0x01u) << 4u));
    m->shift_count++;
    if (m->shift_count == 5u) {
        uint8_t reg = (uint8_t)((address >> 13u) & 0x03u);
        m->regs[reg] = m->shift & 0x1Fu;
        m->shift       = 0u;
        m->shift_count = 0u;
        mapper105_update_banks(nes);
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper105_t* m = (mapper105_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enabled) return;
    m->irq_counter += cycles;
    if (m->irq_counter >= MAPPER105_IRQ_PERIOD) {
        m->irq_enabled = 0u;
        nes_cpu_irq(nes);
    }
}

int nes_mapper105_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

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
 * https://www.nesdev.org/wiki/INES_Mapper_253
 * Mapper 253 — 龙珠Z 系列 (Dragon Ball Z pirate, VRC4-like board).
 * Based on FCEUX boards/253.cpp (CaH4e3, 2009).
 *
 * PRG registers (exact addresses):
 *   $8010 : 8KB PRG bank for $8000-$9FFF
 *   $A010 : 8KB PRG bank for $A000-$BFFF
 *   $C000-$FFFF fixed to last two 8KB banks
 *   $9400 : mirroring bits[1:0] (0=V, 1=H, 2=1scr0, 3=1scr1)
 *
 * CHR registers ($B000-$E00C):
 *   Address decode: ind = ((((A&8)|(A>>8))>>3)+2)&7, sar = A&4
 *   sar==0 (low nibble):  chrlo[ind][3:0] = data[3:0]
 *   sar!=0 (high nibble): chrlo[ind][7:4] = data[3:0]; chrhi[ind] = data[7:4]
 *   Full CHR bank = chrlo[ind] | (chrhi[ind] << 8)
 *
 * CHR-RAM (2KB, two 1KB pages):
 *   When vlock==0 and chrlo[i]==4: slot i uses CHR-RAM page 0
 *   When vlock==0 and chrlo[i]==5: slot i uses CHR-RAM page 1
 *   Writing chrlo[0]==0x88 sets vlock=1 (locks CHR-RAM out)
 *   Writing chrlo[0]==0xC8 clears vlock=0 (unlocks CHR-RAM)
 *
 * IRQ (CPU-clock based, counts at 341 PPU cycles per tick):
 *   $F000 : ACK + set latch bits[3:0]
 *   $F004 : ACK + set latch bits[7:4]
 *   $F008 : ACK + reset clock + load counter=latch + arm (bit1=enable)
 *   Counter increments each scanline; fires when 8-bit count overflows (0xFF→0x00).
 *   After firing, auto-reloads from latch.
 *
 * WRAM: 8KB at $6000-$7FFF.
 */

typedef struct {
    uint8_t  prg[2];
    uint8_t  chrlo[8];
    uint8_t  chrhi[8];
    uint8_t  mirror;
    uint8_t  vlock;
    uint8_t  irq_enable;
    uint8_t  irq_latch;
    uint16_t irq_counter;
    uint32_t irq_clock;
    uint8_t  chr_ram[2048]; /* 2KB CHR-RAM: page 0 at offset 0, page 1 at offset 1024 */
} mapper253_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static const nes_mirror_type_t mapper253_mirror_tbl[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

static void mapper253_sync(nes_t* nes) {
    mapper253_t* m = (mapper253_t*)nes->nes_mapper.mapper_register;
    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    if (prg_banks == 0u) return;

    nes_load_prgrom_8k(nes, 0, (uint16_t)(m->prg[0] % prg_banks));
    nes_load_prgrom_8k(nes, 1, (uint16_t)(m->prg[1] % prg_banks));
    nes_load_prgrom_8k(nes, 2, (uint16_t)(prg_banks - 2u));
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_banks - 1u));

    uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    for (uint8_t i = 0u; i < 8u; i++) {
        uint16_t chr = (uint16_t)(m->chrlo[i] | ((uint16_t)m->chrhi[i] << 8));
        if (((m->chrlo[i] == 4u) || (m->chrlo[i] == 5u)) && !m->vlock) {
            /* CHR-RAM: chrlo==4 → page 0, chrlo==5 → page 1 */
            nes->nes_ppu.pattern_table[i] = m->chr_ram + (uint32_t)(chr & 1u) * 1024u;
        } else if (chr_banks > 0u) {
            nes_load_chrrom_1k(nes, i, chr % chr_banks);
        }
    }

    if (!nes->nes_rom.four_screen) {
        nes_ppu_screen_mirrors(nes, mapper253_mirror_tbl[m->mirror & 3u]);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper253_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper253_t* m = (mapper253_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper253_t));

    /* 8KB WRAM at $6000-$7FFF */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
    }

    mapper253_sync(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper253_t* m = (mapper253_t*)nes->nes_mapper.mapper_register;

    /* CHR bank registers: $B000-$E00C (FCEUX formula) */
    if (address >= 0xB000u && address <= 0xE00Cu) {
        /* ind = ((((A&8)|(A>>8))>>3)+2)&7 selects which of the 8 CHR slots */
        uint8_t ind = (uint8_t)(((((address & 8u) | (address >> 8)) >> 3u) + 2u) & 7u);
        /* sar=0 → low nibble, sar!=0 → high nibble */
        uint8_t sar = (uint8_t)(address & 4u);
        uint8_t clo;
        if (sar) {
            clo = (uint8_t)((m->chrlo[ind] & 0x0Fu) | ((data & 0x0Fu) << 4u));
            m->chrhi[ind] = (uint8_t)(data >> 4u);
        } else {
            clo = (uint8_t)((m->chrlo[ind] & 0xF0u) | (data & 0x0Fu));
        }
        m->chrlo[ind] = clo;
        /* vlock control: only triggered by writes to CHR slot 0 */
        if (ind == 0u) {
            if      (clo == 0xC8u) m->vlock = 0u;
            else if (clo == 0x88u) m->vlock = 1u;
        }
        mapper253_sync(nes);
        return;
    }

    /* PRG / mirroring / IRQ registers at exact addresses */
    switch (address) {
    case 0x8010u:
        m->prg[0] = data;
        mapper253_sync(nes);
        break;
    case 0xA010u:
        m->prg[1] = data;
        mapper253_sync(nes);
        break;
    case 0x9400u:
        m->mirror = data & 3u;
        mapper253_sync(nes);
        break;
    case 0xF000u:
        nes->nes_cpu.irq_pending = 0;
        m->irq_latch = (uint8_t)((m->irq_latch & 0xF0u) | (data & 0x0Fu));
        break;
    case 0xF004u:
        nes->nes_cpu.irq_pending = 0;
        m->irq_latch = (uint8_t)((m->irq_latch & 0x0Fu) | ((data & 0x0Fu) << 4u));
        break;
    case 0xF008u:
        nes->nes_cpu.irq_pending = 0;
        m->irq_clock   = 0u;
        m->irq_counter = m->irq_latch;
        m->irq_enable  = (data & 2u) ? 1u : 0u;
        break;
    default:
        break;
    }
}

/*
 * IRQ: CPU-clock based, counts PPU cycles (cpu_cycles * 3).
 * Every 341 PPU cycles (= 1 scanline) the 8-bit counter increments.
 * Fires when the counter overflows from 0xFF to 0x100 (bit8 set).
 * After firing, counter auto-reloads from latch.
 */
static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper253_t* m = (mapper253_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_enable) return;
    m->irq_clock += (uint32_t)cycles * 3u;
    while (m->irq_clock >= 341u) {
        m->irq_clock -= 341u;
        m->irq_counter++;
        if (m->irq_counter & 0x100u) {
            nes_cpu_irq(nes);
            m->irq_counter = m->irq_latch;
        }
    }
}

int nes_mapper253_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

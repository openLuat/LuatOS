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
 * https://www.nesdev.org/wiki/INES_Mapper_083
 * Mapper 83 — Cony/Yoko (龙珠4合1 etc.)
 *
 * Reference: Nestopia NstBoardCony.cpp
 *
 * Register map ($8000-$8FFF, repeating every $400):
 *   $x000-$x0FF  prg[4]  : outer block + inner 16KB bank (mode 0)
 *   $x100-$x1FF  ctrl    : bit7=IRQ global enable, bit6=IRQ step dir,
 *                          bit5=WRAM enable, bit4=PRG mode,
 *                          bits[1:0]=mirroring (0=V,1=H,2=1scr-A,3=1scr-B)
 *   $x200 (even) IRQ lo  : IRQ counter low byte + ACK
 *   $x201 (odd)  IRQ hi  : IRQ counter high byte + enable + ACK
 *   $x300-$x30F  prg[0-3]: 8KB PRG bank registers for mode 1 (addr&3)
 *   $x310-$x317  CHR[0-7]: CHR 1KB bank (addr&7); bank = (prg4<<4 & 0x300)|data
 *
 * Also: $B000/$B0FF/$B100 → prg[4] (outer block select mirrors)
 *       $5100-$51FF → pr8 shadow register (R/W)
 *
 * PRG mode 0 (ctrl bit4=0): 16KB switchable $8000-$BFFF + fixed last 16KB $C000-$FFFF
 *   switchable = prg[4] & 0x3F  (16KB unit)
 *   fixed      = (prg[4] & 0x30) | 0x0F  (last 16KB of current outer block)
 *
 * PRG mode 1 (ctrl bit4=1): 8KB×3 switchable + slot3 retains mode-0 fixed value
 *   $8000-$9FFF = prg[0], $A000-$BFFF = prg[1], $C000-$DFFF = prg[2]
 *
 * IRQ: 16-bit CPU-cycle counter; bit6=0 count-up, bit6=1 count-down; fires at 0.
 */

typedef struct {
    uint8_t  ctrl;          /* $8100 control register */
    uint8_t  prg[5];        /* [0-3]=8KB banks (mode1), [4]=outer/16KB */
    uint8_t  pr8;           /* $5100 shadow register */
    uint16_t irq_counter;
    uint8_t  irq_enabled;
} mapper83_t;

static void mapper83_update_prg(nes_t* nes) {
    mapper83_t* m = (mapper83_t*)nes->nes_mapper.mapper_register;
    uint16_t prg_count = (uint16_t)nes->nes_rom.prg_rom_size * 2u;  /* 8KB banks */

    if (m->ctrl & 0x10u) {
        /* Mode 1: 8KB × 3 switchable; slot3 keeps last mode-0 value */
        nes_load_prgrom_8k(nes, 0, m->prg[0] % prg_count);
        nes_load_prgrom_8k(nes, 1, m->prg[1] % prg_count);
        nes_load_prgrom_8k(nes, 2, m->prg[2] % prg_count);
    } else {
        /* Mode 0: 16KB switchable ($8000-$BFFF) + fixed last 16KB ($C000-$FFFF) */
        uint16_t inner16 = (uint16_t)(m->prg[4] & 0x3Fu);
        uint16_t fixed16 = (uint16_t)((m->prg[4] & 0x30u) | 0x0Fu);
        nes_load_prgrom_8k(nes, 0, (uint16_t)(inner16 * 2u) % prg_count);
        nes_load_prgrom_8k(nes, 1, (uint16_t)(inner16 * 2u + 1u) % prg_count);
        nes_load_prgrom_8k(nes, 2, (uint16_t)(fixed16 * 2u) % prg_count);
        nes_load_prgrom_8k(nes, 3, (uint16_t)(fixed16 * 2u + 1u) % prg_count);
    }
}

static void mapper83_write_chr(nes_t* nes, uint8_t slot, uint8_t data) {
    if (nes->nes_rom.chr_rom_size == 0u) return;
    mapper83_t* m = (mapper83_t*)nes->nes_mapper.mapper_register;
    uint16_t chr_count = (uint16_t)nes->nes_rom.chr_rom_size * 8u;  /* 1KB banks */
    uint16_t bank = (uint16_t)(((uint16_t)(m->prg[4]) << 4u & 0x300u) | (uint16_t)data) % chr_count;
    nes_load_chrrom_1k(nes, slot, bank);
}

static void mapper83_set_mirroring(nes_t* nes, uint8_t ctrl_lo2) {
    switch (ctrl_lo2 & 3u) {
        case 0:  nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);     break;
        case 1:  nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);   break;
        case 2:  nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0);  break;
        default: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1);  break;
    }
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper83_t));
        if (!nes->nes_mapper.mapper_register) return;
    }
    mapper83_t* m = (mapper83_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper83_t));

    /* Allocate 8KB WRAM ($6000-$7FFF) */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
    }

    /* PRG mode 0, prg[4]=0: $8000-$BFFF=16KB bank0, $C000-$FFFF=16KB bank0x0F */
    mapper83_update_prg(nes);

    /* CHR: all 8 slots to bank 0 */
    for (uint8_t i = 0u; i < 8u; i++) {
        mapper83_write_chr(nes, i, 0u);
    }
}

/* $8000-$FFFF write handler */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper83_t* m = (mapper83_t*)nes->nes_mapper.mapper_register;
    if (!m) return;

    /* $B000/$B0FF/$B100: outer block / prg[4] (same as $8000-$80FF) */
    if (address == 0xB000u || address == 0xB0FFu || address == 0xB100u) {
        m->prg[4] = data;
        mapper83_update_prg(nes);
        return;
    }

    /* $8000-$8FFF: registers repeat every $400 bytes */
    if (address < 0x9000u) {
        uint16_t offset = address & 0x03FFu;

        if (offset < 0x100u) {
            /* $x000-$x0FF: prg[4] (inner 16KB bank + outer block bits) */
            m->prg[4] = data;
            mapper83_update_prg(nes);
        } else if (offset < 0x200u) {
            /* $x100-$x1FF: ctrl */
            uint8_t diff = m->ctrl ^ data;
            m->ctrl = data;
            if (diff & 0x10u) mapper83_update_prg(nes);
            if (diff & 0x03u) mapper83_set_mirroring(nes, data);
        } else if (offset < 0x300u) {
            /* $x200-$x2FF: IRQ counter (even=lo+ACK, odd=hi+enable+ACK) */
            if (!(address & 1u)) {
                m->irq_counter = (m->irq_counter & 0xFF00u) | (uint16_t)data;
                nes->nes_cpu.irq_pending = 0;
            } else {
                m->irq_counter = (m->irq_counter & 0x00FFu) | ((uint16_t)data << 8);
                m->irq_enabled = (m->ctrl & 0x80u) ? 1u : 0u;
                nes->nes_cpu.irq_pending = 0;
            }
        } else {
            /* $x300-$x3FF: PRG banks (bit4=0) or CHR banks (bit4=1, bit3=0) */
            uint16_t sub = offset - 0x300u;
            if (!(sub & 0x10u)) {
                /* $x300-$x30F (repeating every $20): PRG slot = addr & 3 */
                uint8_t slot = (uint8_t)(address & 0x03u);
                m->prg[slot] = data & 0x1Fu;
                if (m->ctrl & 0x10u) mapper83_update_prg(nes);
            } else if (!(sub & 0x08u)) {
                /* $x310-$x317 (repeating every $20): CHR slot = addr & 7 */
                mapper83_write_chr(nes, (uint8_t)(address & 0x07u), data);
            }
        }
    }
}

/* $4020-$5FFF write: $5100-$51FF = pr8 shadow register */
static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper83_t* m = (mapper83_t*)nes->nes_mapper.mapper_register;
    if (!m) return;
    if (address >= 0x5100u) m->pr8 = data;
}

/* $4020-$5FFF read: $5100-$51FF = pr8; $5000 = 0xFF (no DIP switch) */
static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    mapper83_t* m = (mapper83_t*)nes->nes_mapper.mapper_register;
    if (!m) return 0xFFu;
    if (address >= 0x5100u) return m->pr8;
    return 0xFFu;
}

/* CPU-cycle IRQ: count up (bit6=0) or down (bit6=1), fires when counter reaches 0 */
static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper83_t* m = (mapper83_t*)nes->nes_mapper.mapper_register;
    if (!m || !m->irq_enabled || !m->irq_counter) return;

    if (m->ctrl & 0x40u) {
        /* Count down */
        if (cycles >= m->irq_counter) {
            m->irq_counter = 0u;
            m->irq_enabled = 0u;
            nes->nes_cpu.irq_pending = 1;
        } else {
            m->irq_counter -= cycles;
        }
    } else {
        /* Count up: fire when wraps past 0xFFFF */
        uint32_t next = (uint32_t)m->irq_counter + (uint32_t)cycles;
        if (next >= 0x10000u) {
            m->irq_counter = 0u;
            m->irq_enabled = 0u;
            nes->nes_cpu.irq_pending = 1;
        } else {
            m->irq_counter = (uint16_t)next;
        }
    }
}

int nes_mapper83_init(nes_t* nes) {
    nes->nes_mapper.mapper_init       = nes_mapper_init;
    nes->nes_mapper.mapper_deinit     = nes_mapper_deinit;
    nes->nes_mapper.mapper_write      = nes_mapper_write;
    nes->nes_mapper.mapper_apu        = nes_mapper_apu;
    nes->nes_mapper.mapper_read_apu   = nes_mapper_read_apu;
    nes->nes_mapper.mapper_cpu_clock  = nes_mapper_cpu_clock;
    return NES_OK;
}

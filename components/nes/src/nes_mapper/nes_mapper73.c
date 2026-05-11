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

/* https://www.nesdev.org/wiki/INES_Mapper_073
 * Mapper 73 - VRC3 (Konami).
 * PRG: 16KB switchable at $8000-$BFFF; $C000-$FFFF fixed (last 16KB).
 * CHR: CHR-RAM only (no CHR banking registers).
 * IRQ: CPU-cycle-based 16-bit (or 8-bit) decrementing counter.
 */

typedef struct {
    uint16_t irq_latch;           /* 16-bit assembled latch from nibble writes */
    uint16_t irq_counter;         /* active countdown counter */
    uint8_t  irq_enable;          /* 1 = IRQ currently active */
    uint8_t  irq_enable_after_ack;/* $C000 bit0: re-enable IRQ on acknowledge */
    uint8_t  irq_mode;            /* 0=8-bit low-byte only, 1=full 16-bit */
} mapper73_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper73_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper73_register_t* r = (mapper73_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper73_register_t));

    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1u));
    nes_load_chrrom_8k(nes, 0, 0); /* CHR-RAM */
}

/*
 * $8000: IRQ latch bits[3:0]
 * $9000: IRQ latch bits[7:4]
 * $A000: IRQ latch bits[11:8]
 * $B000: IRQ latch bits[15:12]
 * $C000: IRQ control — bit0=enable-after-ack, bit1=enable-now, bit2=16-bit mode
 * $D000: IRQ acknowledge — disable IRQ; reload counter and re-enable if $C000 bit0 set
 * $F000: PRG 16KB bank select (bits[3:0]) for $8000-$BFFF
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper73_register_t* r = (mapper73_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000u) {
    case 0x8000u:
        r->irq_latch = (r->irq_latch & 0xFFF0u) | (uint16_t)(data & 0x0Fu);
        break;
    case 0x9000u:
        r->irq_latch = (r->irq_latch & 0xFF0Fu) | (uint16_t)((data & 0x0Fu) << 4);
        break;
    case 0xA000u:
        r->irq_latch = (r->irq_latch & 0xF0FFu) | (uint16_t)((data & 0x0Fu) << 8);
        break;
    case 0xB000u:
        r->irq_latch = (r->irq_latch & 0x0FFFu) | (uint16_t)((data & 0x0Fu) << 12);
        break;
    case 0xC000u: /* IRQ control */
        r->irq_enable_after_ack = data & 0x01u;
        r->irq_mode             = (data >> 2) & 0x01u;
        if (data & 0x02u) {
            r->irq_enable  = 1;
            r->irq_counter = r->irq_latch;
        } else {
            r->irq_enable = 0;
        }
        break;
    case 0xD000u: /* IRQ acknowledge */
        r->irq_enable          = r->irq_enable_after_ack;
        nes->nes_cpu.irq_pending = 0;
        if (r->irq_enable_after_ack) {
            r->irq_counter = r->irq_latch;
        }
        break;
    case 0xF000u: /* PRG 16KB bank select */
        nes_load_prgrom_16k(nes, 0, (uint16_t)(data & 0x0Fu));
        break;
    default:
        break;
    }
}

/*
 * Decrement the IRQ counter by the number of CPU cycles consumed.
 * In 8-bit mode only the low 8 bits are tested; in 16-bit mode the full
 * counter is tested.  When the counter reaches or crosses zero the IRQ
 * is raised, the counter is reloaded, and the enable flag is updated.
 */
static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper73_register_t* r = (mapper73_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;

    if (r->irq_mode == 0) {
        /* 8-bit mode: only low byte of counter is active */
        uint8_t lo = (uint8_t)r->irq_counter;
        if (lo <= (uint8_t)cycles) {
            r->irq_counter = r->irq_latch;
            r->irq_enable  = r->irq_enable_after_ack;
            nes_cpu_irq(nes);
        } else {
            r->irq_counter = (r->irq_counter & 0xFF00u) | (uint16_t)(lo - (uint8_t)cycles);
        }
    } else {
        /* 16-bit mode */
        if (r->irq_counter <= cycles) {
            r->irq_counter = r->irq_latch;
            r->irq_enable  = r->irq_enable_after_ack;
            nes_cpu_irq(nes);
        } else {
            r->irq_counter = (uint16_t)(r->irq_counter - cycles);
        }
    }
}

int nes_mapper73_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

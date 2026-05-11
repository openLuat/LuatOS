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

/* https://www.nesdev.org/wiki/INES_Mapper_065 */

typedef struct {
    uint8_t  prg[3];        /* 8KB PRG bank indices at $8000/$A000/$C000 */
    uint8_t  chr[8];        /* 1KB CHR bank indices [0-7] */
    uint8_t  irq_enable;    /* IRQ enabled flag */
    int32_t  irq_counter;   /* IRQ countdown counter */
    uint16_t irq_reload;    /* IRQ reload value (big-endian: $9005=high, $9006=low) */
} nes_mapper65_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper65_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper65_t* r = (nes_mapper65_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(*r));

    uint16_t num_8k = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    r->prg[0] = 0;
    r->prg[1] = 0;
    r->prg[2] = (uint8_t)(num_8k - 2u);
    nes_load_prgrom_8k(nes, 0, r->prg[0]);
    nes_load_prgrom_8k(nes, 1, r->prg[1]);
    nes_load_prgrom_8k(nes, 2, r->prg[2]);
    nes_load_prgrom_8k(nes, 3, num_8k - 1);

    for (uint8_t i = 0; i < 8; i++) {
        r->chr[i] = 0;
        nes_load_chrrom_1k(nes, i, r->chr[i]);
    }
    nes_ppu_screen_mirrors(nes, nes->nes_rom.mirroring_type ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
}

/*
 * $8000: 8KB PRG bank at $8000
 * $9001: Mirroring — bit[7]: 0=vertical, 1=horizontal
 * $9003: IRQ enable — bit[7]: 1=enable, 0=disable+acknowledge
 * $9004: IRQ reload — load counter from irq_reload
 * $9005: IRQ reload value high byte
 * $9006: IRQ reload value low byte
 * $A000: 8KB PRG bank at $A000
 * $B000-$B007: CHR 1KB banks [0-7]
 * $C000: 8KB PRG bank at $C000
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper65_t* r = (nes_mapper65_t*)nes->nes_mapper.mapper_register;
    uint16_t num_8k = (uint16_t)(nes->nes_rom.prg_rom_size * 2);

    if ((address & 0xFFF8) == 0xB000) {
        uint8_t slot = (uint8_t)(address & 7);
        r->chr[slot] = data;
        nes_load_chrrom_1k(nes, slot, data);
        return;
    }

    switch (address) {
        case 0x8000:
            r->prg[0] = data;
            nes_load_prgrom_8k(nes, 0, data % num_8k);
            break;
        case 0x9001:
            nes_ppu_screen_mirrors(nes, (data & 0x80u) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
            break;
        case 0x9003:
            r->irq_enable = (data & 0x80u) ? 1u : 0u;
            nes->nes_cpu.irq_pending = 0;
            break;
        case 0x9004:
            r->irq_counter = (int32_t)r->irq_reload;
            break;
        case 0x9005:
            r->irq_reload = (r->irq_reload & 0x00FF) | ((uint16_t)data << 8);
            break;
        case 0x9006:
            r->irq_reload = (r->irq_reload & 0xFF00) | data;
            break;
        case 0xA000:
            r->prg[1] = data;
            nes_load_prgrom_8k(nes, 1, data % num_8k);
            break;
        case 0xC000:
            r->prg[2] = data;
            nes_load_prgrom_8k(nes, 2, data % num_8k);
            break;
        default:
            break;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    nes_mapper65_t* r = (nes_mapper65_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;

    r->irq_counter -= (int32_t)cycles;
    if (r->irq_counter < -4) {
        r->irq_enable = 0;
        r->irq_counter = -1;
        nes_cpu_irq(nes);
    }
}

int nes_mapper65_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

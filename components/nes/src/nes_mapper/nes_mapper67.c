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

/* https://www.nesdev.org/wiki/Sunsoft_mapper_3_(INES_67) */

typedef struct {
    uint8_t  chr[4];        /* 2KB CHR bank indices for $0000/$0800/$1000/$1800 */
    uint8_t  prg;           /* 16KB PRG bank at $8000 */
    uint8_t  irq_enable;
    uint8_t  irq_flag;      /* set when IRQ has fired; cleared on $E800 acknowledge */
    uint16_t irq_counter;   /* 16-bit countdown; fires on underflow (0 → 0xFFFF) */
} nes_mapper67_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static inline void mapper67_load_chr2k(nes_t* nes, uint8_t slot, uint8_t bank) {
    uint8_t num_1k = (uint8_t)(nes->nes_rom.chr_rom_size * 8);
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2),     (uint8_t)((bank * 2)     % num_1k));
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2 + 1), (uint8_t)((bank * 2 + 1) % num_1k));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper67_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper67_t* r = (nes_mapper67_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(*r));

    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    for (uint8_t i = 0; i < 4; i++) {
        r->chr[i] = i;
        mapper67_load_chr2k(nes, i, i);
    }
    nes_ppu_screen_mirrors(nes, nes->nes_rom.mirroring_type ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
}

/*
 * $8800-$8FFF: 2KB CHR bank for PPU $0000-$07FF
 * $9800-$9FFF: 2KB CHR bank for PPU $0800-$0FFF
 * $A800-$AFFF: 2KB CHR bank for PPU $1000-$17FF
 * $B800-$BFFF: 2KB CHR bank for PPU $1800-$1FFF
 * $C800-$CFFF: IRQ counter high byte
 * $D800-$DFFF: IRQ counter low byte
 * $E800-$EFFF: IRQ acknowledge; bit[4]=enable
 * $F800-$FFFF: bits[2:0]=16KB PRG bank; bit[3]=mirroring (0=horizontal, 1=vertical)
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper67_t* r = (nes_mapper67_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF800) {
        case 0x8800:
            r->chr[0] = data;
            mapper67_load_chr2k(nes, 0, data);
            break;
        case 0x9800:
            r->chr[1] = data;
            mapper67_load_chr2k(nes, 1, data);
            break;
        case 0xA800:
            r->chr[2] = data;
            mapper67_load_chr2k(nes, 2, data);
            break;
        case 0xB800:
            r->chr[3] = data;
            mapper67_load_chr2k(nes, 3, data);
            break;
        case 0xC800:
            r->irq_counter = (r->irq_counter & 0x00FF) | ((uint16_t)data << 8);
            break;
        case 0xD800:
            r->irq_counter = (r->irq_counter & 0xFF00) | data;
            break;
        case 0xE800:
            /* acknowledge IRQ; bit[4] selects enable/disable */
            r->irq_enable = (data >> 4) & 1;
            r->irq_flag = 0;
            nes->nes_cpu.irq_pending = 0;
            break;
        case 0xF800:
            r->prg = data & 0x07;
            nes_load_prgrom_16k(nes, 0, r->prg % nes->nes_rom.prg_rom_size);
            nes_ppu_screen_mirrors(nes, (data & 0x08) ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
            break;
        default:
            break;
    }
}

/*
 * 16-bit IRQ counter decrements each scanline; fires on underflow (0 → 0xFFFF).
 * Game writes to $E800 (bit[4]=0) to acknowledge and disable.
 */
static void nes_mapper_hsync(nes_t* nes) {
    nes_mapper67_t* r = (nes_mapper67_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    r->irq_counter--;
    if (r->irq_counter == 0xFFFF) {
        r->irq_flag = 1;
        nes_cpu_irq(nes);
    }
}

int nes_mapper67_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_hsync  = nes_mapper_hsync;
    return NES_OK;
}

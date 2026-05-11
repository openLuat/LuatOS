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

/* https://www.nesdev.org/wiki/MMC2 */

typedef struct {
    uint8_t prg;        /* 8KB PRG bank index for $8000-$9FFF */
    uint8_t creg[4];    /* CHR 4KB bank regs: [0,1]=left slot, [2,3]=right slot */
    uint8_t latch0;     /* 0 → use creg[0], 1 → use creg[1] for $0000-$0FFF */
    uint8_t latch1;     /* 0 → use creg[2], 1 → use creg[3] for $1000-$1FFF */
} mapper9_reg_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper9_update_prg(nes_t* nes) {
    mapper9_reg_t* mapper_reg = (mapper9_reg_t*)nes->nes_mapper.mapper_register;
    uint16_t num_8k = (uint16_t)(nes->nes_rom.prg_rom_size * 2);
    /* $8000-$9FFF: switchable */
    nes_load_prgrom_8k(nes, 0, mapper_reg->prg % num_8k);
    /* $A000-$BFFF: fixed to 3rd-to-last 8KB bank */
    nes_load_prgrom_8k(nes, 1, (num_8k - 3) % num_8k);
    /* $C000-$DFFF: fixed to 2nd-to-last 8KB bank */
    nes_load_prgrom_8k(nes, 2, (num_8k - 2) % num_8k);
    /* $E000-$FFFF: fixed to last 8KB bank */
    nes_load_prgrom_8k(nes, 3, num_8k - 1);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper9_reg_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper9_reg_t* mapper_reg = (mapper9_reg_t*)nes->nes_mapper.mapper_register;
    nes_memset(mapper_reg, 0, sizeof(*mapper_reg));
    mapper_reg->latch0 = 1;
    mapper_reg->latch1 = 1;

    mapper9_update_prg(nes);
    nes_load_chrrom_4k(nes, 0, mapper_reg->creg[mapper_reg->latch0]);
    nes_load_chrrom_4k(nes, 1, mapper_reg->creg[2 + mapper_reg->latch1]);

    nes_ppu_screen_mirrors(nes, nes->nes_rom.mirroring_type ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
}

/*
    Registers ($A000-$FFFF):
    $A000: PRG bank select    — selects 8KB bank for $8000-$9FFF
    $B000: CHR bank FD/$0000  — 4KB bank used when latch0=0
    $C000: CHR bank FE/$0000  — 4KB bank used when latch0=1
    $D000: CHR bank FD/$1000  — 4KB bank used when latch1=0
    $E000: CHR bank FE/$1000  — 4KB bank used when latch1=1
    $F000: Mirroring          — bit 0: 0=vertical, 1=horizontal
*/
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper9_reg_t* mapper_reg = (mapper9_reg_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000) {
        case 0xA000:
            mapper_reg->prg = data & 0x0F;
            mapper9_update_prg(nes);
            break;
        case 0xB000:
            mapper_reg->creg[0] = data & 0x1F;
            nes_load_chrrom_4k(nes, 0, mapper_reg->creg[mapper_reg->latch0]);
            break;
        case 0xC000:
            mapper_reg->creg[1] = data & 0x1F;
            nes_load_chrrom_4k(nes, 0, mapper_reg->creg[mapper_reg->latch0]);
            break;
        case 0xD000:
            mapper_reg->creg[2] = data & 0x1F;
            nes_load_chrrom_4k(nes, 1, mapper_reg->creg[2 + mapper_reg->latch1]);
            break;
        case 0xE000:
            mapper_reg->creg[3] = data & 0x1F;
            nes_load_chrrom_4k(nes, 1, mapper_reg->creg[2 + mapper_reg->latch1]);
            break;
        case 0xF000:
            nes_ppu_screen_mirrors(nes, (data & 1) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
            break;
        default:
            break;
    }
}

/*
    PPU latch — triggered after the PPU fetches the high pattern byte of tile $FD/$FE.
    MMC2 uses exact trigger addresses for $0000-$0FFF and ranges for $1000-$1FFF.
*/
static void nes_mapper_ppu(nes_t* nes, uint16_t address) {
    mapper9_reg_t* mapper_reg = (mapper9_reg_t*)nes->nes_mapper.mapper_register;
    if (address == 0x0FD8u) {
        mapper_reg->latch0 = 0;
        nes_load_chrrom_4k(nes, 0, mapper_reg->creg[0]);
    } else if (address == 0x0FE8u) {
        mapper_reg->latch0 = 1;
        nes_load_chrrom_4k(nes, 0, mapper_reg->creg[1]);
    } else if (address >= 0x1FD8u && address <= 0x1FDFu) {
        mapper_reg->latch1 = 0;
        nes_load_chrrom_4k(nes, 1, mapper_reg->creg[2]);
    } else if (address >= 0x1FE8u && address <= 0x1FEFu) {
        mapper_reg->latch1 = 1;
        nes_load_chrrom_4k(nes, 1, mapper_reg->creg[3]);
    }
}

int nes_mapper9_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_ppu   = nes_mapper_ppu;
    nes->nes_mapper.mapper_ppu_tile_min = 0xFD;
    nes->nes_mapper.mapper_ppu_tile_max = 0xFE;
    return NES_OK;
}

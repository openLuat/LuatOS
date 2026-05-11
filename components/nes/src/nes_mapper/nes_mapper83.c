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
 * Mapper 83 — Cony/Yoko
 * Used by Chinese pirate multi-game carts (e.g. 龙珠4合1).
 *
 * $8000      : bits[5:0] = PRG 32KB bank select
 * $8100-$87FF: CHR 1KB bank for slot (addr>>8)&0x07  (slots 1-7)
 *              slot 0 defaults to bank 0 from init
 * No IRQ.
 */

typedef struct {
    uint8_t prg_bank;
    uint8_t chr[8];
} mapper83_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper83_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper83_register_t* r = (mapper83_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper83_register_t));

    nes_load_prgrom_32k(nes, 0, 0);

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        for (int i = 0; i < 8; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)i, 0);
        }
    }
}

/*
 * $8000      : PRG 32KB bank select (bits[5:0])
 * $8100-$87FF: CHR 1KB bank N where N = (address>>8)&0x07
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper83_register_t* r = (mapper83_register_t*)nes->nes_mapper.mapper_register;
    if (address == 0x8000u) {
        r->prg_bank = data & 0x3Fu;
        nes_load_prgrom_32k(nes, 0, r->prg_bank);
    } else if (address >= 0x8100u && address <= 0x87FFu) {
        uint8_t slot = (uint8_t)((address >> 8u) & 0x07u);
        r->chr[slot] = data;
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_1k(nes, slot, r->chr[slot]);
        }
    }
}

int nes_mapper83_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

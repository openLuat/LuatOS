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

/* https://www.nesdev.org/wiki/INES_Mapper_154
 * Mapper 154 — Namco 118 with single-screen mirroring.
 * Same as mapper 88 (Namco 118) but bit 6 of CHR register 0 or 1 writes
 * selects single-screen nametable page (0=NT0, 1=NT1).
 */

typedef struct {
    uint8_t reg_select;
    uint8_t chr[6];
    uint8_t prg[2];
    uint8_t mirror;
} mapper154_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper154_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper154_t* r = (mapper154_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper154_t));

    uint8_t last = (uint8_t)(nes->nes_rom.prg_rom_size * 2u - 1u);
    nes_load_prgrom_8k(nes, 0, 0);
    nes_load_prgrom_8k(nes, 1, 1);
    nes_load_prgrom_8k(nes, 2, (uint8_t)(last - 1u));
    nes_load_prgrom_8k(nes, 3, last);

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        for (int i = 0; i < 8; i++) nes_load_chrrom_1k(nes, (uint8_t)i, 0);
    }
    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper154_t* r = (mapper154_t*)nes->nes_mapper.mapper_register;
    if (address & 1u) {
        uint8_t bank = data & 0x3Fu;
        if (r->reg_select <= 1u) {
            /* bit 6 selects single-screen NT page */
            r->mirror = (data >> 6) & 1u;
            if (nes->nes_rom.four_screen == 0)
                nes_ppu_screen_mirrors(nes, r->mirror ? NES_MIRROR_ONE_SCREEN1 : NES_MIRROR_ONE_SCREEN0);
        }
        switch (r->reg_select) {
        case 0:
            r->chr[0] = bank;
            nes_load_chrrom_1k(nes, 0, (uint8_t)(bank * 2u));
            nes_load_chrrom_1k(nes, 1, (uint8_t)(bank * 2u + 1u));
            break;
        case 1:
            r->chr[1] = bank;
            nes_load_chrrom_1k(nes, 2, (uint8_t)(bank * 2u));
            nes_load_chrrom_1k(nes, 3, (uint8_t)(bank * 2u + 1u));
            break;
        case 2: r->chr[2] = bank; nes_load_chrrom_1k(nes, 4, bank); break;
        case 3: r->chr[3] = bank; nes_load_chrrom_1k(nes, 5, bank); break;
        case 4: r->chr[4] = bank; nes_load_chrrom_1k(nes, 6, bank); break;
        case 5: r->chr[5] = bank; nes_load_chrrom_1k(nes, 7, bank); break;
        case 6: r->prg[0] = bank; nes_load_prgrom_8k(nes, 0, bank); break;
        case 7: r->prg[1] = bank; nes_load_prgrom_8k(nes, 1, bank); break;
        default: break;
        }
    } else {
        r->reg_select = data & 0x07u;
    }
}

int nes_mapper154_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

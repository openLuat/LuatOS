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
 * https://www.nesdev.org/wiki/INES_Mapper_176
 * Mapper 176 — Waixing FC-026 Chinese multicart.
 *
 * All control registers live in the expansion APU range ($4020-$5FFF):
 *   $5FF1: bits[3:0] = PRG 32KB bank select
 *   $5FF3: CHR 8KB bank select
 * No mapper_write, no IRQ.
 */

typedef struct {
    uint8_t prg_bank;
    uint8_t chr_bank;
} mapper176_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper176_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper176_register_t* r = (mapper176_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper176_register_t));

    nes_load_prgrom_32k(nes, 0, 0);

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

/*
 * $5FF1: PRG 32KB bank (bits[3:0])
 * $5FF3: CHR 8KB bank
 */
static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper176_register_t* r = (mapper176_register_t*)nes->nes_mapper.mapper_register;
    switch (address) {
    case 0x5FF1u:
        r->prg_bank = data & 0x0Fu;
        nes_load_prgrom_32k(nes, 0, r->prg_bank);
        break;
    case 0x5FF3u:
        r->chr_bank = data;
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_8k(nes, 0, r->chr_bank);
        }
        break;
    default:
        break;
    }
}

int nes_mapper176_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    return NES_OK;
}

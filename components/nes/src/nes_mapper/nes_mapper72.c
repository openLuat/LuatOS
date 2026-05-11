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

/* https://www.nesdev.org/wiki/INES_Mapper_072
 * Jaleco JF-17 — PRG 16KB + CHR 8KB bank latches.
 * Write $8000-$FFFF:
 *   bit[7] = 1 → load data[3:0] as PRG 16KB bank for $8000-$BFFF
 *   bit[6] = 1 → load data[3:0] as CHR 8KB bank
 * Fixed last 16KB at $C000-$FFFF.
 */

typedef struct {
    uint8_t prg;
    uint8_t chr;
} mapper72_reg_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper72_reg_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper72_reg_t* r = (mapper72_reg_t*)nes->nes_mapper.mapper_register;
    r->prg = 0; r->chr = 0;
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    mapper72_reg_t* r = (mapper72_reg_t*)nes->nes_mapper.mapper_register;
    if (data & 0x80u) {
        r->prg = data & 0x0Fu;
        nes_load_prgrom_16k(nes, 0, r->prg);
    }
    if (data & 0x40u) {
        r->chr = data & 0x0Fu;
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_8k(nes, 0, r->chr);
        }
    }
}

int nes_mapper72_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

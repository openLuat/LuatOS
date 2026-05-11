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

/* https://www.nesdev.org/wiki/INES_Mapper_046
 * Rumble Station (15-in-1) — outer/inner PRG+CHR bank selection.
 * Write $6000-$7FFF: bits[3:0]=outer PRG bank high bits; bits[7:4]=outer CHR high bits
 * Write $8000-$FFFF: bit[0]=inner PRG low bit; bit[4]=inner CHR low bit
 * Final PRG 32KB = (outer_prg<<1)|inner_prg; CHR 8KB = (outer_chr<<1)|inner_chr.
 */

typedef struct {
    uint8_t outer_prg;
    uint8_t outer_chr;
    uint8_t inner_prg;
    uint8_t inner_chr;
} mapper46_reg_t;

static void mapper46_update(nes_t* nes) {
    mapper46_reg_t* r = (mapper46_reg_t*)nes->nes_mapper.mapper_register;
    uint16_t prg = (uint16_t)((r->outer_prg << 1u) | (r->inner_prg & 1u));
    uint8_t  chr = (uint8_t) ((r->outer_chr << 1u) | (r->inner_chr & 1u));
    nes_load_prgrom_32k(nes, 0, prg);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, chr);
    }
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper46_reg_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_memset(nes->nes_mapper.mapper_register, 0, sizeof(mapper46_reg_t));
    mapper46_update(nes);
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    mapper46_reg_t* r = (mapper46_reg_t*)nes->nes_mapper.mapper_register;
    r->outer_prg = (uint8_t)(data & 0x0Fu);
    r->outer_chr = (uint8_t)((data >> 4) & 0x0Fu);
    mapper46_update(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    mapper46_reg_t* r = (mapper46_reg_t*)nes->nes_mapper.mapper_register;
    r->inner_prg = (uint8_t)(data & 0x01u);
    r->inner_chr = (uint8_t)((data >> 4) & 0x01u);
    mapper46_update(nes);
}

int nes_mapper46_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

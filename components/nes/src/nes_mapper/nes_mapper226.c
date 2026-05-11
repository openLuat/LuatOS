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

/* https://www.nesdev.org/wiki/INES_Mapper_226
 * BMC 76-in-1 — two-write latch for PRG+CHR bank.
 * First write ($8000): bits[6:0] = PRG bank high bits; bit[7]=mirror; bit[0]=mode
 * Second write ($8001): bit[0] = PRG bank low bit
 * CHR: always bank 0 (no CHR switching).
 */

typedef struct {
    uint8_t reg0;
    uint8_t reg1;
} mapper226_reg_t;

static void mapper226_update(nes_t* nes) {
    mapper226_reg_t* r = (mapper226_reg_t*)nes->nes_mapper.mapper_register;
    uint16_t prg = (uint16_t)(((r->reg0 & 0x1Fu) << 1) | (r->reg1 & 0x01u));
    if (r->reg0 & 0x40u) {
        /* 32KB mode */
        nes_load_prgrom_32k(nes, 0, (uint16_t)(prg >> 1));
    } else {
        /* 16KB mode */
        nes_load_prgrom_16k(nes, 0, prg);
        nes_load_prgrom_16k(nes, 1, prg);
    }
    if (nes->nes_rom.four_screen == 0) {
        nes_ppu_screen_mirrors(nes, (r->reg0 & 0x80u) ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
    }
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper226_reg_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_memset(nes->nes_mapper.mapper_register, 0, sizeof(mapper226_reg_t));
    mapper226_update(nes);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper226_reg_t* r = (mapper226_reg_t*)nes->nes_mapper.mapper_register;
    if (address & 0x01u) {
        r->reg1 = data;
    } else {
        r->reg0 = data;
    }
    mapper226_update(nes);
}

int nes_mapper226_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

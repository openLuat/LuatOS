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

/* https://www.nesdev.org/wiki/INES_Mapper_246
 * Mapper 246 - Fong Shen Bang (封神榜).
 * PRG: 4x8KB switchable banks at $8000-$FFFF via writes to $6000-$6003.
 * CHR: 4x2KB switchable banks at $0000-$1FFF via writes to $6004-$6007.
 * FCEUX M246Write: range $6000-$67FF, A&7 selects register.
 * WRAM: 2KB at $6800-$6FFF (FCEUX setprg2r).
 */

typedef struct {
    uint8_t prg[4];
    uint8_t chr[4];
} mapper246_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper246_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper246_register_t* r = (mapper246_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper246_register_t));

    // FCEUX power-on: regs[0-3] = 0xFF, all PRG slots map to last bank
    uint16_t last_prg = (uint16_t)(nes->nes_rom.prg_rom_size * 2u - 1u);
    nes_load_prgrom_8k(nes, 0, last_prg);
    nes_load_prgrom_8k(nes, 1, last_prg);
    nes_load_prgrom_8k(nes, 2, last_prg);
    nes_load_prgrom_8k(nes, 3, last_prg);

    // FCEUX power-on: regs[4-7] = 0, all 4x2KB CHR slots map to CHR 2KB bank 0
    if (nes->nes_rom.chr_rom_size > 0) {
        for (uint8_t i = 0; i < 4u; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)(i * 2u),      0u);
            nes_load_chrrom_1k(nes, (uint8_t)(i * 2u + 1u), 1u);
        }
    } else {
        nes_load_chrrom_8k(nes, 0, 0);
    }

    // Allocate WRAM ($6800-$6FFF)
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
    }

    nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);
}

static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    // FCEUX M246Write: range $6000-$67FF, A&7 selects register
    if (address > 0x67FFu) return;

    mapper246_register_t* r = (mapper246_register_t*)nes->nes_mapper.mapper_register;
    uint8_t reg = (uint8_t)(address & 7u);
    if (reg <= 3u) {
        r->prg[reg] = data;
        nes_load_prgrom_8k(nes, reg, data);
    } else {
        uint8_t slot = reg - 4u;
        r->chr[slot] = data;
        if (nes->nes_rom.chr_rom_size > 0) {
            nes_load_chrrom_1k(nes, (uint8_t)(slot * 2u),      (uint16_t)data * 2u);
            nes_load_chrrom_1k(nes, (uint8_t)(slot * 2u + 1u), (uint16_t)data * 2u + 1u);
        }
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)nes; (void)address; (void)data;
}

int nes_mapper246_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    return NES_OK;
}


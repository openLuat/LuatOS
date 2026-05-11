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

/* https://www.nesdev.org/wiki/INES_Mapper_036
 * Mapper 36 — TXC PCB (Strike Wolf).
 * PRG 32KB bank switched by bit6 of write to $8000-$FFFF.
 * CHR 8KB bank switched by bit4 of the same write.
 */

typedef struct {
    uint8_t reg;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper36_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper36_update_banks(nes_t* nes) {
    mapper36_t* m = (mapper36_t*)nes->nes_mapper.mapper_register;
    uint8_t prg32 = (uint8_t)(m->prg_bank_count / 4u);
    uint8_t chr8  = (uint8_t)(m->chr_bank_count / 8u);
    if (prg32 == 0u) prg32 = 1u;
    if (chr8  == 0u) chr8  = 1u;
    nes_load_prgrom_32k(nes, 0, (uint16_t)(((m->reg >> 6u) & 0x01u) % prg32));
    nes_load_chrrom_8k(nes, 0, (uint8_t)(((m->reg >> 4u) & 0x01u) % chr8));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper36_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper36_t* m = (mapper36_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper36_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper36_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper36_t* m = (mapper36_t*)nes->nes_mapper.mapper_register;
    (void)address;
    m->reg = data;
    mapper36_update_banks(nes);
}

int nes_mapper36_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

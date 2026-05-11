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

/* https://www.nesdev.org/wiki/INES_Mapper_104
 * Mapper 104 — Pegasus 5-in-1.
 * Outer 32KB PRG bank via bit select at $5000:
 *   bit7=0: select 32KB outer block via data[6:4]
 *   Inner bank via $8000:
 *     data[2:0]: PRG 16KB within outer block ($8000 fixed, $C000 varies)
 */

typedef struct {
    uint8_t outer;
    uint8_t inner;
    uint8_t prg_bank_count;
} mapper104_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper104_update_banks(nes_t* nes) {
    mapper104_t* m = (mapper104_t*)nes->nes_mapper.mapper_register;
    uint8_t prg16 = (uint8_t)(m->prg_bank_count / 2u);
    if (prg16 == 0u) prg16 = 1u;
    uint8_t base   = (uint8_t)((m->outer & 0x07u) << 2u);
    uint8_t bank0  = (uint8_t)((base | (m->inner & 0x03u)) % prg16);
    uint8_t bank1  = (uint8_t)((base | 0x03u) % prg16);
    nes_load_prgrom_16k(nes, 0, (uint16_t)bank0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)bank1);
    if (nes->nes_rom.chr_rom_size == 0u) nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper104_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper104_t* m = (mapper104_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper104_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    mapper104_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper104_t* m = (mapper104_t*)nes->nes_mapper.mapper_register;
    if (address == 0x5000u) {
        m->outer = (data >> 4u) & 0x07u;
        mapper104_update_banks(nes);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper104_t* m = (mapper104_t*)nes->nes_mapper.mapper_register;
    (void)address;
    m->inner = data & 0x03u;
    mapper104_update_banks(nes);
}

int nes_mapper104_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu    = nes_mapper_apu;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_173
 * Mapper 173 — TXC 22211C.
 * Like mapper 172 but with a rotate-right on the data byte.
 */

typedef struct {
    uint8_t regs[4];
    uint8_t reg_sel;
    uint8_t prg_bank_count;
    uint8_t chr_bank_count;
} mapper173_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper173_update_banks(nes_t* nes) {
    mapper173_t* m = (mapper173_t*)nes->nes_mapper.mapper_register;
    uint8_t prg32 = (uint8_t)(m->prg_bank_count / 4u);
    uint8_t chr8  = (uint8_t)(m->chr_bank_count / 8u);
    if (prg32 == 0u) prg32 = 1u;
    if (chr8  == 0u) chr8  = 1u;
    nes_load_prgrom_32k(nes, 0, (uint16_t)((m->regs[1] >> 2u) % prg32));
    nes_load_chrrom_8k(nes, 0, (uint8_t)((m->regs[0] >> 2u) % chr8));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper173_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper173_t* m = (mapper173_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper173_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    m->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8u);
    mapper173_update_banks(nes);
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper173_t* m = (mapper173_t*)nes->nes_mapper.mapper_register;
    if ((address & 0xFFu) == 0x00u)
        m->reg_sel = data & 0x03u;
    else if ((address & 0xFFu) == 0x01u) {
        /* rotate right by 1 bit */
        uint8_t d = (uint8_t)((data >> 1u) | (data << 7u));
        m->regs[m->reg_sel] = d;
        mapper173_update_banks(nes);
    }
}

static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    mapper173_t* m = (mapper173_t*)nes->nes_mapper.mapper_register;
    (void)address;
    uint8_t d = m->regs[0];
    return (uint8_t)((d << 1u) | (d >> 7u));  /* rotate left = undo */
}

int nes_mapper173_init(nes_t* nes) {
    nes->nes_mapper.mapper_init     = nes_mapper_init;
    nes->nes_mapper.mapper_deinit   = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu      = nes_mapper_apu;
    nes->nes_mapper.mapper_read_apu = nes_mapper_read_apu;
    return NES_OK;
}

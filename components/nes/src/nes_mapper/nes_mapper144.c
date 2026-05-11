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

/* https://www.nesdev.org/wiki/INES_Mapper_144
 * AGCI 50282 (Death Race PCB).
 * Register format (identical to mapper 11 / Color Dreams):
 *   bits[3:0] = 32KB PRG bank,  bits[7:4] = 8KB CHR bank.
 * No bus conflicts (unlike mapper 11).
 *
 * Address decode: only writes to $C000-$FFFF (A14=1) trigger the register.
 * Writes to $8000-$BFFF (A14=0) are ignored.  This prevents the startup-code
 * write of $00 to $8000 from accidentally switching PRG to bank0, while still
 * allowing the RAM trampoline ($FFBE/$FFB0 region) to switch banks freely.
 *
 * Power-on: register=0 → bank0.  Startup code immediately writes $0D to
 * $FFB0 (A14=1) → bank1.  Trampoline writes $0C/$0D to switch bank0↔bank1.
 */

typedef struct {
    uint8_t reg;
} mapper144_t;

static void mapper144_sync(nes_t* nes) {
    mapper144_t* m = (mapper144_t*)nes->nes_mapper.mapper_register;
    const uint16_t prg_count32 = (uint16_t)(nes->nes_rom.prg_rom_size >> 1u);
    if (prg_count32 > 0u) {
        nes_load_prgrom_32k(nes, 0, (uint8_t)((m->reg & 0x0Fu) % prg_count32));
    }
    if (nes->nes_rom.chr_rom_size > 0u) {
        const uint16_t chr_count = (uint16_t)nes->nes_rom.chr_rom_size;
        nes_load_chrrom_8k(nes, 0, (uint8_t)(((m->reg >> 4u) & 0x0Fu) % chr_count));
    }
}

static void nes_mapper_init(nes_t* nes) {
    mapper144_t* m = (mapper144_t*)nes_malloc(sizeof(mapper144_t));
    if (m) {
        nes_memset(m, 0, sizeof(mapper144_t));
    }
    nes->nes_mapper.mapper_register = m;
    // Power-on: register=0 → PRG bank0.  Startup immediately switches to bank1.
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0u) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
    // Death Race uses $6000-$7FFF as work RAM
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        }
    }
}

static void nes_mapper_deinit(nes_t* nes) {
    if (nes->nes_mapper.mapper_register) {
        nes_free(nes->nes_mapper.mapper_register);
        nes->nes_mapper.mapper_register = NULL;
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    // Only $C000-$FFFF (A14=1) triggers the register; $8000-$BFFF writes are ignored
    if (address < 0xC000u) return;
    mapper144_t* m = (mapper144_t*)nes->nes_mapper.mapper_register;
    if (!m) return;
    m->reg = data;
    mapper144_sync(nes);
}

int nes_mapper144_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

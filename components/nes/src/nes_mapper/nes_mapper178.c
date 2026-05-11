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
 * https://www.nesdev.org/wiki/INES_Mapper_178
 * Mapper 178 — Waixing FC-037 (大航海 / Daikoukai variant).
 *
 * Individual 8KB PRG banks are selected by writing to $6000-$6003
 * via the SRAM range (mapper_sram):
 *   $6000: 8KB PRG bank for slot 0 ($8000-$9FFF)
 *   $6001: 8KB PRG bank for slot 1 ($A000-$BFFF)
 *   $6002: 8KB PRG bank for slot 2 ($C000-$DFFF)
 *   $6003: 8KB PRG bank for slot 3 ($E000-$FFFF)
 * No IRQ.
 */

typedef struct {
    uint8_t prg[4];
    uint8_t prg_bank_count;
} mapper178_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper178_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper178_register_t* r = (mapper178_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper178_register_t));

    uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    r->prg_bank_count  = (uint8_t)prg_banks;

    r->prg[0] = 0u;
    r->prg[1] = 1u;
    r->prg[2] = (uint8_t)(prg_banks - 2u);
    r->prg[3] = (uint8_t)(prg_banks - 1u);

    nes_load_prgrom_8k(nes, 0, r->prg[0]);
    nes_load_prgrom_8k(nes, 1, r->prg[1]);
    nes_load_prgrom_8k(nes, 2, r->prg[2]);
    nes_load_prgrom_8k(nes, 3, r->prg[3]);

    nes_load_chrrom_8k(nes, 0, 0);
}

/*
 * $6000-$6003: 8KB PRG bank select for slots 0-3 (address bits[1:0] = slot)
 */
static void nes_mapper_sram(nes_t* nes, uint16_t address, uint8_t data) {
    mapper178_register_t* r = (mapper178_register_t*)nes->nes_mapper.mapper_register;
    if (address <= 0x6003u) {
        uint8_t slot = (uint8_t)(address & 0x03u);
        r->prg[slot] = data & 0x0Fu;
        nes_load_prgrom_8k(nes, slot, r->prg[slot]);
    }
}

int nes_mapper178_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_sram   = nes_mapper_sram;
    return NES_OK;
}

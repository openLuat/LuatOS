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

/* https://www.nesdev.org/wiki/INES_Mapper_232
 * Camerica Quattro — PRG outer+inner bank selection.
 * Write $8000-$BFFF: bits[4:3] = outer 32KB block (high bits of PRG bank)
 * Write $C000-$FFFF: bits[1:0] = inner 16KB bank within the selected block
 * $C000-$FFFF area: switchable 16KB; $E000-$FFFF fixed to last 16KB of block.
 * Actually: both slots are 16KB; upper slot fixed to last of block.
 */

typedef struct {
    uint8_t outer; /* bits[4:3] from $8000 write */
    uint8_t inner; /* bits[1:0] from $C000 write */
} mapper232_reg_t;

static void mapper232_update(nes_t* nes) {
    mapper232_reg_t* r = (mapper232_reg_t*)nes->nes_mapper.mapper_register;
    uint8_t base  = (uint8_t)(r->outer << 2);
    uint8_t inner = (uint8_t)(base | (r->inner & 0x03u));
    uint8_t last  = (uint8_t)(base | 0x03u);
    nes_load_prgrom_16k(nes, 0, inner);
    nes_load_prgrom_16k(nes, 1, last);
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper232_reg_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper232_reg_t* r = (mapper232_reg_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper232_reg_t));
    r->outer = 3; /* default to last block */
    mapper232_update(nes);
    nes_load_chrrom_8k(nes, 0, 0);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper232_reg_t* r = (mapper232_reg_t*)nes->nes_mapper.mapper_register;
    if (address < 0xC000u) {
        r->outer = (uint8_t)((data >> 3) & 0x03u);
    } else {
        r->inner = (uint8_t)(data & 0x03u);
    }
    mapper232_update(nes);
}

int nes_mapper232_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

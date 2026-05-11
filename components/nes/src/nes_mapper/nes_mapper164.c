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

/* https://www.nesdev.org/wiki/INES_Mapper_164 */

typedef struct {
    uint8_t prg_bank;   /* PRG 32KB bank index (bits[5:0] of $5000) */
} nes_mapper164_t;

static void mapper164_update_prg(nes_t* nes) {
    nes_mapper164_t* m = (nes_mapper164_t*)nes->nes_mapper.mapper_register;
    uint16_t prg_32k_banks = nes->nes_rom.prg_rom_size / 2; /* 16KB units -> 32KB banks */
    if (prg_32k_banks == 0) prg_32k_banks = 1;
    nes_load_prgrom_32k(nes, 0, (uint16_t)(m->prg_bank % prg_32k_banks));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper164_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper164_t* m = (nes_mapper164_t*)nes->nes_mapper.mapper_register;
    m->prg_bank = 0;

    nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        nes_load_chrrom_8k(nes, 0, 0);
    }
    mapper164_update_prg(nes);
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

/*
 * Writes to $4020-$5FFF are routed here via mapper_apu.
 * $5000: bits[5:0] = 32KB PRG bank select
 * $5300: bit[7] = mirroring (0=H, 1=V)
 */
static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper164_t* m = (nes_mapper164_t*)nes->nes_mapper.mapper_register;
    switch (address) {
    case 0x5000:
        m->prg_bank = data & 0x3F;
        mapper164_update_prg(nes);
        break;
    case 0x5300:
        nes_ppu_screen_mirrors(nes, (data & 0x80) ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
        break;
    default:
        break;
    }
}

int nes_mapper164_init(nes_t* nes) {
    nes->nes_mapper.mapper_init    = nes_mapper_init;
    nes->nes_mapper.mapper_deinit  = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu     = nes_mapper_apu;
    return NES_OK;
}

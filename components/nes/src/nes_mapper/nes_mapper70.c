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

/* https://www.nesdev.org/wiki/INES_Mapper_070 */

/*
 * Write to $8000-$FFFF:
 *   7  bit  0
 *   MPPP CCCC
 *   |||| ||||
 *   |||| ++++-- 8KB CHR bank at $0000-$1FFF
 *   |+++------- 16KB PRG bank at $8000-$BFFF; $C000-$FFFF fixed to last bank
 *   +---------- one-screen mirroring select on mapper152-style boards
 *
 * Mapper 70 is nominally hard-wired mirroring, but several iNES dumps use the
 * mapper152 wiring under mapper 70.  Match Mesen2's compatibility behavior:
 * start as vertical, then enable one-screen A/B mirroring if bit7 is ever set.
 */

typedef struct {
    uint8_t mirroring_control;
} nes_mapper70_t;

static uint8_t mapper70_uses_mirroring_control(nes_t* nes) {
    return nes->nes_rom.prg_rom_size <= 8u;
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper70_t));
        if (nes->nes_mapper.mapper_register == NULL) {
            NES_LOG_ERROR("mapper70: failed to allocate register state\n");
        }
    }

    nes_mapper70_t* m = (nes_mapper70_t*)nes->nes_mapper.mapper_register;
    if (m != NULL) {
        m->mirroring_control = 0;
    }

    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    nes_load_chrrom_8k(nes, 0, 0);
    nes_ppu_screen_mirrors(nes, mapper70_uses_mirroring_control(nes) ? NES_MIRROR_VERTICAL : NES_MIRROR_AUTO);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;

    nes_mapper70_t* m = (nes_mapper70_t*)nes->nes_mapper.mapper_register;
    uint8_t mirror_control = mapper70_uses_mirroring_control(nes);
    if (mirror_control && m != NULL) {
        if (data & 0x80u) {
            m->mirroring_control = 1;
        }
        if (m->mirroring_control) {
            nes_ppu_screen_mirrors(nes, (data & 0x80u) ? NES_MIRROR_ONE_SCREEN1 : NES_MIRROR_ONE_SCREEN0);
        }
    }

    nes_load_prgrom_16k(nes, 0, (uint16_t)((data >> 4) & (mirror_control ? 0x07u : 0x0Fu)));
    nes_load_chrrom_8k(nes, 0, (uint16_t)(data & 0x0Fu));
}

int nes_mapper70_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

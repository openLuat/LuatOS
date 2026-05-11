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
 *   PPPP CCCC
 *   |||| ||||
 *   |||| ++++-- 8KB CHR bank at $0000-$1FFF
 *   ++++------- 16KB PRG bank at $8000-$BFFF; $C000-$FFFF fixed to last bank
 *
 * Mirroring is fixed from the ROM header (no in-cart control).
 */

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    nes_load_chrrom_8k(nes, 0, 0);
    nes_ppu_screen_mirrors(nes, nes->nes_rom.mirroring_type ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    nes_load_prgrom_16k(nes, 0, ((data >> 4) & 0x0F) % nes->nes_rom.prg_rom_size);
    nes_load_chrrom_8k(nes, 0, (data & 0x0F) % nes->nes_rom.chr_rom_size);
}

int nes_mapper70_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_077
 * Napoleon Senki (Irem) — PRG 32KB fixed; CHR 2KB switchable at $0000-$07FF;
 * $0800-$1FFF is CHR-RAM.
 * Write $8000-$FFFF: bits[3:0] = 2KB CHR-ROM bank for $0000-$07FF.
 */

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_1k(nes, 0, 0);
        nes_load_chrrom_1k(nes, 1, 1);
    }
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    if (nes->nes_rom.chr_rom_size > 0) {
        uint8_t bank2k = (uint8_t)(data & 0x0Fu);
        nes_load_chrrom_1k(nes, 0, (uint8_t)(bank2k * 2u));
        nes_load_chrrom_1k(nes, 1, (uint8_t)(bank2k * 2u + 1u));
    }
}

int nes_mapper77_init(nes_t* nes) {
    nes->nes_mapper.mapper_init  = nes_mapper_init;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/INES_Mapper_013
 * CPROM — 32KB PRG-ROM fixed; PPU $0000-$0FFF = CHR-RAM bank 0 (fixed);
 * PPU $1000-$1FFF = switchable 4KB CHR-RAM bank via writes to $8000-$FFFF.
 */

#define MAPPER13_CHR_RAM_SIZE       (CHR_ROM_UNIT_SIZE * 2u)
#define MAPPER13_CHR_BANK_SIZE      0x1000u
#define MAPPER13_CHR_RAM_4K_BANKS   (MAPPER13_CHR_RAM_SIZE / MAPPER13_CHR_BANK_SIZE)

static void mapper13_map_chr_ram(nes_t* nes, uint8_t bank) {
    uint8_t* chr_ram = nes->nes_rom.chr_rom;
    if (chr_ram == NULL) {
        return;
    }

    bank = (uint8_t)(bank % MAPPER13_CHR_RAM_4K_BANKS);
    for (uint8_t i = 0; i < 4; i++) {
        nes->nes_ppu.pattern_table[i] = chr_ram + 1024u * i;
        nes->nes_ppu.pattern_table[4 + i] = chr_ram + 1024u * ((uint16_t)bank * 4u + i);
    }
}

static void mapper13_select_chr(nes_t* nes, uint8_t bank) {
    bank &= 0x03u;
    if (nes->nes_rom.chr_rom_size > 0) {
        nes_load_chrrom_4k(nes, 0, 0);
        nes_load_chrrom_4k(nes, 1, bank);
    } else {
        mapper13_map_chr_ram(nes, bank);
    }
}

static void nes_mapper_deinit(nes_t* nes) {
    if (nes->nes_mapper.mapper_data != NULL) {
        if (nes->nes_rom.chr_rom == nes->nes_mapper.mapper_data) {
            nes->nes_rom.chr_rom = NULL;
        }
        nes_free(nes->nes_mapper.mapper_data);
        nes->nes_mapper.mapper_data = NULL;
    }
}

static void nes_mapper_init(nes_t* nes) {
    nes_load_prgrom_32k(nes, 0, 0);

    if (nes->nes_rom.chr_rom_size == 0) {
        uint8_t* chr_ram = (uint8_t*)nes_malloc(MAPPER13_CHR_RAM_SIZE);
        if (chr_ram != NULL) {
            nes_memset(chr_ram, 0, MAPPER13_CHR_RAM_SIZE);
            if (nes->nes_rom.chr_rom != NULL) {
                nes_free(nes->nes_rom.chr_rom);
            }
            nes->nes_rom.chr_rom = chr_ram;
            nes->nes_mapper.mapper_data = chr_ram;
        } else {
            NES_LOG_ERROR("mapper13: failed to allocate 16KB CHR-RAM\n");
        }
    }

    mapper13_select_chr(nes, 0);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)address;
    mapper13_select_chr(nes, data);
}

int nes_mapper13_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

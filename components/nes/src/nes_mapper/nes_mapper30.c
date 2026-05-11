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

/* https://www.nesdev.org/wiki/INES_Mapper_030
 * Mapper 30 — UNROM-512 (homebrew: 32 PRG banks × 16KB, CHR-RAM 32KB).
 * Write to $8000-$FFFF:
 *   bits[4:0]: PRG 16KB bank for $8000 (fixed $C000 to last bank)
 *   bits[6:5]: CHR 8KB bank (4 banks of CHR-RAM)
 * Supports 1-screen mirroring via bit7.
 */

typedef struct {
    uint8_t prg_bank;
    uint8_t chr_bank;
    uint8_t mirror;
    uint8_t prg_bank_count;
} mapper30_t;

#define MAPPER30_CHR_RAM_SIZE  (CHR_ROM_UNIT_SIZE * 4u)
#define MAPPER30_CHR_BANK_SIZE CHR_ROM_UNIT_SIZE
#define MAPPER30_CHR_BANKS     (MAPPER30_CHR_RAM_SIZE / MAPPER30_CHR_BANK_SIZE)

static void nes_mapper_deinit(nes_t* nes) {
    if (nes->nes_mapper.mapper_data != NULL) {
        if (nes->nes_rom.chr_rom == nes->nes_mapper.mapper_data) {
            nes->nes_rom.chr_rom = NULL;
        }
        nes_free(nes->nes_mapper.mapper_data);
        nes->nes_mapper.mapper_data = NULL;
    }
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper30_map_chr_ram(nes_t* nes, uint8_t bank) {
    uint8_t* chr_ram = nes->nes_rom.chr_rom;
    if (chr_ram == NULL) {
        return;
    }

    bank = (uint8_t)(bank % MAPPER30_CHR_BANKS);
    for (uint8_t i = 0; i < 8; i++) {
        nes->nes_ppu.pattern_table[i] = chr_ram + 1024u * ((uint16_t)bank * 8u + i);
    }
}

static void mapper30_update_banks(nes_t* nes) {
    mapper30_t* m = (mapper30_t*)nes->nes_mapper.mapper_register;
    uint8_t prg16 = (uint8_t)(m->prg_bank_count / 2u);
    if (prg16 == 0u) prg16 = 1u;
    nes_load_prgrom_16k(nes, 0, (uint16_t)(m->prg_bank % prg16));
    nes_load_prgrom_16k(nes, 1, (uint16_t)(prg16 - 1u));
    if (nes->nes_rom.chr_rom_size == 0u) {
        mapper30_map_chr_ram(nes, m->chr_bank);
    } else {
        nes_load_chrrom_8k(nes, 0, m->chr_bank);
    }
    if (nes->nes_rom.four_screen == 0)
        nes_ppu_screen_mirrors(nes, m->mirror ? NES_MIRROR_ONE_SCREEN1 : NES_MIRROR_ONE_SCREEN0);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper30_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper30_t* m = (mapper30_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(mapper30_t));
    m->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2u);
    if (nes->nes_rom.chr_rom_size == 0u) {
        uint8_t* chr_ram = (uint8_t*)nes_malloc(MAPPER30_CHR_RAM_SIZE);
        if (chr_ram != NULL) {
            nes_memset(chr_ram, 0, MAPPER30_CHR_RAM_SIZE);
            if (nes->nes_rom.chr_rom != NULL) {
                nes_free(nes->nes_rom.chr_rom);
            }
            nes->nes_rom.chr_rom = chr_ram;
            nes->nes_mapper.mapper_data = chr_ram;
        } else {
            NES_LOG_ERROR("mapper30: failed to allocate 32KB CHR-RAM\n");
        }
    }
    mapper30_update_banks(nes);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper30_t* m = (mapper30_t*)nes->nes_mapper.mapper_register;
    (void)address;
    m->prg_bank = data & 0x1Fu;
    m->chr_bank = (data >> 5u) & 0x03u;
    m->mirror   = (data >> 7u) & 0x01u;
    mapper30_update_banks(nes);
}

int nes_mapper30_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

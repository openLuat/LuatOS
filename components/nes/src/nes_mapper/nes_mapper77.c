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
 * Napoleon Senki (Irem LROG017) — PRG 32KB switchable; PPU $0000-$07FF is
 * switchable 2KB CHR-ROM; PPU $0800-$1FFF is 6KB CHR-RAM; four-screen VRAM.
 * Write $8000-$FFFF: bits[3:0] = 32KB PRG bank, bits[7:4] = 2KB CHR-ROM bank.
 */

#define MAPPER77_CHR_RAM_SIZE       0x1800u
#define MAPPER77_CHR_PAGE_SIZE      0x0800u

typedef struct {
    uint8_t latch;
    uint8_t chr_ram[MAPPER77_CHR_RAM_SIZE];
} nes_mapper77_t;

static void mapper77_map_chr_ram(nes_t* nes, nes_mapper77_t* m) {
    for (uint8_t page = 0u; page < 3u; page++) {
        uint8_t* base = m->chr_ram + (uint16_t)page * MAPPER77_CHR_PAGE_SIZE;
        uint8_t slot = (uint8_t)((page + 1u) * 2u);
        nes->nes_ppu.pattern_table[slot] = base;
        nes->nes_ppu.pattern_table[slot + 1u] = base + 0x0400u;
    }
}

static void mapper77_sync(nes_t* nes) {
    nes_mapper77_t* m = (nes_mapper77_t*)nes->nes_mapper.mapper_register;
    if (m == NULL) {
        return;
    }

    nes_load_prgrom_32k(nes, 0, m->latch & 0x0Fu);

    if (nes->nes_rom.chr_rom_size > 0u) {
        uint16_t chr_bank = (uint16_t)(m->latch >> 4u) * 2u;
        nes_load_chrrom_1k(nes, 0, chr_bank);
        nes_load_chrrom_1k(nes, 1, chr_bank + 1u);
    } else {
        nes->nes_ppu.pattern_table[0] = m->chr_ram;
        nes->nes_ppu.pattern_table[1] = m->chr_ram + 0x0400u;
    }

    mapper77_map_chr_ram(nes, m);
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper77_t));
        if (nes->nes_mapper.mapper_register == NULL) {
            NES_LOG_ERROR("mapper77: failed to allocate 6KB CHR-RAM\n");
            return;
        }
    }

    nes_mapper77_t* m = (nes_mapper77_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(*m));

    mapper77_sync(nes);
    nes_ppu_screen_mirrors(nes, NES_MIRROR_FOUR_SCREEN);
}

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper77_t* m = (nes_mapper77_t*)nes->nes_mapper.mapper_register;
    if (m == NULL) {
        return;
    }

    uint8_t* bank = nes->nes_cpu.prg_banks[(address >> 13u) - 4u];
    if (bank != NULL) {
        data &= bank[address & 0x1FFFu];
    }

    m->latch = data;
    mapper77_sync(nes);
}

int nes_mapper77_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

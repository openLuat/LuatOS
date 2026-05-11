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

/* https://www.nesdev.org/wiki/MMC4 */

typedef struct {
    uint8_t prg_bank;        /* 16KB PRG bank at $8000-$BFFF */
    uint8_t chr_bank[2][2];  /* [half 0/1][latch fd=0 / latch fe=1] 4KB CHR banks */
    uint8_t latch[2];        /* current latch state per CHR half */
} nes_mapper10_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper10_update_prg(nes_t* nes) {
    nes_mapper10_t* r = (nes_mapper10_t*)nes->nes_mapper.mapper_register;
    uint16_t num_16k = nes->nes_rom.prg_rom_size;
    nes_load_prgrom_16k(nes, 0, r->prg_bank % num_16k);
    nes_load_prgrom_16k(nes, 1, num_16k - 1);
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper10_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper10_t* r = (nes_mapper10_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(*r));
    r->latch[0] = 1;
    r->latch[1] = 1;

    /* MMC4 battery-backed games use $6000-$7FFF as working RAM; allocate if not yet done */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        }
    }

    mapper10_update_prg(nes);
    nes_load_chrrom_4k(nes, 0, r->chr_bank[0][r->latch[0]]);
    nes_load_chrrom_4k(nes, 1, r->chr_bank[1][r->latch[1]]);
    nes_ppu_screen_mirrors(nes, nes->nes_rom.mirroring_type ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
}

/*
 * $A000: 16KB PRG bank at $8000-$BFFF (bits[3:0])
 * $B000: CHR 4KB bank for $0000 when latch0=0 (tile FD fetched)
 * $C000: CHR 4KB bank for $0000 when latch0=1 (tile FE fetched)
 * $D000: CHR 4KB bank for $1000 when latch1=0 (tile FD fetched)
 * $E000: CHR 4KB bank for $1000 when latch1=1 (tile FE fetched)
 * $F000: Mirroring — bit[0]: 0=vertical, 1=horizontal
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper10_t* r = (nes_mapper10_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000) {
        case 0xA000:
            r->prg_bank = data & 0x0F;
            mapper10_update_prg(nes);
            break;
        case 0xB000:
            r->chr_bank[0][0] = data & 0x1F;
            if (r->latch[0] == 0) nes_load_chrrom_4k(nes, 0, r->chr_bank[0][0]);
            break;
        case 0xC000:
            r->chr_bank[0][1] = data & 0x1F;
            if (r->latch[0] == 1) nes_load_chrrom_4k(nes, 0, r->chr_bank[0][1]);
            break;
        case 0xD000:
            r->chr_bank[1][0] = data & 0x1F;
            if (r->latch[1] == 0) nes_load_chrrom_4k(nes, 1, r->chr_bank[1][0]);
            break;
        case 0xE000:
            r->chr_bank[1][1] = data & 0x1F;
            if (r->latch[1] == 1) nes_load_chrrom_4k(nes, 1, r->chr_bank[1][1]);
            break;
        case 0xF000:
            nes_ppu_screen_mirrors(nes, (data & 1) ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
            break;
        default:
            break;
    }
}

/*
 * PPU latch — triggered after the PPU fetches the high pattern byte of tile $FD/$FE.
 * MMC4 uses ranges for both pattern halves.
 */
static void nes_mapper_ppu(nes_t* nes, uint16_t address) {
    nes_mapper10_t* r = (nes_mapper10_t*)nes->nes_mapper.mapper_register;
    if (address >= 0x0FD8u && address <= 0x0FDFu) {
        r->latch[0] = 0;
        nes_load_chrrom_4k(nes, 0, r->chr_bank[0][0]);
    } else if (address >= 0x0FE8u && address <= 0x0FEFu) {
        r->latch[0] = 1;
        nes_load_chrrom_4k(nes, 0, r->chr_bank[0][1]);
    } else if (address >= 0x1FD8u && address <= 0x1FDFu) {
        r->latch[1] = 0;
        nes_load_chrrom_4k(nes, 1, r->chr_bank[1][0]);
    } else if (address >= 0x1FE8u && address <= 0x1FEFu) {
        r->latch[1] = 1;
        nes_load_chrrom_4k(nes, 1, r->chr_bank[1][1]);
    }
}

int nes_mapper10_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    nes->nes_mapper.mapper_ppu    = nes_mapper_ppu;
    nes->nes_mapper.mapper_ppu_tile_min = 0xFD;
    nes->nes_mapper.mapper_ppu_tile_max = 0xFE;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/Sunsoft_mapper_4 */

typedef struct {
    uint8_t chr[4];      /* 2KB CHR bank indices for PPU $0000/$0800/$1000/$1800 */
    uint8_t nt_bank[2];  /* CHR ROM 1KB page indices for nametable 0 and 1 */
    uint8_t prg;         /* 16KB PRG bank at $8000 */
    uint8_t nt_from_rom; /* 1 = use CHR ROM as nametable source */
    uint8_t mirror_mode; /* 0=H, 1=V, 2=single-screen NT0, 3=single-screen NT1 */
} nes_mapper68_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static inline void mapper68_load_chr2k(nes_t* nes, uint8_t slot, uint8_t bank) {
    uint8_t num_1k = (uint8_t)(nes->nes_rom.chr_rom_size * 8);
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2),     (uint8_t)((bank * 2)     % num_1k));
    nes_load_chrrom_1k(nes, (uint8_t)(slot * 2 + 1), (uint8_t)((bank * 2 + 1) % num_1k));
}

/*
 * Apply nametable configuration. When nt_from_rom is clear, use CIRAM with
 * the selected mirroring mode. When set, redirect nametable pointers directly
 * into CHR ROM using nt_bank[0] and nt_bank[1] as 1KB page indices.
 */
static void mapper68_update_nt(nes_t* nes) {
    nes_mapper68_t* r = (nes_mapper68_t*)nes->nes_mapper.mapper_register;
    if (!r->nt_from_rom) {
        switch (r->mirror_mode) {
            case 0: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
            case 1: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
            case 2: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
            case 3: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
        }
        return;
    }

    uint16_t num_1k = (uint16_t)(nes->nes_rom.chr_rom_size * 8);
    uint8_t* p0 = nes->nes_rom.chr_rom + ((r->nt_bank[0] & 0x7F) % num_1k) * 0x400;
    uint8_t* p1 = nes->nes_rom.chr_rom + ((r->nt_bank[1] & 0x7F) % num_1k) * 0x400;
    uint8_t** nt  = nes->nes_ppu.name_table;
    uint8_t** ntm = nes->nes_ppu.name_table_mirrors;

    switch (r->mirror_mode) {
        case 0: /* Horizontal: NT0/NT1 share p0, NT2/NT3 share p1 */
            nt[0] = nt[1] = p0; nt[2] = nt[3] = p1; break;
        case 1: /* Vertical: NT0/NT2 share p0, NT1/NT3 share p1 */
            nt[0] = nt[2] = p0; nt[1] = nt[3] = p1; break;
        case 2: /* Single screen using NT bank 0 */
            nt[0] = nt[1] = nt[2] = nt[3] = p0; break;
        case 3: /* Single screen using NT bank 1 */
            nt[0] = nt[1] = nt[2] = nt[3] = p1; break;
    }
    ntm[0] = nt[0]; ntm[1] = nt[1]; ntm[2] = nt[2]; ntm[3] = nt[3];
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper68_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper68_t* r = (nes_mapper68_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(*r));

    nes_load_prgrom_16k(nes, 0, 0);
    nes_load_prgrom_16k(nes, 1, (uint16_t)(nes->nes_rom.prg_rom_size - 1));
    for (uint8_t i = 0; i < 4; i++) {
        r->chr[i] = i;
        mapper68_load_chr2k(nes, i, i);
    }
    nes_ppu_screen_mirrors(nes, nes->nes_rom.mirroring_type ? NES_MIRROR_VERTICAL : NES_MIRROR_HORIZONTAL);
}

/*
 * $8000-$8FFF: 2KB CHR bank for PPU $0000-$07FF
 * $9000-$9FFF: 2KB CHR bank for PPU $0800-$0FFF
 * $A000-$AFFF: 2KB CHR bank for PPU $1000-$17FF
 * $B000-$BFFF: 2KB CHR bank for PPU $1800-$1FFF
 * $C000-$CFFF: NT CHR ROM bank 0 (1KB page index, bit[7] forced set)
 * $D000-$DFFF: NT CHR ROM bank 1
 * $E000-$EFFF: bits[1:0]=mirror mode (0=H,1=V,2=NT0,3=NT1); bit[4]=CHR ROM NT enable
 * $F000-$FFFF: bits[3:0]=16KB PRG bank at $8000; $C000-$FFFF fixed to last bank
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper68_t* r = (nes_mapper68_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF000) {
        case 0x8000:
            r->chr[0] = data;
            mapper68_load_chr2k(nes, 0, data);
            break;
        case 0x9000:
            r->chr[1] = data;
            mapper68_load_chr2k(nes, 1, data);
            break;
        case 0xA000:
            r->chr[2] = data;
            mapper68_load_chr2k(nes, 2, data);
            break;
        case 0xB000:
            r->chr[3] = data;
            mapper68_load_chr2k(nes, 3, data);
            break;
        case 0xC000:
            r->nt_bank[0] = data | 0x80;
            if (r->nt_from_rom) mapper68_update_nt(nes);
            break;
        case 0xD000:
            r->nt_bank[1] = data | 0x80;
            if (r->nt_from_rom) mapper68_update_nt(nes);
            break;
        case 0xE000:
            r->mirror_mode = data & 0x03;
            r->nt_from_rom = (data >> 4) & 1;
            mapper68_update_nt(nes);
            break;
        case 0xF000:
            r->prg = data & 0x0F;
            nes_load_prgrom_16k(nes, 0, r->prg % nes->nes_rom.prg_rom_size);
            break;
        default:
            break;
    }
}

int nes_mapper68_init(nes_t* nes) {
    nes->nes_mapper.mapper_init   = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write  = nes_mapper_write;
    return NES_OK;
}

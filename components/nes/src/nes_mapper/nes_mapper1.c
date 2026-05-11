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
#include "nes_mapper.h"

/* https://www.nesdev.org/wiki/MMC1 */


typedef struct  {
    uint8_t shift;
    uint8_t prg_bank;   /* last PRG bank register value, for re-applying when P mode changes */
    union {
        struct {
            uint8_t M:2;
            uint8_t P:2;
            uint8_t C:1;
            uint8_t  :3;
        }control;
        uint8_t control_byte;
    };
} mapper1_register_t;

/* MMC1 M-field to NES mirror type.
   MMC1: 0=one-screen-lower, 1=one-screen-upper, 2=vertical, 3=horizontal */
static const nes_mirror_type_t nes_mapper1_mirror_table[4] = {
    NES_MIRROR_ONE_SCREEN0,  /* M=0 */
    NES_MIRROR_ONE_SCREEN1,  /* M=1 */
    NES_MIRROR_VERTICAL,     /* M=2 */
    NES_MIRROR_HORIZONTAL,   /* M=3 */
};


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
    /* Free WRAM regardless of who allocated it; callers check for NULL before freeing. */
    if (nes->nes_rom.sram) {
        nes_free(nes->nes_rom.sram);
        nes->nes_rom.sram = NULL;
    }
}

static void nes_mapper_init(nes_t* nes){
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper1_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    // CPU $6000-$7FFF: 8 KB PRG-RAM bank, (optional)
    /* MMC1 cartridges always have 8 KB WRAM at $6000-$7FFF, even without battery.
       Allocate here if the ROM loader did not (e.g., when NES_USE_SRAM=0). */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) {
            /* Initialize WRAM to 0x00 (safe default for SRAM work variables).
               Battery-backed SRAM doubles as work RAM; zero-initializing avoids
               stale 0xFF bytes being interpreted as CHR bank indices by the NMI. */
            nes_memset(nes->nes_rom.sram, 0x00, SRAM_SIZE);
        }
    }

    // CPU $8000-$BFFF: 16 KB PRG-ROM bank, either switchable or fixed to the first bank
    nes_load_prgrom_16k(nes, 0, 0);
    // CPU $C000-$FFFF: 16 KB PRG-ROM bank, either fixed to the last bank or switchable
    nes_load_prgrom_16k(nes, 1, nes->nes_rom.prg_rom_size - 1);

    // PPU $0000-$0FFF: 4 KB switchable CHR bank
    // PPU $1000-$1FFF: 4 KB switchable CHR bank

    // CHR capacity:
    nes_load_chrrom_8k(nes, 0, 0);

    nes_memset(r, 0x00, sizeof(mapper1_register_t));
    r->shift = 0x10;
    /* Power-on: Control=$0C (P=3: fix last PRG bank at $C000; C=0: 8K CHR; M=0: one-screen) */
    r->control_byte = 0x0C;
}

/* Apply PRG bank mapping using the stored prg_bank value and current P mode. */
static inline void nes_mapper_apply_prgbank(nes_t* nes) {
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    const uint8_t bankid = r->prg_bank;
    switch (r->control.P) {
    case 0: case 1:
        /* 32 KB mode – switch both banks together; src is a 32 KB block index */
        nes_load_prgrom_32k(nes, 0, bankid >> 1);
        break;
    case 2:
        /* Fix first bank at $8000 and switch 16 KB bank at $C000 */
        nes_load_prgrom_16k(nes, 0, 0);
        nes_load_prgrom_16k(nes, 1, bankid);
        break;
    case 3:
        /* Fix last bank at $C000 and switch 16 KB bank at $8000 */
        nes_load_prgrom_16k(nes, 0, bankid);
        nes_load_prgrom_16k(nes, 1, nes->nes_rom.prg_rom_size - 1);
        break;
    }
}

static inline void nes_mapper_write_control(nes_t* nes, uint8_t data) {
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    const uint8_t old_p = r->control.P;
    r->control_byte = data;
    nes_ppu_screen_mirrors(nes, nes_mapper1_mirror_table[r->control.M]);
    /* Re-apply PRG bank mapping when P (PRG banking mode) changes. */
    if (r->control.P != old_p) {
        nes_mapper_apply_prgbank(nes);
    }
}
/*
CHR bank 0 (internal, $A000-$BFFF)
    4bit0
    -----
    CCCCC
    |||||
    +++++- Select 4 KB or 8 KB CHR bank at PPU $0000 (low bit ignored in 8 KB mode)
*/
static inline void nes_mapper_write_chrbank0(nes_t* nes) {
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    if (r->control.C) {
        nes_load_chrrom_4k(nes, 0, r->shift);
    } else {
        nes_load_chrrom_8k(nes, 0, r->shift >> 1);
    }
}
/*
CHR bank 1 (internal, $C000-$DFFF)
    4bit0
    -----
    CCCCC
    |||||
    +++++- Select 4 KB CHR bank at PPU $1000 (ignored in 8 KB mode)
*/
static inline void nes_mapper_write_chrbank1(nes_t* nes) {
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    if (r->control.C) 
        nes_load_chrrom_4k(nes, 1, r->shift);
}
/*
PRG bank (internal, $E000-$FFFF)
    4bit0
    -----
    RPPPP
    |||||
    |++++- Select 16 KB PRG-ROM bank (low bit ignored in 32 KB mode)
    +----- MMC1B and later: PRG-RAM chip enable (0: enabled; 1: disabled; ignored on MMC1A)
        MMC1A: Bit 3 bypasses fixed bank logic in 16K mode (0: fixed bank affects A17-A14;
        1: fixed bank affects A16-A14 and bit 3 directly controls A17)
*/
static inline void nes_mapper_write_prgbank(nes_t* nes) {
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    r->prg_bank = r->shift & (uint8_t)0x0F;
    nes_mapper_apply_prgbank(nes);
}

static inline void nes_mapper_write_register(nes_t* nes, uint16_t address) {
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    switch ((address & 0x7FFF) >> 13){
    case 0:
        nes_mapper_write_control(nes, r->shift);
        break;
    case 1:
        nes_mapper_write_chrbank0(nes);
        break;
    case 2:
        nes_mapper_write_chrbank1(nes);
        break;
    case 3:
        nes_mapper_write_prgbank(nes);
        break;
    }
}
/*
Load register ($8000-$FFFF)
    7  bit  0
    ---- ----
    Rxxx xxxD
    |       |
    |       +- Data bit to be shifted into shift register, LSB first
    +--------- A write with bit set will reset shift register
                and write Control with (Control OR $0C), 
                locking PRG-ROM at $C000-$FFFF to the last bank.
*/
static void nes_mapper_write(nes_t* nes, uint16_t write_addr, uint8_t data){
    mapper1_register_t* r = (mapper1_register_t*)nes->nes_mapper.mapper_register;
    if (data & (uint8_t)0x80){
        r->shift = 0x10; // reset shift register
        // Control = Control OR $0C, locking PRG-ROM at $C000-$FFFF to the last bank
        r->control_byte |= 0x0C;
        nes_ppu_screen_mirrors(nes, nes_mapper1_mirror_table[r->control.M]);
        /* P is now forced to 3; re-apply PRG bank in the new mode. */
        nes_mapper_apply_prgbank(nes);
    }else {
        const uint8_t finished = r->shift & 1;
        r->shift >>= 1;
        r->shift |= (data & 1) << 4;
        if (finished) {
            nes_mapper_write_register(nes, write_addr);
            r->shift = 0x10;
        }
    }
}

int nes_mapper1_init(nes_t* nes){
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/MMC3 */

typedef struct {
    uint8_t bank_select;    /* $8000: Bank select register */
    uint8_t bank_values[8]; /* R0-R7 bank data values */
    uint8_t mirroring;      /* $A000: Mirroring */
    uint8_t prg_ram_protect;/* $A001: PRG RAM protect */
    uint8_t irq_latch;      /* $C000: IRQ latch value */
    uint8_t irq_counter;    /* Current IRQ counter */
    uint8_t irq_reload;     /* Flag: reload counter on next scanline */
    uint8_t irq_enabled;    /* $E001: IRQ enabled */
    uint8_t prg_bank_count; /* Number of 8KB PRG banks */
    uint8_t chr_bank_count; /* Number of 1KB CHR banks */
} mapper4_register_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void mapper4_update_banks(nes_t* nes) {
    mapper4_register_t* mapper_reg = (mapper4_register_t*)nes->nes_mapper.mapper_register;
    uint8_t prg_mode = (mapper_reg->bank_select >> 6) & 1;
    uint8_t chr_mode = (mapper_reg->bank_select >> 7) & 1;

    /* PRG banking:
     * Mode 0: $8000-$9FFF swappable, $C000-$DFFF fixed to second-last bank
     * Mode 1: $C000-$DFFF swappable, $8000-$9FFF fixed to second-last bank
     * $A000-$BFFF is always R7, $E000-$FFFF is always last bank
     */
    uint8_t last_bank = mapper_reg->prg_bank_count - 1;
    uint8_t second_last = mapper_reg->prg_bank_count - 2;

    if (prg_mode == 0) {
        nes_load_prgrom_8k(nes, 0, mapper_reg->bank_values[6] % mapper_reg->prg_bank_count);
        nes_load_prgrom_8k(nes, 1, mapper_reg->bank_values[7] % mapper_reg->prg_bank_count);
        nes_load_prgrom_8k(nes, 2, second_last);
        nes_load_prgrom_8k(nes, 3, last_bank);
    } else {
        nes_load_prgrom_8k(nes, 0, second_last);
        nes_load_prgrom_8k(nes, 1, mapper_reg->bank_values[7] % mapper_reg->prg_bank_count);
        nes_load_prgrom_8k(nes, 2, mapper_reg->bank_values[6] % mapper_reg->prg_bank_count);
        nes_load_prgrom_8k(nes, 3, last_bank);
    }

    /* CHR banking:
     * Mode 0: 2KB banks at $0000/$0800, 1KB banks at $1000/$1400/$1800/$1C00
     * Mode 1: 1KB banks at $0000/$0400/$0800/$0C00, 2KB banks at $1000/$1800
     */
    if (nes->nes_rom.chr_rom_size == 0) {
        return; /* CHR-RAM, no banking needed */
    }

    if (chr_mode == 0) {
        /* R0: 2KB at $0000 (low bit ignored) */
        nes_load_chrrom_1k(nes, 0, (mapper_reg->bank_values[0] & 0xFE) % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 1, (mapper_reg->bank_values[0] | 0x01) % mapper_reg->chr_bank_count);
        /* R1: 2KB at $0800 (low bit ignored) */
        nes_load_chrrom_1k(nes, 2, (mapper_reg->bank_values[1] & 0xFE) % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 3, (mapper_reg->bank_values[1] | 0x01) % mapper_reg->chr_bank_count);
        /* R2-R5: 1KB at $1000-$1C00 */
        nes_load_chrrom_1k(nes, 4, mapper_reg->bank_values[2] % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 5, mapper_reg->bank_values[3] % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 6, mapper_reg->bank_values[4] % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 7, mapper_reg->bank_values[5] % mapper_reg->chr_bank_count);
    } else {
        /* R2-R5: 1KB at $0000-$0C00 */
        nes_load_chrrom_1k(nes, 0, mapper_reg->bank_values[2] % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 1, mapper_reg->bank_values[3] % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 2, mapper_reg->bank_values[4] % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 3, mapper_reg->bank_values[5] % mapper_reg->chr_bank_count);
        /* R0: 2KB at $1000 (low bit ignored) */
        nes_load_chrrom_1k(nes, 4, (mapper_reg->bank_values[0] & 0xFE) % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 5, (mapper_reg->bank_values[0] | 0x01) % mapper_reg->chr_bank_count);
        /* R1: 2KB at $1800 (low bit ignored) */
        nes_load_chrrom_1k(nes, 6, (mapper_reg->bank_values[1] & 0xFE) % mapper_reg->chr_bank_count);
        nes_load_chrrom_1k(nes, 7, (mapper_reg->bank_values[1] | 0x01) % mapper_reg->chr_bank_count);
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper4_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper4_register_t* mapper_reg = (mapper4_register_t*)nes->nes_mapper.mapper_register;
    mapper_reg->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2); /* 16KB units -> 8KB units */
    mapper_reg->chr_bank_count = (uint8_t)(nes->nes_rom.chr_rom_size * 8); /* 8KB units -> 1KB units */

    mapper_reg->bank_select = 0;
    mapper_reg->mirroring = 0;
    mapper_reg->prg_ram_protect = 0;
    mapper_reg->irq_latch = 0;
    mapper_reg->irq_counter = 0;
    mapper_reg->irq_reload = 0;
    mapper_reg->irq_enabled = 0;

    for (int i = 0; i < 8; i++) {
        mapper_reg->bank_values[i] = 0;
    }

    /* Default: last two PRG banks at $C000-$FFFF */
    mapper_reg->bank_values[6] = 0;
    mapper_reg->bank_values[7] = 1;

    /* CHR-RAM: set up pattern table pointers before bank update */
    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }

    mapper4_update_banks(nes);
}

/*
 * $8000-$9FFE (even): Bank select
 *   7  bit  0
 *   CPxx xRRR
 *   ||    |||
 *   ||    +++- Specify which bank register to update on next write to Bank Data register
 *   |+------- PRG ROM bank mode (0: $8000-$9FFF swappable, $C000-$DFFF fixed to second-last bank;
 *   |                             1: $C000-$DFFF swappable, $8000-$9FFF fixed to second-last bank)
 *   +-------- CHR A12 inversion (0: two 2 KB banks at $0000-$0FFF, four 1 KB banks at $1000-$1FFF;
 *                                 1: two 2 KB banks at $1000-$1FFF, four 1 KB banks at $0000-$0FFF)
 *
 * $8001-$9FFF (odd): Bank data
 * $A000-$BFFE (even): Mirroring
 * $A001-$BFFF (odd): PRG RAM protect
 * $C000-$DFFE (even): IRQ latch
 * $C001-$DFFF (odd): IRQ reload
 * $E000-$FFFE (even): IRQ disable
 * $E001-$FFFF (odd): IRQ enable
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper4_register_t* mapper_reg = (mapper4_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xE001) {
    case 0x8000: /* Bank select */
        mapper_reg->bank_select = data;
        mapper4_update_banks(nes);
        break;
    case 0x8001: /* Bank data */
        {
            uint8_t reg = mapper_reg->bank_select & 0x07;
            mapper_reg->bank_values[reg] = data;
            mapper4_update_banks(nes);
        }
        break;
    case 0xA000: /* Mirroring */
        mapper_reg->mirroring = data & 1;
        if (nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes, mapper_reg->mirroring ? NES_MIRROR_HORIZONTAL : NES_MIRROR_VERTICAL);
        }
        break;
    case 0xA001: /* PRG RAM protect */
        mapper_reg->prg_ram_protect = data;
        break;
    case 0xC000: /* IRQ latch */
        mapper_reg->irq_latch = data;
        break;
    case 0xC001: /* IRQ reload */
        mapper_reg->irq_reload = 1;
        break;
    case 0xE000: /* IRQ disable + acknowledge */
        mapper_reg->irq_enabled = 0;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0xE001: /* IRQ enable */
        mapper_reg->irq_enabled = 1;
        break;
    }
}

/*
 * MMC3 scanline counter (NESdev accurate):
 * IRQ fires ONLY when the counter decrements to 0, not when it reloads to 0.
 * With latch=0: reload always produces counter=0 but does NOT trigger IRQ.
 * https://www.nesdev.org/wiki/MMC3#IRQ_Specifics
 */
static void nes_mapper_hsync(nes_t* nes) {
    mapper4_register_t* mapper_reg = (mapper4_register_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) {
        return; /* Rendering disabled, counter not clocked */
    }

    if (mapper_reg->irq_counter == 0 || mapper_reg->irq_reload) {
        mapper_reg->irq_counter = mapper_reg->irq_latch;
        mapper_reg->irq_reload = 0;
        /* reload to 0 does NOT fire IRQ */
    } else {
        mapper_reg->irq_counter--;
        if (mapper_reg->irq_counter == 0 && mapper_reg->irq_enabled) {
            nes_cpu_irq(nes);
        }
    }
}

int nes_mapper4_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_hsync = nes_mapper_hsync;
    return NES_OK;
}

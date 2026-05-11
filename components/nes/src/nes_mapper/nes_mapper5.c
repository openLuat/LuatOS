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

/* https://www.nesdev.org/wiki/MMC5 */

typedef struct {
    uint8_t prg_mode;           /* $5100: PRG banking mode (0-3) */
    uint8_t chr_mode;           /* $5101: CHR banking mode (0-3) */
    uint8_t prg_ram_protect1;   /* $5102: PRG RAM protect 1 */
    uint8_t prg_ram_protect2;   /* $5103: PRG RAM protect 2 */
    uint8_t exram_mode;         /* $5104: ExRAM mode (0-3) */
    uint8_t nametable_mapping;  /* $5105: Nametable mapping */
    uint8_t fill_tile;          /* $5106: Fill mode tile */
    uint8_t fill_attr;          /* $5107: Fill mode color (bits 0-1) */
    uint8_t prg_bank[5];       /* $5113-$5117: PRG bank registers */
    uint8_t chr_bank_spr[8];   /* $5120-$5127: CHR bank registers for sprites */
    uint8_t chr_bank_bg[4];    /* $5128-$512B: CHR bank registers for background */
    uint8_t chr_hi;            /* $5130: Upper CHR bank bits (not used for 8-bit banks) */
    uint8_t irq_target;        /* $5203: IRQ scanline compare value */
    uint8_t irq_enabled;       /* $5204 bit 7: IRQ enabled */
    uint8_t irq_pending;       /* IRQ pending flag */
    uint8_t in_frame;          /* Whether PPU is in frame */
    uint8_t scanline_counter;  /* Internal scanline counter */
    uint8_t mul_a;             /* $5205: Multiplier operand A */
    uint8_t mul_b;             /* $5206: Multiplier operand B */
    uint8_t last_chr_write;    /* 0=sprite ($5120-$5127), 1=bg ($5128-$512B) */
    uint8_t last_chr_render;   /* 0=sprite, 1=bg, 0xFF=unknown */
    uint8_t prg_bank_count;    /* Number of 8KB PRG ROM banks */
    uint8_t chr_bank_count;    /* Number of 1KB CHR ROM banks (capped at 255) */
    uint8_t exram[1024];       /* 1KB ExRAM ($5C00-$5FFF) */
    uint8_t fill_nt[1024];     /* Fill-mode nametable */
} mapper5_register_t;


static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
    nes->nes_mapper.mapper_exram = NULL;
    nes->nes_mapper.mapper_chr_hi = 0;
}

static void mapper5_update_fill_nt(mapper5_register_t* mapper_reg) {
    nes_memset(mapper_reg->fill_nt, mapper_reg->fill_tile, 960);
    uint8_t attr = mapper_reg->fill_attr & 3;
    attr = attr | (attr << 2) | (attr << 4) | (attr << 6);
    nes_memset(mapper_reg->fill_nt + 960, attr, 64);
}

static void mapper5_update_nametables(nes_t* nes) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    for (int i = 0; i < 4; i++) {
        uint8_t sel = (mapper_reg->nametable_mapping >> (i * 2)) & 3;
        switch (sel) {
            case 0: nes->nes_ppu.name_table[i] = nes->nes_ppu.ppu_vram[0]; break;
            case 1: nes->nes_ppu.name_table[i] = nes->nes_ppu.ppu_vram[1]; break;
            case 2: nes->nes_ppu.name_table[i] = mapper_reg->exram; break;
            case 3: nes->nes_ppu.name_table[i] = mapper_reg->fill_nt; break;
        }
        nes->nes_ppu.name_table_mirrors[i] = nes->nes_ppu.name_table[i];
    }
}

static void mapper5_update_prg(nes_t* nes) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    uint8_t count = mapper_reg->prg_bank_count;
    if (count == 0) count = 1;

    switch (mapper_reg->prg_mode) {
        case 0: { /* 1 x 32KB switchable ($8000-$FFFF) from $5117 */
            uint8_t bank = (mapper_reg->prg_bank[4] & 0x7C);
            nes_load_prgrom_8k(nes, 0, bank % count);
            nes_load_prgrom_8k(nes, 1, (uint16_t)(bank + 1) % count);
            nes_load_prgrom_8k(nes, 2, (uint16_t)(bank + 2) % count);
            nes_load_prgrom_8k(nes, 3, (uint16_t)(bank + 3) % count);
            break;
        }
        case 1: { /* 2 x 16KB ($8000-$BFFF, $C000-$FFFF) */
            if (mapper_reg->prg_bank[2] & 0x80) {
                uint8_t bank = (mapper_reg->prg_bank[2] & 0x7E);
                nes_load_prgrom_8k(nes, 0, bank % count);
                nes_load_prgrom_8k(nes, 1, (uint16_t)(bank + 1) % count);
            }
            {
                uint8_t bank = (mapper_reg->prg_bank[4] & 0x7E);
                nes_load_prgrom_8k(nes, 2, bank % count);
                nes_load_prgrom_8k(nes, 3, (uint16_t)(bank + 1) % count);
            }
            break;
        }
        case 2: { /* 16KB + 8KB + 8KB */
            if (mapper_reg->prg_bank[2] & 0x80) {
                uint8_t bank = (mapper_reg->prg_bank[2] & 0x7E);
                nes_load_prgrom_8k(nes, 0, bank % count);
                nes_load_prgrom_8k(nes, 1, (uint16_t)(bank + 1) % count);
            }
            if (mapper_reg->prg_bank[3] & 0x80) {
                nes_load_prgrom_8k(nes, 2, (mapper_reg->prg_bank[3] & 0x7F) % count);
            }
            nes_load_prgrom_8k(nes, 3, (mapper_reg->prg_bank[4] & 0x7F) % count);
            break;
        }
        case 3: { /* 4 x 8KB */
            for (int i = 0; i < 4; i++) {
                uint8_t reg = mapper_reg->prg_bank[i + 1];
                if (i == 3 || (reg & 0x80)) {
                    nes_load_prgrom_8k(nes, (uint8_t)i, (reg & 0x7F) % count);
                }
            }
            break;
        }
    }
}

static void mapper5_apply_chr_sprite(nes_t* nes) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    uint8_t count = mapper_reg->chr_bank_count;
    if (count == 0) return; /* CHR-RAM, no banking */

    switch (mapper_reg->chr_mode) {
        case 0: { /* 8KB from $5127 */
            uint8_t base = (uint8_t)(mapper_reg->chr_bank_spr[7] * 8);
            for (int i = 0; i < 8; i++)
                nes_load_chrrom_1k(nes, (uint8_t)i, (uint8_t)((base + i) % count));
            break;
        }
        case 1: { /* 4KB from $5123, $5127 */
            uint8_t base0 = (uint8_t)(mapper_reg->chr_bank_spr[3] * 4);
            uint8_t base1 = (uint8_t)(mapper_reg->chr_bank_spr[7] * 4);
            for (int i = 0; i < 4; i++)
                nes_load_chrrom_1k(nes, (uint8_t)i, (uint8_t)((base0 + i) % count));
            for (int i = 0; i < 4; i++)
                nes_load_chrrom_1k(nes, (uint8_t)(4 + i), (uint8_t)((base1 + i) % count));
            break;
        }
        case 2: { /* 2KB from $5121, $5123, $5125, $5127 */
            for (int j = 0; j < 4; j++) {
                uint8_t base = (uint8_t)(mapper_reg->chr_bank_spr[j * 2 + 1] * 2);
                nes_load_chrrom_1k(nes, (uint8_t)(j * 2), (uint8_t)(base % count));
                nes_load_chrrom_1k(nes, (uint8_t)(j * 2 + 1), (uint8_t)((base + 1) % count));
            }
            break;
        }
        case 3: { /* 1KB from $5120-$5127 */
            for (int i = 0; i < 8; i++)
                nes_load_chrrom_1k(nes, (uint8_t)i, (uint8_t)(mapper_reg->chr_bank_spr[i] % count));
            break;
        }
    }
}

static void mapper5_apply_chr_bg(nes_t* nes) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    uint8_t count = mapper_reg->chr_bank_count;
    if (count == 0) return; /* CHR-RAM, no banking */

    switch (mapper_reg->chr_mode) {
        case 0: { /* 8KB from $512B */
            uint8_t base = (uint8_t)(mapper_reg->chr_bank_bg[3] * 8);
            for (int i = 0; i < 8; i++)
                nes_load_chrrom_1k(nes, (uint8_t)i, (uint8_t)((base + i) % count));
            break;
        }
        case 1: { /* 4KB from $512B, duplicated to both halves */
            uint8_t base = (uint8_t)(mapper_reg->chr_bank_bg[3] * 4);
            for (int i = 0; i < 4; i++) {
                uint8_t bank = (uint8_t)((base + i) % count);
                nes_load_chrrom_1k(nes, (uint8_t)i, bank);
                nes_load_chrrom_1k(nes, (uint8_t)(4 + i), bank);
            }
            break;
        }
        case 2: { /* 2KB from $5129, $512B, duplicated */
            uint8_t base0 = (uint8_t)(mapper_reg->chr_bank_bg[1] * 2);
            uint8_t base1 = (uint8_t)(mapper_reg->chr_bank_bg[3] * 2);
            nes_load_chrrom_1k(nes, 0, (uint8_t)(base0 % count));
            nes_load_chrrom_1k(nes, 1, (uint8_t)((base0 + 1) % count));
            nes_load_chrrom_1k(nes, 2, (uint8_t)(base1 % count));
            nes_load_chrrom_1k(nes, 3, (uint8_t)((base1 + 1) % count));
            nes_load_chrrom_1k(nes, 4, (uint8_t)(base0 % count));
            nes_load_chrrom_1k(nes, 5, (uint8_t)((base0 + 1) % count));
            nes_load_chrrom_1k(nes, 6, (uint8_t)(base1 % count));
            nes_load_chrrom_1k(nes, 7, (uint8_t)((base1 + 1) % count));
            break;
        }
        case 3: { /* 1KB from $5128-$512B, mirrored to upper half */
            for (int i = 0; i < 4; i++) {
                uint8_t bank = (uint8_t)(mapper_reg->chr_bank_bg[i] % count);
                nes_load_chrrom_1k(nes, (uint8_t)i, bank);
                nes_load_chrrom_1k(nes, (uint8_t)(4 + i), bank);
            }
            break;
        }
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper5_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(mapper_reg, 0, sizeof(*mapper_reg));

    mapper_reg->prg_bank_count = (uint8_t)(nes->nes_rom.prg_rom_size * 2);
    uint16_t chr_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8);
    mapper_reg->chr_bank_count = (chr_count > 255) ? 255 : (uint8_t)chr_count;

    /* Allocate WRAM if not already present */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        }
    }

    /* Default PRG mode 3, all banks point to last bank */
    mapper_reg->prg_mode = 3;
    mapper_reg->prg_bank[4] = 0xFF; /* $5117: last bank, ROM */
    mapper_reg->prg_bank[3] = 0xFF;
    mapper_reg->prg_bank[2] = 0xFF;
    mapper_reg->prg_bank[1] = 0x80;

    /* Default CHR mode 0 */
    mapper_reg->chr_mode = 0;
    mapper_reg->last_chr_render = 0xFF;

    /* Default nametable mapping based on ROM header mirroring type */
    if (nes->nes_rom.mirroring_type) {
        mapper_reg->nametable_mapping = 0x44; /* 0,1,0,1 = vertical */
    } else {
        mapper_reg->nametable_mapping = 0x50; /* 0,0,1,1 = horizontal */
    }

    /* Setup fill nametable */
    mapper5_update_fill_nt(mapper_reg);

    /* CHR-RAM: set up pattern table pointers */
    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }

    mapper5_update_prg(nes);
    mapper5_apply_chr_sprite(nes);
    mapper5_update_nametables(nes);

    nes->nes_mapper.mapper_exram = (mapper_reg->exram_mode == 1) ? mapper_reg->exram : NULL;
    nes->nes_mapper.mapper_chr_hi = mapper_reg->chr_hi;
}

/* Handle writes to $5000-$5FFF */
static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    if (address >= 0x5C00 && address <= 0x5FFF) {
        /* ExRAM write: modes 0/1/2 all accept writes; mode 3 is read-only.
         * Real hardware zeros writes in modes 0/1 when not rendering, but that
         * requires precise PPU-read-based in_frame detection. Accept writes
         * unconditionally for compatibility with games that initialize ExRAM
         * while rendering is disabled. */
        if (mapper_reg->exram_mode <= 2) {
            mapper_reg->exram[address & 0x3FF] = data;
        }
        /* Mode 3: read-only, writes ignored */
        return;
    }

    switch (address) {
        case 0x5100: /* PRG mode */
            mapper_reg->prg_mode = data & 3;
            mapper5_update_prg(nes);
            break;
        case 0x5101: /* CHR mode */
            mapper_reg->chr_mode = data & 3;
            mapper_reg->last_chr_render = 0xFF;
            if (mapper_reg->last_chr_write == 0)
                mapper5_apply_chr_sprite(nes);
            else
                mapper5_apply_chr_bg(nes);
            break;
        case 0x5102: /* PRG RAM protect 1 */
            mapper_reg->prg_ram_protect1 = data & 3;
            break;
        case 0x5103: /* PRG RAM protect 2 */
            mapper_reg->prg_ram_protect2 = data & 3;
            break;
        case 0x5104: /* ExRAM mode */
            mapper_reg->exram_mode = data & 3;
            nes->nes_mapper.mapper_exram = (mapper_reg->exram_mode == 1) ? mapper_reg->exram : NULL;
            break;
        case 0x5105: /* Nametable mapping */
            mapper_reg->nametable_mapping = data;
            mapper5_update_nametables(nes);
            break;
        case 0x5106: /* Fill-mode tile */
            mapper_reg->fill_tile = data;
            mapper5_update_fill_nt(mapper_reg);
            break;
        case 0x5107: /* Fill-mode color */
            mapper_reg->fill_attr = data & 3;
            mapper5_update_fill_nt(mapper_reg);
            break;

        case 0x5113: /* PRG bank for $6000-$7FFF (RAM only) */
            mapper_reg->prg_bank[0] = data;
            break;
        case 0x5114: case 0x5115: case 0x5116: case 0x5117:
            mapper_reg->prg_bank[address - 0x5113] = data;
            mapper5_update_prg(nes);
            break;

        case 0x5120: case 0x5121: case 0x5122: case 0x5123:
        case 0x5124: case 0x5125: case 0x5126: case 0x5127:
            mapper_reg->chr_bank_spr[address - 0x5120] = data;
            mapper_reg->last_chr_write = 0;
            mapper_reg->last_chr_render = 0xFF;
            mapper5_apply_chr_sprite(nes);
            break;
        case 0x5128: case 0x5129: case 0x512A: case 0x512B:
            mapper_reg->chr_bank_bg[address - 0x5128] = data;
            mapper_reg->last_chr_write = 1;
            mapper_reg->last_chr_render = 0xFF;
            mapper5_apply_chr_bg(nes);
            break;

        case 0x5130: /* Upper CHR bank bits */
            mapper_reg->chr_hi = data & 3;
            nes->nes_mapper.mapper_chr_hi = data & 3;
            break;

        case 0x5203: /* IRQ target scanline */
            mapper_reg->irq_target = data;
            break;
        case 0x5204: /* IRQ enable */
            mapper_reg->irq_enabled = data & 0x80;
            break;

        case 0x5205: /* Multiplier operand A */
            mapper_reg->mul_a = data;
            break;
        case 0x5206: /* Multiplier operand B */
            mapper_reg->mul_b = data;
            break;

        default:
            break;
    }
}

/* Handle reads from $5000-$5FFF */
static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    if (address >= 0x5C00 && address <= 0x5FFF) {
        /* ExRAM always CPU-readable regardless of mode */
        return mapper_reg->exram[address & 0x3FF];
    }

    switch (address) {
        case 0x5204: { /* IRQ status */
            uint8_t result = 0;
            if (mapper_reg->irq_pending) result |= 0x80;
            if (mapper_reg->in_frame) result |= 0x40;
            mapper_reg->irq_pending = 0;
            nes->nes_cpu.irq_pending = 0; /* acknowledge: de-assert CPU IRQ line */
            return result;
        }
        case 0x5205: { /* Multiplier result low */
            uint16_t product = (uint16_t)mapper_reg->mul_a * mapper_reg->mul_b;
            return (uint8_t)(product & 0xFF);
        }
        case 0x5206: { /* Multiplier result high */
            uint16_t product = (uint16_t)mapper_reg->mul_a * mapper_reg->mul_b;
            return (uint8_t)(product >> 8);
        }
        default:
            break;
    }
    return 0;
}

/* Writes to $8000-$FFFF: MMC5 uses these for PRG-RAM writes only */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)nes;
    (void)address;
    (void)data;
}

/* Called per visible scanline for scanline counter / IRQ */
static void nes_mapper_hsync(nes_t* nes) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) {
        mapper_reg->in_frame = 0;
        mapper_reg->scanline_counter = 0;
        return;
    }

    mapper_reg->in_frame = 1;

    /* Compare BEFORE incrementing so that target 0 is reachable */
    if (mapper_reg->scanline_counter == mapper_reg->irq_target) {
        mapper_reg->irq_pending = 1;
        if (mapper_reg->irq_enabled) {
            nes_cpu_irq(nes);
        }
    }
    mapper_reg->scanline_counter++;
}

/* Called at VSync: reset scanline counter */
static void nes_mapper_vsync(nes_t* nes) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    mapper_reg->in_frame = 0;
    mapper_reg->scanline_counter = 0;
}

/* Called before BG (mode=1) or sprite (mode=0) rendering */
static void nes_mapper_render_screen(nes_t* nes, uint8_t mode) {
    mapper5_register_t* mapper_reg = (mapper5_register_t*)nes->nes_mapper.mapper_register;
    if (mapper_reg->chr_bank_count == 0) return; /* CHR-RAM */
    if (mapper_reg->last_chr_render == mode) return;
    mapper_reg->last_chr_render = mode;
    if (mode) {
        /* BG rendering */
        mapper5_apply_chr_bg(nes);
    } else {
        /* Sprite rendering */
        mapper5_apply_chr_sprite(nes);
    }
}

int nes_mapper5_init(nes_t* nes) {
    nes->nes_mapper.mapper_init = nes_mapper_init;
    nes->nes_mapper.mapper_deinit = nes_mapper_deinit;
    nes->nes_mapper.mapper_write = nes_mapper_write;
    nes->nes_mapper.mapper_apu = nes_mapper_apu;
    nes->nes_mapper.mapper_read_apu = nes_mapper_read_apu;
    nes->nes_mapper.mapper_hsync = nes_mapper_hsync;
    nes->nes_mapper.mapper_vsync = nes_mapper_vsync;
    nes->nes_mapper.mapper_render_screen = nes_mapper_render_screen;
    return NES_OK;
}

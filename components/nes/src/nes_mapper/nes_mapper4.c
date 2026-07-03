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

static FILE*    wx_dbg_f     = NULL;
static int      wx_dbg_frame = 0;
static int      wx_in_dialog = 0; /* set 1 when chr_lock && any $FF write seen */

typedef struct {
    uint8_t bank_select;    /* $8000: Bank select register */
    uint8_t bank_values[8]; /* R0-R7 bank data values */
    uint8_t mirroring;      /* $A000: Mirroring */
    uint8_t prg_ram_protect;/* $A001: PRG RAM protect */
    uint8_t irq_latch;      /* $C000: IRQ latch value */
    uint8_t irq_counter;    /* Current IRQ counter */
    uint8_t irq_reload;     /* Flag: reload counter on next scanline */
    uint8_t irq_enabled;    /* $E001: IRQ enabled */
    uint16_t prg_bank_count; /* Number of 8KB PRG banks */
    uint16_t chr_bank_count; /* Number of 1KB CHR banks */
    /* Waixing MMC3 variant (Fengyun.nes CRC 0xD49D116F):
     * The protection chip intercepts $8001 writes to CHR registers R0-R5.
     * Startup stub sequence:
     *   $5010=$8C: authentication
     *   $5010=$00: unlock, set $6010 readback = $60, clear lock
     *   ... write font CHR banks via $8001 (R0=4,R1=6,R2=$BC-$BF) ...
     *   $5012=$00: lock, save current R0-R5 as locked_banks
     *
     * During gameplay (chr_lock=1):
     *   $8001 write to R0-R5 with value=$FF: substituted with locked_banks[reg]
     *   $8001 write with any other value: pass through unchanged
     *
     * The NMI CHR updater writes $FF to R0-R5 during dialog mode (ZP$24-$29=$FF).
     * During the unlocked setup window, R2-R5 are decoded through the Waixing
     * CHR line permutation ($BC-$BF -> $EC-$EF).  The chip later substitutes
     * $FF with these decoded font banks, so dialog text renders using the
     * correct font tiles instead of garbled pattern.
     * Normal gameplay writes non-$FF values ($B8-$BB etc.) which pass through.
     *
     * $6000/$6010/$6013 readback builds the protection trampoline opcode
     * sequence JMP $EC60 at $0100. */
    uint8_t waixing_protect; /* 1 = this ROM has the Waixing protection chip */
    uint8_t chr_lock;        /* 1 = CHR lock active ($FF writes substituted) */
    uint8_t chr_setup;       /* 1 = between $5010=$00 unlock and $5012 lock */
    uint8_t locked_banks[6]; /* R0-R5 values saved at $5012 write time */
    uint8_t exp5000;
    uint8_t exp5010; /* $6010 readback: low byte of protection target */
    uint8_t exp5012;
    uint8_t exp5013;
    uint8_t _reserved;
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
    uint16_t last_bank = mapper_reg->prg_bank_count - 1u;
    uint16_t second_last = mapper_reg->prg_bank_count - 2u;

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

/* Waixing protection chip address-line bit permutation.
 * R0/R1 (reg < 2): bypass – the font bank index is stored directly (banks 4-7).
 * R2-R5 (reg >= 2): Mapper-249-style CHR address scramble: $BC->$EC, $BD->$ED, $BE->$EE, $BF->$EF. */
static uint8_t mapper4_waixing_decode_font_chr(uint8_t reg, uint8_t bank) {
    if (reg < 2u) return bank;
    return (uint8_t)((bank & 0x03u) | ((bank & 0x08u) >> 1u) | ((bank & 0x80u) >> 4u) |
                     ((bank & 0x40u) >> 2u) | ((bank & 0x04u) << 3u) | ((bank & 0x10u) << 2u) |
                     ((bank & 0x20u) << 2u));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper4_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper4_register_t* mapper_reg = (mapper4_register_t*)nes->nes_mapper.mapper_register;
    mapper_reg->prg_bank_count = (uint16_t)(nes->nes_rom.prg_rom_size * 2u); /* 16KB units -> 8KB units */
    mapper_reg->chr_bank_count = (uint16_t)(nes->nes_rom.chr_rom_size * 8u); /* 8KB units -> 1KB units */

    mapper_reg->bank_select = 0;
    mapper_reg->mirroring = 0;
    mapper_reg->prg_ram_protect = 0;
    mapper_reg->irq_latch = 0;
    mapper_reg->irq_counter = 0;
    mapper_reg->irq_reload = 0;
    mapper_reg->irq_enabled = 0;
    mapper_reg->waixing_protect = (nes->nes_rom.rom_crc == 0xD49D116Fu) ? 1u : 0u;
    mapper_reg->chr_lock = 0;
    mapper_reg->chr_setup = 0;
    mapper_reg->exp5000 = 0;
    mapper_reg->exp5010 = 0;
    mapper_reg->exp5012 = 0;
    mapper_reg->exp5013 = 0;
    mapper_reg->_reserved = 0;
    for (int i = 0; i < 8; i++) {
        mapper_reg->bank_values[i] = 0;
    }
    for (int i = 0; i < 6; i++) {
        mapper_reg->locked_banks[i] = 0;
    }

    /* Default: last two PRG banks at $C000-$FFFF */
    mapper_reg->bank_values[6] = 0;
    mapper_reg->bank_values[7] = 1;

    /* CHR-RAM: set up pattern table pointers before bank update */
    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }

    /* Waixing protect games always use $6000-$7FFF as game variables after
     * chr_lock; allocate SRAM regardless of the ROM header save_ram flag. */
    if ((mapper_reg->waixing_protect || nes->nes_rom.save_ram) && nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        } else {
            NES_LOG_ERROR("mapper4: failed to allocate WRAM\n");
        }
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
            uint8_t reg = mapper_reg->bank_select & 0x07u;
            uint8_t orig_data = data;
            if (mapper_reg->waixing_protect && reg <= 5u) {
                if (mapper_reg->chr_lock) {
                    if (data == 0xFFu) {
                        data = mapper_reg->locked_banks[reg];
                    }
                    /* log every $8001 write while locked (first 30 dialog frames) */
                    if (wx_dbg_frame <= 30) {
                        if (!wx_dbg_f) wx_dbg_f = fopen("waixing_chr_debug.txt", "w");
                        if (wx_dbg_f) {
                            uint8_t cm = (mapper_reg->bank_select >> 7) & 1u;
                            fprintf(wx_dbg_f,
                                "F%d bs=%02X reg=%u cm=%u raw=%02X final=%02X\n",
                                wx_dbg_frame, mapper_reg->bank_select,
                                (unsigned)reg, (unsigned)cm,
                                (unsigned)orig_data, (unsigned)data);
                            fflush(wx_dbg_f);
                        }
                    }
                } else if (mapper_reg->chr_setup) {
                    data = mapper4_waixing_decode_font_chr(reg, data);
                }
            }
            mapper_reg->bank_values[reg] = data;
            mapper4_update_banks(nes);
            /* after update: log slot 0-3 CHR banks */
            if (mapper_reg->waixing_protect && mapper_reg->chr_lock && wx_dbg_frame <= 30) {
                if (!wx_dbg_f) wx_dbg_f = fopen("waixing_chr_debug.txt", "w");
                if (wx_dbg_f) {
                    uint8_t reg_end = mapper_reg->bank_select & 0x07u;
                    if (reg_end == 5u) { /* after last CHR reg written, dump slots */
                        fprintf(wx_dbg_f,
                            "  slots[0-3]: bv[0]=%02X bv[1]=%02X bv[2]=%02X bv[3]=%02X bv[4]=%02X bv[5]=%02X\n",
                            mapper_reg->bank_values[0], mapper_reg->bank_values[1],
                            mapper_reg->bank_values[2], mapper_reg->bank_values[3],
                            mapper_reg->bank_values[4], mapper_reg->bank_values[5]);
                        fflush(wx_dbg_f);
                    }
                }
            }
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

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper4_register_t* mapper_reg = (mapper4_register_t*)nes->nes_mapper.mapper_register;
    if (!mapper_reg->waixing_protect) return;

    switch (address) {
    case 0x5000: mapper_reg->exp5000 = data; break;
    case 0x5010:
        if (data == 0x00u) {
            mapper_reg->exp5010 = 0x60u;
            /* One-shot guard: once chr_lock=1 (font banks saved), do not
             * re-open the setup window on subsequent $5010=$00 writes.
             * Only refresh the exp5010 readback so the trampoline still works. */
            if (!mapper_reg->chr_lock) {
                mapper_reg->chr_setup = 1u;
            }
        }
        break;
    case 0x5012:
        mapper_reg->exp5012 = data;
        mapper_reg->chr_lock = 1u;
        mapper_reg->chr_setup = 0u;
        for (int i = 0; i < 6; i++) {
            mapper_reg->locked_banks[i] = mapper_reg->bank_values[i];
            mapper_reg->bank_values[i] = 0u;
        }
        mapper4_update_banks(nes);
        break;
    case 0x5013: mapper_reg->exp5013 = data; break;
    default: break;
    }
}

static uint8_t nes_mapper_read_sram(nes_t* nes, uint16_t address) {
    mapper4_register_t* mapper_reg = (mapper4_register_t*)nes->nes_mapper.mapper_register;
    /* Only intercept protection readback addresses during the setup phase
     * (before chr_lock=1).  After chr_lock, the game uses $6000-$7FFF as
     * ordinary work-RAM and the protection register shadows must not mask it. */
    if (mapper_reg->waixing_protect && !mapper_reg->chr_lock) {
        switch (address) {
        case 0x6000: return mapper_reg->exp5000;
        case 0x6010: return mapper_reg->exp5010;
        case 0x6012: return mapper_reg->exp5012;
        case 0x6013: return mapper_reg->exp5013;
        default: break;
        }
    }

    if (nes->nes_rom.sram) {
        return nes->nes_rom.sram[address & 0x1FFFu];
    }
    return 0;
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

static void nes_mapper_vsync(nes_t* nes) {
    (void)nes;
    wx_dbg_frame++;
    if (wx_dbg_f && wx_dbg_frame <= 31) {
        fprintf(wx_dbg_f, "--- vsync %d ---\n", wx_dbg_frame);
        fflush(wx_dbg_f);
    }
}

int nes_mapper4_init(nes_t* nes) {
    nes->nes_mapper.mapper_init    = nes_mapper_init;
    nes->nes_mapper.mapper_deinit  = nes_mapper_deinit;
    nes->nes_mapper.mapper_write   = nes_mapper_write;
    nes->nes_mapper.mapper_apu     = nes_mapper_apu;
    nes->nes_mapper.mapper_read_sram = nes_mapper_read_sram;
    nes->nes_mapper.mapper_hsync   = nes_mapper_hsync;
    nes->nes_mapper.mapper_vsync   = nes_mapper_vsync;
    return NES_OK;
}


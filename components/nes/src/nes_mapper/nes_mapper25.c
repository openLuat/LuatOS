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

/* https://www.nesdev.org/wiki/VRC4
 * Mapper 25 - VRC4c/VRC4d variant.
 * Address decode: reg bit0 from CPU A1/A3, reg bit1 from CPU A0/A2.
 * 8KB PRG banks: slot0/slot2 swappable, slot1 switchable, slot3 fixed last bank.
 * 8x1KB CHR banks via normalized $B000-$E003.
 * VRC4 IRQ is CPU-clock based, with scanline mode ticking every 341 PPU dots.
 */

typedef struct {
    uint8_t prg[2];
    uint8_t chr[8];
    uint8_t mirror;
    uint8_t prg_swap;
    uint8_t irq_enable;
    uint8_t irq_enable_ack;
    uint8_t irq_latch;
    uint8_t irq_counter;
    uint8_t irq_cycle_mode;
    uint16_t irq_cycle_accum;
} mapper25_register_t;

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static uint16_t mapper25_decode_addr(uint16_t address) {
    uint16_t reg = address & 0xF000u;
    if (address & 0x0005u) reg |= 0x0002u;
    if (address & 0x000Au) reg |= 0x0001u;
    return reg;
}

static void mapper25_update_prg(nes_t* nes) {
    mapper25_register_t* r = (mapper25_register_t*)nes->nes_mapper.mapper_register;
    const uint16_t prg_banks = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    if (prg_banks == 0u) {
        return;
    }

    const uint16_t fixed_8k = (prg_banks > 1u) ? (uint16_t)(prg_banks - 2u) : 0u;
    if (r->prg_swap & 0x02u) {
        nes_load_prgrom_8k(nes, 0, fixed_8k);
        nes_load_prgrom_8k(nes, 2, (uint16_t)(r->prg[0] % prg_banks));
    } else {
        nes_load_prgrom_8k(nes, 0, (uint16_t)(r->prg[0] % prg_banks));
        nes_load_prgrom_8k(nes, 2, fixed_8k);
    }
    nes_load_prgrom_8k(nes, 1, (uint16_t)(r->prg[1] % prg_banks));
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_banks - 1u));
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper25_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper25_register_t* r = (mapper25_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper25_register_t));

    r->prg[0] = 0;
    r->prg[1] = 1;
    mapper25_update_prg(nes);

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    } else {
        for (int i = 0; i < 8; i++) {
            nes_load_chrrom_1k(nes, (uint8_t)i, 0);
        }
    }

    if (nes->nes_rom.save_ram && nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        } else {
            NES_LOG_ERROR("mapper25: failed to allocate SRAM\n");
        }
    }
}

/*
 * CHR write handler for normalized $B000-$E003.
 * bit0 selects nibble (0=low4, 1=high4); bit1 selects bank within the block.
 */
static void mapper25_write_chr(mapper25_register_t* r, nes_t* nes,
                                uint16_t reg, uint8_t data) {
    if (nes->nes_rom.chr_rom_size == 0) return;
    uint8_t nibble = (uint8_t)(reg & 1u);
    uint8_t sub    = (uint8_t)((reg >> 1) & 1u);
    uint8_t block  = (uint8_t)((reg >> 12) - 0xBu);
    uint8_t idx    = (uint8_t)(block * 2u + sub);
    if (nibble == 0) {
        r->chr[idx] = (r->chr[idx] & 0xF0u) | (data & 0x0Fu);
    } else {
        r->chr[idx] = (r->chr[idx] & 0x0Fu) | (uint8_t)((data & 0x0Fu) << 4);
    }
    const uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    nes_load_chrrom_1k(nes, idx, (uint8_t)(r->chr[idx] % chr_banks));
}

static const nes_mirror_type_t vrc4_mirror_table[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

/*
 * $8000        : 8KB PRG bank select for $8000-$9FFF, bits[4:0]
 * $A000        : 8KB PRG bank select for $A000-$BFFF, bits[4:0]
 * $9000/$9001  : mirroring bits[1:0] (0=V, 1=H, 2=1scr0, 3=1scr1)
 * $9002/$9003  : PRG swap mode
 * $B000-$E003  : 8x1KB CHR banks
 * $F000/$F001  : IRQ latch low/high nibble
 * $F002        : IRQ control
 * $F003        : IRQ acknowledge
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper25_register_t* r = (mapper25_register_t*)nes->nes_mapper.mapper_register;
    const uint16_t reg = mapper25_decode_addr(address);
    switch (reg & 0xF003u) {
    case 0x8000u:
    case 0x8001u:
    case 0x8002u:
    case 0x8003u:
        r->prg[0] = data & 0x1Fu;
        mapper25_update_prg(nes);
        break;
    case 0xA000u:
    case 0xA001u:
    case 0xA002u:
    case 0xA003u:
        r->prg[1] = data & 0x1Fu;
        mapper25_update_prg(nes);
        break;
    case 0x9000u:
    case 0x9001u:
        r->mirror = data & 0x03u;
        if (data != 0xFFu && nes->nes_rom.four_screen == 0) {
            nes_ppu_screen_mirrors(nes, vrc4_mirror_table[r->mirror]);
        }
        break;
    case 0x9002u:
    case 0x9003u:
        r->prg_swap = data & 0x02u;
        mapper25_update_prg(nes);
        break;
    case 0xB000u:
    case 0xB001u:
    case 0xB002u:
    case 0xB003u:
    case 0xC000u:
    case 0xC001u:
    case 0xC002u:
    case 0xC003u:
    case 0xD000u:
    case 0xD001u:
    case 0xD002u:
    case 0xD003u:
    case 0xE000u:
    case 0xE001u:
    case 0xE002u:
    case 0xE003u:
        mapper25_write_chr(r, nes, reg, data);
        break;
    case 0xF000u:
        nes->nes_cpu.irq_pending = 0;
        r->irq_latch = (uint8_t)((r->irq_latch & 0xF0u) | (data & 0x0Fu));
        break;
    case 0xF001u:
        nes->nes_cpu.irq_pending = 0;
        r->irq_latch = (uint8_t)((r->irq_latch & 0x0Fu) | ((data & 0x0Fu) << 4));
        break;
    case 0xF002u:
        nes->nes_cpu.irq_pending = 0;
        r->irq_cycle_accum = 0;
        r->irq_counter = r->irq_latch;
        r->irq_cycle_mode = data & 0x04u;
        r->irq_enable = data & 0x02u;
        r->irq_enable_ack = data & 0x01u;
        break;
    case 0xF003u:
        nes->nes_cpu.irq_pending = 0;
        r->irq_enable = r->irq_enable_ack;
        break;
    default:
        break;
    }
}

static void mapper25_irq_tick(nes_t* nes) {
    mapper25_register_t* r = (mapper25_register_t*)nes->nes_mapper.mapper_register;
    if (r->irq_counter == 0xFFu) {
        r->irq_counter = r->irq_latch;
        nes_cpu_irq(nes);
    } else {
        r->irq_counter++;
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper25_register_t* r = (mapper25_register_t*)nes->nes_mapper.mapper_register;
    if (!r->irq_enable) return;
    if (r->irq_cycle_mode) {
        while (cycles--) {
            mapper25_irq_tick(nes);
        }
        return;
    }

    r->irq_cycle_accum = (uint16_t)(r->irq_cycle_accum + cycles * 3u);
    while (r->irq_cycle_accum >= 341u) {
        r->irq_cycle_accum = (uint16_t)(r->irq_cycle_accum - 341u);
        mapper25_irq_tick(nes);
    }
}

int nes_mapper25_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

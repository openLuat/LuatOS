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

// https://www.nesdev.org/wiki/INES_Mapper_090

#include "nes.h"

typedef enum {
    MAPPER90_IRQ_CPU_CLOCK = 0,
    MAPPER90_IRQ_PPU_A12   = 1,
    MAPPER90_IRQ_PPU_READ  = 2,
    MAPPER90_IRQ_CPU_WRITE = 3,
} mapper90_irq_source_t;

typedef struct {
    uint8_t prg[4];
    uint8_t chr_low[8];
    uint8_t chr_high[8];
    uint8_t prg_mode;
    uint8_t ex_prg_mode;
    uint8_t chr_mode;
    uint8_t chr_block_mode;
    uint8_t chr_block;
    uint8_t mirror_chr;
    uint8_t mirror;
    uint8_t irq_enable;
    uint8_t irq_source;
    uint8_t irq_direction;
    uint8_t irq_small_prescaler;
    uint8_t irq_prescaler;
    uint8_t irq_counter;
    uint8_t irq_xor;
    uint8_t multiply_value1;
    uint8_t multiply_value2;
    uint8_t reg_ram_value;
} mapper90_register_t;

static uint8_t mapper90_invert_prg_bits(uint8_t value) {
    return (uint8_t)(((value & 0x01u) << 6) | ((value & 0x7Eu) >> 1));
}

static void mapper90_update_prg(nes_t* nes) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    const uint8_t ex_prg = (uint8_t)(r->ex_prg_mode << 6u);
    uint8_t prg[4];
    uint8_t last = (r->prg_mode & 0x04u) ? r->prg[3] : 0x3Fu;

    if ((r->prg_mode & 0x03u) == 0x03u) {
        prg[0] = (uint8_t)(mapper90_invert_prg_bits(r->prg[0]) & 0x3Fu);
        prg[1] = (uint8_t)(mapper90_invert_prg_bits(r->prg[1]) & 0x3Fu);
        prg[2] = (uint8_t)(mapper90_invert_prg_bits(r->prg[2]) & 0x3Fu);
        prg[3] = (uint8_t)(mapper90_invert_prg_bits(last) & 0x3Fu);
    } else {
        prg[0] = r->prg[0];
        prg[1] = r->prg[1];
        prg[2] = r->prg[2];
        prg[3] = last;
    }

    switch (r->prg_mode & 0x03u) {
    case 0u: /* 32KB */
        nes_load_prgrom_32k(nes, 0, (uint16_t)((prg[3] & 0x0Fu) | ((uint16_t)r->ex_prg_mode << 4u)));
        break;
    case 1u: /* 16KB + 16KB */
        nes_load_prgrom_16k(nes, 0, (uint16_t)((prg[1] & 0x1Fu) | ((uint16_t)r->ex_prg_mode << 5u)));
        nes_load_prgrom_16k(nes, 1, (uint16_t)((prg[3] & 0x1Fu) | ((uint16_t)r->ex_prg_mode << 5u)));
        break;
    case 2u: /* 4x8KB */
    case 3u:
        nes_load_prgrom_8k(nes, 0, (uint16_t)(prg[0] | ex_prg));
        nes_load_prgrom_8k(nes, 1, (uint16_t)(prg[1] | ex_prg));
        nes_load_prgrom_8k(nes, 2, (uint16_t)(prg[2] | ex_prg));
        nes_load_prgrom_8k(nes, 3, (uint16_t)(prg[3] | ex_prg));
        break;
    }
}

static uint16_t mapper90_get_chr_reg(mapper90_register_t* r, uint8_t index) {
    if (r->chr_mode >= 2u && r->mirror_chr) {
        if (index == 2u) index = 0u;
        else if (index == 3u) index = 1u;
    }

    if (r->chr_block_mode) {
        switch (r->chr_mode & 0x03u) {
        case 0u: return (uint16_t)((r->chr_low[index] & 0x1Fu) | ((uint16_t)r->chr_block << 5u));
        case 1u: return (uint16_t)((r->chr_low[index] & 0x3Fu) | ((uint16_t)r->chr_block << 6u));
        case 2u: return (uint16_t)((r->chr_low[index] & 0x7Fu) | ((uint16_t)r->chr_block << 7u));
        default: return (uint16_t)(r->chr_low[index] | ((uint16_t)r->chr_block << 8u));
        }
    }

    return (uint16_t)(r->chr_low[index] | ((uint16_t)r->chr_high[index] << 8u));
}

static void mapper90_update_chr(nes_t* nes) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;

    if (nes->nes_rom.chr_rom_size == 0u) {
        nes_load_chrrom_8k(nes, 0, 0);
        return;
    }

    switch (r->chr_mode & 0x03u) {
    case 0u: { /* 8KB */
        uint16_t bank = (uint16_t)(mapper90_get_chr_reg(r, 0u) << 3u);
        for (uint8_t i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, (uint16_t)(bank + i));
        break;
    }
    case 1u: { /* 2x4KB, mapper 90 uses the power-on latches 0 and 4 */
        uint16_t bank = (uint16_t)(mapper90_get_chr_reg(r, 0u) << 2u);
        for (uint8_t i = 0u; i < 4u; i++)
            nes_load_chrrom_1k(nes, i, (uint16_t)(bank + i));

        bank = (uint16_t)(mapper90_get_chr_reg(r, 4u) << 2u);
        for (uint8_t i = 0u; i < 4u; i++)
            nes_load_chrrom_1k(nes, (uint8_t)(i + 4u), (uint16_t)(bank + i));
        break;
    }
    case 2u: /* 4x2KB */
        for (uint8_t i = 0u; i < 4u; i++) {
            uint16_t bank = (uint16_t)(mapper90_get_chr_reg(r, (uint8_t)(i * 2u)) << 1u);
            nes_load_chrrom_1k(nes, (uint8_t)(i * 2u), (uint16_t)(bank + 0u));
            nes_load_chrrom_1k(nes, (uint8_t)(i * 2u + 1u), (uint16_t)(bank + 1u));
        }
        break;
    default: /* 8x1KB */
        for (uint8_t i = 0u; i < 8u; i++)
            nes_load_chrrom_1k(nes, i, mapper90_get_chr_reg(r, i));
        break;
    }
}

static const nes_mirror_type_t jy_mirror_table[4] = {
    NES_MIRROR_VERTICAL,
    NES_MIRROR_HORIZONTAL,
    NES_MIRROR_ONE_SCREEN0,
    NES_MIRROR_ONE_SCREEN1,
};

static void mapper90_clock_irq(nes_t* nes);

static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    switch (address & 0xF007u) {
    case 0x8000u:
    case 0x8001u:
    case 0x8002u:
    case 0x8003u:
    case 0x8004u:
    case 0x8005u:
    case 0x8006u:
    case 0x8007u:
        r->prg[address & 0x03u] = data & 0x7Fu;
        mapper90_update_prg(nes);
        break;
    case 0x9000u:
    case 0x9001u:
    case 0x9002u:
    case 0x9003u:
    case 0x9004u:
    case 0x9005u:
    case 0x9006u:
    case 0x9007u:
        r->chr_low[address & 0x07u] = data;
        mapper90_update_chr(nes);
        break;
    case 0xA000u:
    case 0xA001u:
    case 0xA002u:
    case 0xA003u:
    case 0xA004u:
    case 0xA005u:
    case 0xA006u:
    case 0xA007u:
        r->chr_high[address & 0x07u] = data;
        mapper90_update_chr(nes);
        break;
    case 0xC000u:
        if (data & 0x01u) r->irq_enable = 1u;
        else {
            r->irq_enable = 0u;
            nes->nes_cpu.irq_pending = 0;
        }
        break;
    case 0xC001u:
        r->irq_direction = (data >> 6u) & 0x03u;
        r->irq_small_prescaler = (data & 0x04u) ? 1u : 0u;
        r->irq_source = data & 0x03u;
        break;
    case 0xC002u:
        r->irq_enable = 0u;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0xC003u:
        r->irq_enable = 1u;
        break;
    case 0xC004u:
        r->irq_prescaler = data ^ r->irq_xor;
        break;
    case 0xC005u:
        r->irq_counter = data ^ r->irq_xor;
        break;
    case 0xC006u:
        r->irq_xor = data;
        break;
    case 0xD000u:
    case 0xD004u:
        r->prg_mode = data & 0x07u;
        r->chr_mode = (data >> 3u) & 0x03u;
        mapper90_update_prg(nes);
        mapper90_update_chr(nes);
        break;
    case 0xD001u:
    case 0xD005u:
        r->mirror = data & 0x03u;
        if (nes->nes_rom.four_screen == 0)
            nes_ppu_screen_mirrors(nes, jy_mirror_table[r->mirror]);
        break;
    case 0xD003u:
    case 0xD007u:
        r->mirror_chr = (data & 0x80u) ? 1u : 0u;
        r->chr_block_mode = (data & 0x20u) ? 0u : 1u;
        r->chr_block = (uint8_t)((data & 0x01u) | ((data & 0x18u) >> 2u));
        r->ex_prg_mode = (data >> 1u) & 0x03u;
        mapper90_update_prg(nes);
        mapper90_update_chr(nes);
        break;
    default:
        break;
    }

    if (r->irq_source == MAPPER90_IRQ_CPU_WRITE) {
        mapper90_clock_irq(nes);
    }
}

static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;

    switch (address & 0xF803u) {
    case 0x5000u:
        return 0u;
    case 0x5800u:
        return (uint8_t)(r->multiply_value1 * r->multiply_value2);
    case 0x5801u:
        return (uint8_t)(((uint16_t)r->multiply_value1 * r->multiply_value2) >> 8u);
    case 0x5803u:
        return r->reg_ram_value;
    default:
        return 0u;
    }
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;

    switch (address & 0xF803u) {
    case 0x5800u:
        r->multiply_value1 = data;
        break;
    case 0x5801u:
        r->multiply_value2 = data;
        break;
    case 0x5803u:
        r->reg_ram_value = data;
        break;
    default:
        break;
    }
}

static void mapper90_clock_irq(nes_t* nes) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    uint8_t mask = r->irq_small_prescaler ? 0x07u : 0xFFu;
    uint8_t prescaler = r->irq_prescaler & mask;
    uint8_t clock_irq = 0u;

    if (r->irq_direction == 0x01u) {
        prescaler++;
        if ((prescaler & mask) == 0u) clock_irq = 1u;
    } else if (r->irq_direction == 0x02u) {
        prescaler--;
        if (prescaler == 0u) clock_irq = 1u;
    }

    r->irq_prescaler = (uint8_t)((r->irq_prescaler & (uint8_t)~mask) | (prescaler & mask));
    if (!clock_irq) return;

    if (r->irq_direction == 0x01u) {
        r->irq_counter++;
        if (r->irq_counter == 0u && r->irq_enable) nes_cpu_irq(nes);
    } else if (r->irq_direction == 0x02u) {
        r->irq_counter--;
        if (r->irq_counter == 0xFFu && r->irq_enable) nes_cpu_irq(nes);
    }
}

static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    if (r->irq_source != MAPPER90_IRQ_CPU_CLOCK) return;

    while (cycles--) {
        mapper90_clock_irq(nes);
    }
}

static void nes_mapper_hsync(nes_t* nes) {
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_ppu.MASK_b == 0 && nes->nes_ppu.MASK_s == 0) return;

    if (r->irq_source == MAPPER90_IRQ_PPU_A12) {
        for (uint8_t i = 0u; i < 8u; i++) {
            mapper90_clock_irq(nes);
        }
    } else if (r->irq_source == MAPPER90_IRQ_PPU_READ) {
        for (uint8_t i = 0u; i < 170u; i++) {
            mapper90_clock_irq(nes);
        }
    }
}

static void mapper90_init_mirroring(nes_t* nes) {
    if (nes->nes_rom.four_screen == 0) {
        nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);
    }
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(mapper90_register_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    mapper90_register_t* r = (mapper90_register_t*)nes->nes_mapper.mapper_register;
    nes_memset(r, 0, sizeof(mapper90_register_t));

    r->chr_block_mode = 0u;

    mapper90_update_prg(nes);
    mapper90_update_chr(nes);
    mapper90_init_mirroring(nes);
}

int nes_mapper90_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_read_apu  = nes_mapper_read_apu;
    nes->nes_mapper.mapper_apu       = nes_mapper_apu;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    nes->nes_mapper.mapper_hsync     = nes_mapper_hsync;
    return NES_OK;
}

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

/* https://www.nesdev.org/wiki/Sunsoft_FME-7 */

typedef struct {
    uint8_t  reg_select;
    uint8_t  prg[3];        /* $8000, $A000, $C000 bank indices */
    uint8_t  chr[8];        /* 1KB CHR bank indices */
    uint8_t  prg6_bank;     /* $6000-$7FFF PRG ROM bank (when prg6_ram_en=0) */
    uint8_t  prg6_ram_en;   /* 1 = WRAM at $6000-$7FFF, 0 = PRG ROM */
    uint8_t  irq_timer_en;
    uint8_t  irq_counter_en;
    uint16_t irq_counter;
} nes_mapper69_t;

static void mapper69_update_prg(nes_t* nes) {
    nes_mapper69_t* m = (nes_mapper69_t*)nes->nes_mapper.mapper_register;
    uint16_t prg_banks = nes->nes_rom.prg_rom_size * 2; /* 16KB units -> 8KB units */
    nes_load_prgrom_8k(nes, 0, m->prg[0] % prg_banks);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % prg_banks);
    nes_load_prgrom_8k(nes, 2, m->prg[2] % prg_banks);
    nes_load_prgrom_8k(nes, 3, (uint16_t)(prg_banks - 1));
}

static void mapper69_update_chr(nes_t* nes) {
    nes_mapper69_t* m = (nes_mapper69_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_rom.chr_rom_size == 0) return;
    uint16_t chr_banks = (uint16_t)(nes->nes_rom.chr_rom_size * 8); /* 8KB units -> 1KB units */
    for (int i = 0; i < 8; i++) {
        nes_load_chrrom_1k(nes, (uint8_t)i, (uint16_t)(m->chr[i] % chr_banks));
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper69_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper69_t* m = (nes_mapper69_t*)nes->nes_mapper.mapper_register;
    m->reg_select      = 0;
    m->prg[0]          = 0;
    m->prg[1]          = 1;
    m->prg[2]          = 2;
    m->prg6_bank       = 0;
    m->prg6_ram_en     = 0;
    m->irq_timer_en    = 0;
    m->irq_counter_en  = 0;
    m->irq_counter     = 0;
    for (int i = 0; i < 8; i++) m->chr[i] = (uint8_t)i;

    /* Allocate WRAM for $6000-$7FFF (FME-7 register 8 RAM mode) */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram != NULL) {
            nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
        }
    }

    if (nes->nes_rom.chr_rom_size == 0) {
        nes_load_chrrom_8k(nes, 0, 0);
    }
    mapper69_update_prg(nes);
    mapper69_update_chr(nes);
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

/*
 * $8000-$9FFF: command register (bits[3:0] = register index)
 * $A000-$BFFF: parameter register (data written to selected register)
 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper69_t* m = (nes_mapper69_t*)nes->nes_mapper.mapper_register;

    if (address < 0xA000) {
        /* $8000-$9FFF: select register */
        m->reg_select = data & 0x0F;
        return;
    }

    /* $A000-$BFFF: write to selected register */
    switch (m->reg_select) {
    case 0x0: case 0x1: case 0x2: case 0x3:
    case 0x4: case 0x5: case 0x6: case 0x7:
        /* CHR 1KB bank select */
        m->chr[m->reg_select] = data;
        mapper69_update_chr(nes);
        break;
    case 0x8:
        /* $6000-$7FFF bank: bit6=RAM/ROM select, bits[5:0]=PRG ROM bank */
        m->prg6_bank   = data & 0x3Fu;
        m->prg6_ram_en = (data >> 6u) & 1u;
        break;
    case 0x9:
        /* 8KB PRG bank at $8000 */
        m->prg[0] = data & 0x3F;
        mapper69_update_prg(nes);
        break;
    case 0xA:
        /* 8KB PRG bank at $A000 */
        m->prg[1] = data & 0x3F;
        mapper69_update_prg(nes);
        break;
    case 0xB:
        /* 8KB PRG bank at $C000 */
        m->prg[2] = data & 0x3F;
        mapper69_update_prg(nes);
        break;
    case 0xC:
        /* Mirroring: bits[1:0]: 0=V, 1=H, 2=single0, 3=single1 */
        switch (data & 0x03) {
        case 0: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);     break;
        case 1: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);   break;
        case 2: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0);  break;
        case 3: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1);  break;
        }
        break;
    case 0xD:
        /* IRQ control: bit[7]=timer enable, bit[0]=counter enable */
        m->irq_timer_en   = (data >> 7) & 1;
        m->irq_counter_en = data & 1;
        /* Acknowledge pending IRQ on any write to this register */
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0xE:
        /* IRQ counter low byte */
        m->irq_counter = (m->irq_counter & 0xFF00) | data;
        break;
    case 0xF:
        /* IRQ counter high byte */
        m->irq_counter = (m->irq_counter & 0x00FF) | ((uint16_t)data << 8);
        break;
    }
}

/*
 * $6000-$7FFF read: route to WRAM (register 8 bit6=1) or PRG ROM bank
 * (register 8 bit6=0, bank selected by bits[5:0]).
 */
static uint8_t nes_mapper_read_sram(nes_t* nes, uint16_t address) {
    nes_mapper69_t* m = (nes_mapper69_t*)nes->nes_mapper.mapper_register;
    if (m->prg6_ram_en) {
        if (nes->nes_rom.sram != NULL)
            return nes->nes_rom.sram[address & 0x1FFFu];
        return 0xFF;
    }
    /* PRG ROM mode: read from banked 8KB PRG ROM */
    if (nes->nes_rom.prg_rom != NULL) {
        uint32_t prg_8k_count = (uint32_t)nes->nes_rom.prg_rom_size * 2u;
        uint32_t bank = (uint32_t)(m->prg6_bank) % prg_8k_count;
        return nes->nes_rom.prg_rom[bank * 8192u + (address & 0x1FFFu)];
    }
    return 0xFF;
}

/*
 * 16-bit cycle counter: decrements every CPU cycle when counter enable
 * (bit7 of reg $D) is set.  IRQ fires on unsigned underflow only when
 * IRQ enable (bit0 of reg $D) is also set.
 * NESdev: counter decrements regardless of IRQ enable bit.
 */
static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    nes_mapper69_t* m = (nes_mapper69_t*)nes->nes_mapper.mapper_register;
    if (!m->irq_timer_en) return;
    uint16_t prev = m->irq_counter;
    m->irq_counter -= cycles;
    if (m->irq_counter_en && m->irq_counter > prev) {  /* unsigned underflow → IRQ */
        nes_cpu_irq(nes);
    }
}

int nes_mapper69_init(nes_t* nes) {
    nes->nes_mapper.mapper_init        = nes_mapper_init;
    nes->nes_mapper.mapper_deinit      = nes_mapper_deinit;
    nes->nes_mapper.mapper_write       = nes_mapper_write;
    nes->nes_mapper.mapper_read_sram   = nes_mapper_read_sram;
    nes->nes_mapper.mapper_cpu_clock   = nes_mapper_cpu_clock;
    return NES_OK;
}

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

/*
 * Mapper 17 — FFE F8xxx PCB
 * https://www.nesdev.org/wiki/INES_Mapper_017
 *
 * Register map (FCEUX ffe.cpp, ffemode=1 — the ONLY authoritative source):
 *   $4501        IRQ ACK              (disarm + clear pending)
 *   $4502        IRQ counter lo byte  (IRQCount &= 0xFF00 | data; ACK)
 *   $4503        IRQ counter hi byte  (IRQCount &= 0x00FF | data<<8; ARM; ACK)
 *   $4504        PRG slot0 ($8000-$9FFF) bank, direct encoding
 *   $4505        PRG slot1 ($A000-$BFFF) bank, direct encoding
 *   $4506        PRG slot2 ($C000-$DFFF) bank, direct encoding
 *   $4507        PRG slot3 ($E000-$FFFF) bank, direct encoding
 *   $4510-$4517  CHR 1KB banks 0-7, direct encoding
 *   $42FE        Mirroring: mirr = 0 | ((data>>4)&1)   → 0=1-screen-A, 1=1-screen-B
 *   $42FF        Mirroring: mirr = 2 | ((data>>4)&1)   → 2=vertical, 3=horizontal
 *   $5D00/$5D01  Shadow R/W bytes (game uses these; no special mapper logic needed)
 *   $8000-$FFFF  writes = no-op (latch; ffemode=1 ignores it for banking)
 *   $6000-$7FFF  WRAM 8KB
 *
 * IRQ timer (FCEUX FFEIRQHook): count-UP per CPU cycle.
 * Fires when IRQCount >= 0x10000.
 * After fire: IRQa=0, IRQCount=0.  NO auto-reload.
 * Game re-arms by writing $4503 (via E3C0 shadow-restore subroutine) each IRQ.
 *
 * Power-on: preg[3]=~0=0xFF → bank15 (last); preg[0/1/2]=0 → bank0.
 * RESET code (bank15, E2E6-E374) initialises:
 *   $4504=$0C → slot0=bank12
 *   $4505=$0D → slot1=bank13
 *   $4506=$0E → slot2=bank14  (bank14 = $C000 service library, D394/E3C0/etc.)
 * Then JMP $D394 (bank14). D394 arms IRQ via JSR C232→E3C0→STA $4503.
 *
 * Verified ROM: Batman: Return of the Joker (蝙蝠侠2, Unl)
 */

typedef struct {
    uint8_t  prg[4];        /* 8KB PRG banks for slots 0-3 */
    uint8_t  chr[8];        /* 1KB CHR banks */
    uint8_t  mirr;          /* 0=1-screen-A, 1=1-screen-B, 2=V, 3=H */
    uint32_t irq_count;     /* CPU-cycle up-counter */
    uint8_t  irq_enable;    /* 1=armed */
    uint8_t  shadow[2];     /* $5D00/$5D01 R/W storage */
} nes_mapper17_t;

static void mapper17_update_prg(nes_t* nes) {
    nes_mapper17_t* m = (nes_mapper17_t*)nes->nes_mapper.mapper_register;
    uint16_t n = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    nes_load_prgrom_8k(nes, 0, m->prg[0] % n);
    nes_load_prgrom_8k(nes, 1, m->prg[1] % n);
    nes_load_prgrom_8k(nes, 2, m->prg[2] % n);
    nes_load_prgrom_8k(nes, 3, m->prg[3] % n);
}

static void mapper17_update_chr(nes_t* nes) {
    nes_mapper17_t* m = (nes_mapper17_t*)nes->nes_mapper.mapper_register;
    if (nes->nes_rom.chr_rom_size == 0) return;
    uint16_t nc = (uint16_t)(nes->nes_rom.chr_rom_size * 8u);
    for (int i = 0; i < 8; i++)
        nes_load_chrrom_1k(nes, (uint8_t)i, m->chr[i] % nc);
}

static void mapper17_update_mirr(nes_t* nes) {
    nes_mapper17_t* m = (nes_mapper17_t*)nes->nes_mapper.mapper_register;
    switch (m->mirr) {
    case 0: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN0); break;
    case 1: nes_ppu_screen_mirrors(nes, NES_MIRROR_ONE_SCREEN1); break;
    case 2: nes_ppu_screen_mirrors(nes, NES_MIRROR_VERTICAL);    break;
    case 3: nes_ppu_screen_mirrors(nes, NES_MIRROR_HORIZONTAL);  break;
    default: break;
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (!nes->nes_mapper.mapper_register) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper17_t));
        if (!nes->nes_mapper.mapper_register) return;
    }
    nes_mapper17_t* m = (nes_mapper17_t*)nes->nes_mapper.mapper_register;
    nes_memset(m, 0, sizeof(nes_mapper17_t));

    uint16_t n = (uint16_t)(nes->nes_rom.prg_rom_size * 2u);
    /* Power-on: slot3=last bank (bank15); slot0/1/2=bank0 */
    m->prg[3] = (uint8_t)((n - 1u) & 0xFFu);

    if (!nes->nes_rom.sram) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
    }

    m->mirr = nes->nes_rom.mirroring_type ? 2u : 3u;
    mapper17_update_prg(nes);
    mapper17_update_chr(nes);
    mapper17_update_mirr(nes);
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper17_t* m = (nes_mapper17_t*)nes->nes_mapper.mapper_register;
    if (!m) return;
    switch (address) {
    /* Mirroring */
    case 0x42FE:
        m->mirr = (uint8_t)(0u | ((data >> 4u) & 1u));
        mapper17_update_mirr(nes);
        break;
    case 0x42FF:
        m->mirr = (uint8_t)(2u | ((data >> 4u) & 1u));
        mapper17_update_mirr(nes);
        break;

    /* IRQ registers */
    case 0x4501:
        m->irq_enable = 0;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0x4502:
        m->irq_count = (m->irq_count & 0xFF00u) | data;
        nes->nes_cpu.irq_pending = 0;
        break;
    case 0x4503:
        m->irq_count = (m->irq_count & 0x00FFu) | ((uint32_t)data << 8u);
        m->irq_enable = 1;
        nes->nes_cpu.irq_pending = 0;
        break;

    /* PRG slot banks (all 4 switchable, direct encoding) */
    case 0x4504: m->prg[0] = data; mapper17_update_prg(nes); break;
    case 0x4505: m->prg[1] = data; mapper17_update_prg(nes); break;
    case 0x4506: m->prg[2] = data; mapper17_update_prg(nes); break;
    case 0x4507: m->prg[3] = data; mapper17_update_prg(nes); break;

    /* CHR 1KB banks */
    case 0x4510: case 0x4511: case 0x4512: case 0x4513:
    case 0x4514: case 0x4515: case 0x4516: case 0x4517:
        m->chr[address & 0x07u] = data;
        mapper17_update_chr(nes);
        break;

    /* Shadow R/W bytes used by game subroutines E1C0/E3C0 */
    case 0x5D00: m->shadow[0] = data; break;
    case 0x5D01: m->shadow[1] = data; break;

    default: break;
    }
}

static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    nes_mapper17_t* m = (nes_mapper17_t*)nes->nes_mapper.mapper_register;
    if (!m) return 0;
    if (address == 0x5D00u) return m->shadow[0];
    if (address == 0x5D01u) return m->shadow[1];
    return 0;
}

/* IRQ: count-UP per CPU cycle; fire when >= 0x10000; no auto-reload */
static void nes_mapper_cpu_clock(nes_t* nes, uint16_t cycles) {
    nes_mapper17_t* m = (nes_mapper17_t*)nes->nes_mapper.mapper_register;
    if (!m || !m->irq_enable) return;
    m->irq_count += cycles;
    if (m->irq_count >= 0x10000u) {
        m->irq_enable = 0;
        m->irq_count  = 0;
        nes_cpu_irq(nes);
    }
}

/* $8000-$FFFF writes are no-ops in ffemode=1 */
static void nes_mapper_write(nes_t* nes, uint16_t address, uint8_t data) {
    (void)nes; (void)address; (void)data;
}

int nes_mapper17_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_write     = nes_mapper_write;
    nes->nes_mapper.mapper_apu       = nes_mapper_apu;
    nes->nes_mapper.mapper_read_apu  = nes_mapper_read_apu;
    nes->nes_mapper.mapper_cpu_clock = nes_mapper_cpu_clock;
    return NES_OK;
}

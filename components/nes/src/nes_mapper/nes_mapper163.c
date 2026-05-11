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

/* https://www.nesdev.org/wiki/INES_Mapper_163
 * Nanjing mapper — 南京映射器，用于多款中文未授权游戏（暗黑破坏神、关云长、水浒传等）*/

typedef struct {
    /* reg[0]=$5000: PRG bank 低 4 位 + bit7=CHR 自动切换使能
     * reg[1]=$5100: 安全密钥（copy-protection）
     * reg[2]=$5200: PRG bank 高 4 位
     * reg[3]=$5300: 辅助寄存器（copy-protection 读取使用）
     * reg[4]=$5101: copy-protection 触发寄存器 */
    uint8_t reg[5];
    uint8_t toggle;   /* copy-protection 触发标志，初始值=1 */
} nes_mapper163_t;

static void mapper163_sync_prg(nes_t* nes) {
    nes_mapper163_t* m = (nes_mapper163_t*)nes->nes_mapper.mapper_register;
    if (!m) return;
    /* PRG 32KB bank = reg[0][3:0] | reg[2][3:0]<<4（最多 256 × 32KB = 8MB） */
    uint8_t prg = (m->reg[0] & 0x0Fu) | ((m->reg[2] & 0x0Fu) << 4u);
    uint16_t prg_count = (uint16_t)(nes->nes_rom.prg_rom_size / 2u);
    if (prg_count == 0u) prg_count = 1u;
    nes_load_prgrom_32k(nes, 0, (uint16_t)((uint16_t)prg % prg_count));
}

/*
 * 直接操作 pattern_table 指针，实现对 CHR-RAM 的 4KB 页面切换。
 * nes_load_chrrom_4k 对 CHR-RAM 会强制 src=des（身份映射），
 * 无法将两个页面映射到同一 CHR bank，因此这里绕过该限制。
 * des: 目标 4KB 页 (0=PPU $0000-$0FFF, 1=PPU $1000-$1FFF)
 * bank: CHR bank 编号 (0=chr_ram[0..4095], 1=chr_ram[4096..8191])
 */
static void mapper163_select_chr_page(nes_t* nes, uint8_t des, uint8_t bank) {
    uint8_t* base = nes->nes_rom.chr_rom + (uint32_t)bank * 4096u;
    for (uint8_t i = 0u; i < 4u; i++) {
        nes->nes_ppu.pattern_table[des * 4u + i] = base + (uint32_t)i * 1024u;
    }
}

static void nes_mapper_init(nes_t* nes) {
    if (nes->nes_mapper.mapper_register == NULL) {
        nes->nes_mapper.mapper_register = nes_malloc(sizeof(nes_mapper163_t));
        if (nes->nes_mapper.mapper_register == NULL) return;
    }
    nes_mapper163_t* m = (nes_mapper163_t*)nes->nes_mapper.mapper_register;
    m->reg[0] = 0u;
    m->reg[1] = 0u;
    m->reg[2] = 0u;
    m->reg[3] = 0u;
    m->reg[4] = 0u;
    m->toggle = 1u;

    /* 分配 WRAM ($6000-$7FFF)，中文 RPG 游戏需要 */
    if (nes->nes_rom.sram == NULL) {
        nes->nes_rom.sram = (uint8_t*)nes_malloc(SRAM_SIZE);
        if (nes->nes_rom.sram) nes_memset(nes->nes_rom.sram, 0, SRAM_SIZE);
    }

    /* CHR 初始化：两个 4KB 页均指向 bank 0（与 Mesen2 InitMapper 一致） */
    if (nes->nes_rom.chr_rom_size > 0u) {
        nes_load_chrrom_4k(nes, 0, 0);
        nes_load_chrrom_4k(nes, 1, 0);
    } else {
        /* CHR-RAM：直接操作 pattern_table，使两页共享 bank 0 */
        mapper163_select_chr_page(nes, 0, 0);
        mapper163_select_chr_page(nes, 1, 0);
    }

    /* PRG 初始化：bank 0 */
    mapper163_sync_prg(nes);

    /* mirroring 使用 ROM 头部设置 */
    nes_ppu_screen_mirrors(nes, NES_MIRROR_AUTO);
}

static void nes_mapper_deinit(nes_t* nes) {
    nes_free(nes->nes_mapper.mapper_register);
    nes->nes_mapper.mapper_register = NULL;
}

/*
 * 写入 $5000-$5FFF（通过 mapper_apu 回调，范围 $4020-$5FFF）：
 *
 * $5101（精确地址）：copy-protection 触发寄存器；非零→零时切换 toggle
 *
 * $5100（精确地址）且 data==6：安全密钥，立即切换 PRG 到 bank 3，不更新 reg[1]
 *
 * 其余地址按 (addr & 0x7300) 解码：
 *   $5000: PRG bank 低 4 位；bit7=CHR 自动切换使能
 *   $5100: 安全密钥 reg[1]；data==6 同样切换 PRG bank 3
 *   $5200: PRG bank 高 4 位
 *   $5300: 辅助寄存器
 */
static void nes_mapper_apu(nes_t* nes, uint16_t address, uint8_t data) {
    nes_mapper163_t* m = (nes_mapper163_t*)nes->nes_mapper.mapper_register;
    if (!m) return;
    if (address < 0x5000u) return;

    if (address == 0x5101u) {
        /* 非零→零转换时切换 copy-protection toggle */
        if (m->reg[4] != 0u && data == 0u) {
            m->toggle ^= 1u;
        }
        m->reg[4] = data;
        return;
    }

    /* $5100 精确地址写安全密钥 6：切换 PRG bank 3，不更新 reg[1] */
    if (address == 0x5100u && data == 6u) {
        uint16_t prg_count = (uint16_t)(nes->nes_rom.prg_rom_size / 2u);
        if (prg_count == 0u) prg_count = 1u;
        nes_load_prgrom_32k(nes, 0, 3u % prg_count);
        return;
    }

    switch (address & 0x7300u) {
    case 0x5000u:
        m->reg[0] = data;
        /* 非自动切换模式且在帧前半段时恢复默认 CHR 布局（身份映射） */
        if (!(data & 0x80u) && nes->scanline < 128u) {
            if (nes->nes_rom.chr_rom_size > 0u) {
                nes_load_chrrom_4k(nes, 0, 0);
                nes_load_chrrom_4k(nes, 1, 1);
            } else {
                mapper163_select_chr_page(nes, 0, 0);
                mapper163_select_chr_page(nes, 1, 1);
            }
        }
        mapper163_sync_prg(nes);
        break;
    case 0x5100u:
        m->reg[1] = data;
        if (data == 6u) {
            /* 非精确 $5100 地址的安全密钥写入（如 $5108 等） */
            uint16_t prg_count = (uint16_t)(nes->nes_rom.prg_rom_size / 2u);
            if (prg_count == 0u) prg_count = 1u;
            nes_load_prgrom_32k(nes, 0, 3u % prg_count);
        }
        break;
    case 0x5200u:
        m->reg[2] = data;
        mapper163_sync_prg(nes);
        break;
    case 0x5300u:
        m->reg[3] = data;
        break;
    default:
        break;
    }
}

/*
 * Copy-protection 读取（来自 Mesen2 Nanjing.h）：
 *   addr & 0x7700 == 0x5100: reg[3]|reg[1]|reg[0]|(reg[2]^0xFF)
 *   addr & 0x7700 == 0x5500: toggle ? (reg[3]|reg[0]) : 0
 *   default: 4
 */
static uint8_t nes_mapper_read_apu(nes_t* nes, uint16_t address) {
    nes_mapper163_t* m = (nes_mapper163_t*)nes->nes_mapper.mapper_register;
    if (!m) return 4u;
    switch (address & 0x7700u) {
    case 0x5100u:
        return (uint8_t)(m->reg[3] | m->reg[1] | m->reg[0] | (m->reg[2] ^ 0xFFu));
    case 0x5500u:
        return m->toggle ? (uint8_t)(m->reg[3] | m->reg[0]) : 0u;
    default:
        return 4u;
    }
}

/* CHR 自动切换（reg[0] bit7=1 时启用，CHR-ROM 和 CHR-RAM 均支持）：
 * scanline 127 时切换两个 4KB 页到 CHR bank 1；
 * scanline 239 时切换回 bank 0（与 Mesen2 NotifyVramAddressChange 行为一致）。 */
static void nes_mapper_hsync(nes_t* nes) {
    nes_mapper163_t* m = (nes_mapper163_t*)nes->nes_mapper.mapper_register;
    if (!m || !(m->reg[0] & 0x80u)) return;
    if (nes->scanline == 127u) {
        if (nes->nes_rom.chr_rom_size > 0u) {
            nes_load_chrrom_4k(nes, 0, 1);
            nes_load_chrrom_4k(nes, 1, 1);
        } else {
            mapper163_select_chr_page(nes, 0, 1);
            mapper163_select_chr_page(nes, 1, 1);
        }
    } else if (nes->scanline == 239u) {
        if (nes->nes_rom.chr_rom_size > 0u) {
            nes_load_chrrom_4k(nes, 0, 0);
            nes_load_chrrom_4k(nes, 1, 0);
        } else {
            mapper163_select_chr_page(nes, 0, 0);
            mapper163_select_chr_page(nes, 1, 0);
        }
    }
}


int nes_mapper163_init(nes_t* nes) {
    nes->nes_mapper.mapper_init      = nes_mapper_init;
    nes->nes_mapper.mapper_deinit    = nes_mapper_deinit;
    nes->nes_mapper.mapper_apu       = nes_mapper_apu;
    nes->nes_mapper.mapper_read_apu  = nes_mapper_read_apu;
    nes->nes_mapper.mapper_hsync     = nes_mapper_hsync;
    return NES_OK;
}

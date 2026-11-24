#ifdef __LUATOS__
#include "luat_conf_bsp.h"
#endif
/* The standalone decoder can also be built for host-side pulse replay. */
#if !defined(__LUATOS__) || defined(LUAT_USE_IR_RX)
#include "luat_ir_nec.h"

luat_ir_event_t luat_ir_nec_edge(luat_ir_nec_t *rx, uint64_t now_us) {
    uint64_t us = now_us - rx->last_edge_us;
    rx->last_edge_us = now_us;
    if (!rx->have_edge) {
        rx->have_edge = 1;
        return LUAT_IR_NONE;
    }
    /* 解调输出空闲为高；两个下降沿之间的时间包含低脉冲和随后的高电平间隔。 */
    if (us >= 12500 && us <= 14500) { /* 完整帧引导：9 ms 低电平 + 4.5 ms 高电平 */
        rx->receiving = 1;
        rx->have_key = 0;
        rx->word = 0;
        rx->bits = 0;
    } else if (us >= 10400 && us <= 12000) { /* 重复帧引导：9 ms + 2.25 ms，不含键码 */
        rx->receiving = 0;
        if (rx->have_key && now_us - rx->last_key_us < 160000) {
            rx->last_key_us = now_us;
            return LUAT_IR_REPEAT;
        }
    } else if (rx->receiving) {
        /* 数据低位先行：约 2.25 ms 表示 1，约 1.125 ms 表示 0，超出容差则丢弃本帧。 */
        if (us >= 1750 && us <= 2750) {
            rx->word |= UINT32_C(1) << rx->bits;
        } else if (us < 800 || us > 1450) {
            rx->receiving = 0;
            return LUAT_IR_NONE;
        }
        if (++rx->bits == 32) {
            uint16_t addr = (uint16_t)rx->word;
            uint8_t cmd = (uint8_t)(rx->word >> 16);
            rx->receiving = 0;
            if ((cmd ^ (uint8_t)(rx->word >> 24)) == 0xff) {
                /* 两个地址字节互为反码表示标准 8 位地址，否则按扩展 16 位地址处理。 */
                rx->addr = (((addr >> 8) ^ (addr & 0xff)) == 0xff) ? (addr & 0xff) : addr;
                rx->cmd = cmd;
                rx->last_key_us = now_us;
                rx->have_key = 1;
                return LUAT_IR_KEY;
            }
        }
    }
    return LUAT_IR_NONE;
}
#endif

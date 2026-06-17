/*
 * luat_netdrv_pkg.c - 硬件驱动层统一的包入口
 *
 * 在原 napt_pkg_input 前加一层 EVT_PKG 截获检查. 驱动原本调
 * napt_pkg_input 的地方换成调本函数, 其它调用方代码 (判断返回值后
 * 是否继续 netif_input_proxy 等) 保持不变.
 *
 * 数据流 (FROM_HW 当前唯一实现的 event):
 *
 *   driver -> luat_netdrv_pkg_input(id, FROM_HW, buff, len)
 *               |
 *               +--(has_pkg_cb)--> fire_pkg_event(FROM_HW) -> return 1
 *               +--(else)--------> luat_netdrv_napt_pkg_input(...)
 *                                         |
 *                                         +--(consumed)----> return non-zero
 *                                         +--(not consumed)-> return 0  (调用方继续 netif_input_proxy)
 *
 *   (future) FROM_LWIP:
 *     LWIP linkoutput -> pkg_input(id, FROM_LWIP, buff, len)
 *               |
 *               +--(has_pkg_cb)--> fire_pkg_event(FROM_LWIP) -> return 1
 *               +--(else)--------> drv->dataout -> return 0
 */

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_napt.h"
#include "luat_netdrv_event.h"
#include "luat_netdrv_pkg.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

// FROM_HW 处理: 截获检查 -> napt_pkg_input
static int pkg_input_from_hw(uint8_t id, uint8_t* buff, uint16_t len) {
    // 1. Lua 截获: 已注册 EVT_PKG 回调, 包交给 Lua 后不再走 NAPT/LWIP
    if (luat_netdrv_has_pkg_cb(id)) {
        luat_netdrv_fire_pkg_event(id, LUAT_NETDRV_CH_HW, buff, len);
        return 1;
    }
    // 2. 原 NAPT 处理 (返回值语义不变: 0=未消费需继续, 非0=已消费)
    return luat_netdrv_napt_pkg_input(id, buff, (size_t)len);
}

int luat_netdrv_pkg_input(uint8_t id, uint8_t event, uint8_t* buff, uint16_t len) {
    if (buff == NULL || len == 0) {
        return -1;
    }
    switch (event) {
        case LUAT_NETDRV_CH_HW:
            return pkg_input_from_hw(id, buff, len);
        // case LUAT_NETDRV_CH_LWIP:   // 未来: LWIP TX 拦截
        //     return pkg_input_from_lwip(...);
        // case LUAT_NETDRV_CH_NAPT:   // 未来: NAPT 拦截
        //     return pkg_input_from_napt(...);
        default:
            LLOGW("netdrv_pkg_input: 未知 channel 0x%X adapter %d", event, id);
            return -1;
    }
}

/*
 * luat_netdrv_pkg.c - 硬件驱动层统一的包入口
 *
 * 把"截获 / NAPT / LWIP 注入"集中在一个函数里, 驱动只调 luat_netdrv_pkg_input.
 *
 * 数据流:
 *   driver -> luat_netdrv_pkg_input(id, buff, len)
 *               |
 *               +--(has_pkg_cb)--> fire_pkg_event(FROM_HW) -> return 1
 *               +--(else)--------> napt_pkg_input
 *                                     |
 *                                     +--(consumed)----> return 0
 *                                     +--(not consumed)-> netif_input_proxy
 *                                                          |
 *                                                          +--(ok)--------> return 0
 *                                                          +--(fail)------> return -1
 */

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_napt.h"
#include "luat_netdrv_event.h"
#include "luat_netdrv_pkg.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

int luat_netdrv_pkg_input(uint8_t id, uint8_t* buff, uint16_t len) {
    if (buff == NULL || len == 0) {
        return -1;
    }
    // 1. Lua 截获: 已注册 EVT_PKG 回调, 包交给 Lua, 不再走 NAPT/LWIP
    if (luat_netdrv_has_pkg_cb(id)) {
        luat_netdrv_fire_pkg_event(id, LUAT_NETDRV_PKG_FROM_HW, buff, len);
        return 1;
    }
    // 2. NAPT 处理
    int napt_ret = luat_netdrv_napt_pkg_input(id, buff, (size_t)len);
    if (napt_ret != 0) {
        // NAPT 已消费 (本机 loopback / 本机作为对端)
        return 0;
    }
    // 3. 注入 LWIP
    luat_netdrv_t* drv = luat_netdrv_get(id);
    if (drv == NULL || drv->netif == NULL) {
        LLOGW("netdrv_pkg_input: adapter %d 无 netif, 丢包 len %u", id, len);
        return -1;
    }
    int netif_ret = luat_netdrv_netif_input_proxy(drv->netif, buff, len);
    if (netif_ret != 0) {
        LLOGE("netdrv_pkg_input: netif_input_proxy 错误 adapter %d ret %d", id, netif_ret);
        return -1;
    }
    return 0;
}

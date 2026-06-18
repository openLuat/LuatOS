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
// 修正: EVT_PKG 是被动观察语义, 不应阻断 NAPT/LWIP/bk72xx 后续流程.
// 旧实现 fire 后直接 return 1, 会让 airlink 端 BK72XX wifi 的 drv->dataout
// 硬件环回被静默跳过, 用户注册一个只读计数器就会破坏 wifi TX.
// 新实现: 先把包通知给 Lua (fire 是只读副本, 不消耗原 buffer), 然后照常
// 走 NAPT; NAPT 决定包是否被消费. fire 失败也照常继续走 NAPT, 不应让一个
// 注册的观察者阻断真实的数据通路.
__NETDRV_CODE_IN_RAM__ static int pkg_input_from_hw(uint8_t id, uint8_t* buff, uint16_t len) {
    // 1. Lua 被动观察: 不消耗, 不阻断 NAPT
    if (luat_netdrv_has_pkg_cb(id)) {
        luat_netdrv_fire_pkg_event(id, LUAT_NETDRV_CH_HW, buff, len);
    }
    // 2. 原 NAPT 处理 (返回值语义不变: 0=未消费需继续, 非0=已消费)
    return luat_netdrv_napt_pkg_input(id, buff, (size_t)len);
}

__NETDRV_CODE_IN_RAM__ int luat_netdrv_pkg_input(uint8_t id, uint8_t event, uint8_t* buff, uint16_t len) {
    if (buff == NULL || len == 0) {
        return -1;
    }
    switch (event) {
        case LUAT_NETDRV_CH_HW:
            return pkg_input_from_hw(id, buff, len);
        case LUAT_NETDRV_CH_LWIP: {
            // LWIP 出口: 用户已声明拦截即不再走原 dataout 流程.
            //   - 没有 pkg_cb 注册: 返回 0, 调用方继续原 linkoutput (HW 出口)
            //   - 有 pkg_cb 注册:   fire 后返回 1 (consumed), 调用方跳过 dataout
            // Lua 侧可继续用 netdrv.send_raw(CH_HW/CH_LWIP) 注入应答或转发到其它网卡.
            if (luat_netdrv_has_pkg_cb(id)) {
                luat_netdrv_fire_pkg_event(id, LUAT_NETDRV_CH_LWIP, buff, len);
                return 1;
            }
            return 0;
        }
        // case LUAT_NETDRV_CH_NAPT:   // 未来: NAPT 拦截
        //     return pkg_input_from_napt(...);
        default:
            LLOGW("netdrv_pkg_input: 未知 channel 0x%X adapter %d", event, id);
            return -1;
    }
}

// 硬件 TX 出口的薄包装, 与 pkg_input 对称. 集中所有 drv->dataout 调用点,
// 后续要加 TX 通道拦截 / 统计 / 模拟器注入只需改这一处.
// 本轮不做 fire_pkg_event 拦截, 仅做 null 检查 + 转发 (行为完全等价于原直接调用).
__NETDRV_CODE_IN_RAM__ int luat_netdrv_pkg_output(uint8_t id, uint8_t event, uint8_t* buff, uint16_t len) {
    if (buff == NULL || len == 0) {
        return -1;
    }
    luat_netdrv_t* drv = luat_netdrv_get(id);
    if (drv == NULL || drv->dataout == NULL) {
        LLOGW("netdrv_pkg_output: adapter %d 不可用或无 dataout", id);
        return -1;
    }
    switch (event) {
        case LUAT_NETDRV_CH_HW:
            drv->dataout(drv, drv->userdata, buff, len);
            return 0;
        // case LUAT_NETDRV_CH_LWIP:   // 未来: LWIP TX 拦截
        // case LUAT_NETDRV_CH_NAPT:   // 未来: NAPT TX 拦截
        default:
            LLOGW("netdrv_pkg_output: 未知 channel 0x%X adapter %d", event, id);
            return -1;
    }
}

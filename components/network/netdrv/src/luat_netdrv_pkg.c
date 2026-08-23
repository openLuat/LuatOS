/*
 * luat_netdrv_pkg.c - 硬件驱动层统一的包出入口
 *
 * pkg_input: 在原 napt_pkg_input 前加一层 EVT_PKG 截获检查. 驱动原本调
 *            napt_pkg_input 的地方换成调本函数, 其它调用方代码 (判断返回值后
 *            是否继续 netif_input_proxy 等) 保持不变.
 * pkg_output: 集中所有 drv->dataout 调用入口 (薄包装), 与 pkg_input 对称.
 *
 * 数据流:
 *
 *   RX 入口 (src=CH_HW):
 *     driver -> luat_netdrv_pkg_input(id, src=HW, buff, len)
 *               |
 *               +--(has_pkg_cb)--> fire_pkg_event(src=HW)  // 被动观察, 不消耗 buffer
 *               +-- 任何情况      -> napt_pkg_input(...)
 *                                         |
 *                                         +--(consumed)----> return non-zero
 *                                         +--(not consumed)-> return 0  (调用方继续 netif_input_proxy)
 *
 *   TX 出口拦截 (src=CH_LWIP, 注册即消费):
 *     LWIP linkoutput -> pkg_input(id, src=LWIP, buff, len)
 *               |
 *               +--(has_pkg_cb)--> fire_pkg_event(src=LWIP) -> return 1  (consumed, 跳原 dataout)
 *               +--(else)--------> return 0  (调用方继续原 linkoutput -> dataout)
 *
 *   TX 出口 (dst=CH_HW):
 *     luat_netdrv_pkg_output(id, dst=HW, buff, len) -> drv->dataout(...)
 *
 * 注意: EVT_PKG 在 HW 路径上是"被动观察"语义, fire 不消耗原 buffer, 不阻断
 * NAPT/LWIP/bk72xx 后续流程. 旧实现 fire 后直接 return 1 会让 airlink 端
 * BK72XX wifi 的 drv->dataout 硬件环回被静默跳过, 用户注册一个只读计数器就
 * 会破坏 wifi TX, 因此保留"fire 后照常走 NAPT"的语义.
 */

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_netdrv_napt.h"
#include "luat_netdrv_event.h"
#include "luat_netdrv_pkg.h"

#define LUAT_LOG_TAG "netdrv"
#include "luat_log.h"

__NETDRV_CODE_IN_RAM__ int luat_netdrv_pkg_input(uint8_t id, uint8_t src, uint8_t* buff, uint16_t len) {
    if (buff == NULL || len == 0) {
        return -1;
    }
    switch (src) {
        case LUAT_NETDRV_CH_HW:
            // RX 入口: 被动观察 (fire 不消耗, 不阻断) + 原 NAPT 处理
            if (luat_netdrv_has_pkg_cb(id)) {
                luat_netdrv_fire_pkg_event(id, LUAT_NETDRV_CH_HW, buff, len);
            }
            return luat_netdrv_napt_pkg_input(id, buff, (size_t)len);
        case LUAT_NETDRV_CH_LWIP: {
            // TX 出口: 注册即消费, 调用方跳过 dataout
            //   - 没有 pkg_cb 注册: 返回 0, 调用方继续原 linkoutput (HW 出口)
            //   - 有 pkg_cb 注册:   fire 后返回 1, 调用方跳过 dataout
            // Lua 侧可继续用 netdrv.send_raw(CH_HW/CH_LWIP) 注入应答或转发到其它网卡.
            if (luat_netdrv_has_pkg_cb(id)) {
                luat_netdrv_fire_pkg_event(id, LUAT_NETDRV_CH_LWIP, buff, len);
                return 1;
            }
            return 0;
        }
        // case LUAT_NETDRV_CH_NAPT:   // 未来: NAPT 拦截
        default:
            LLOGW("netdrv_pkg_input: 未知 channel 0x%X adapter %d", src, id);
            return -1;
    }
}

// 硬件 TX 出口的薄包装, 与 pkg_input 对称. 集中所有 drv->dataout 调用点,
// 后续要加 TX 通道拦截 / 统计 / 模拟器注入只需改这一处.
// 本轮不做 fire_pkg_event 拦截, 仅做 null 检查 + 转发 (行为完全等价于原直接调用).
__NETDRV_CODE_IN_RAM__ int luat_netdrv_pkg_output(uint8_t id, uint8_t dst, uint8_t* buff, uint16_t len) {
    if (buff == NULL || len == 0) {
        return -1;
    }
    luat_netdrv_t* drv = luat_netdrv_get(id);
    if (drv == NULL || drv->dataout == NULL) {
        LLOGW("netdrv_pkg_output: adapter %d 不可用或无 dataout", id);
        return -1;
    }
    switch (dst) {
        case LUAT_NETDRV_CH_HW:
            drv->dataout(drv, drv->userdata, buff, len);
            return 0;
        // case LUAT_NETDRV_CH_LWIP:   // 未来: LWIP TX 拦截
        // case LUAT_NETDRV_CH_NAPT:   // 未来: NAPT TX 拦截
        default:
            LLOGW("netdrv_pkg_output: 未知 channel 0x%X adapter %d", dst, id);
            return -1;
    }
}

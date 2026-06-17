#ifndef LUAT_NETDRV_PKG_H
#define LUAT_NETDRV_PKG_H

#include <stdint.h>
#include "luat_netdrv_event.h"  // 提供 LUAT_NETDRV_PKG_FROM_HW 等常量与回调原型

/**
 * 硬件驱动层统一的包入口 (从 napt_pkg_input 升级而来, 加 EVT_PKG 截获)
 *
 * 设计目标:
 *   - 在原 napt_pkg_input 入口前增加 EVT_PKG 截获检查, 驱动调一行就能获得截获能力
 *   - 不修改原 napt / netif_input_proxy 的调用语义 (返回值 0 = 未消费需继续)
 *
 * 调用时机:
 *   - 驱动原本调用 luat_netdrv_napt_pkg_input 的地方, 把函数名换成 luat_netdrv_pkg_input
 *     即可, 其它逻辑 (ret == 0 时继续 netif_input_proxy 等) 完全不变
 *
 * 参数 event 区分包来源 (来自哪个链路阶段):
 *   - LUAT_NETDRV_PKG_FROM_HW (0x10): 硬件 RX, 流程是 截获检查 -> napt_pkg_input
 *   - (future) FROM_LWIP         : LWIP TX linkoutput, 流程是 截获检查 -> drv->dataout
 *
 * 返回值 (与原 napt_pkg_input 兼容):
 *   0  = NAPT 未消费, 调用方应继续注入 LWIP (或对应 event 的下游链路)
 *   非 0 = 包已被消费 (被 Lua 截获 / 被 NAPT 消费)
 *  -1   = 错误 (adapter 异常 / buff 空 / 未知 event)
 */
int luat_netdrv_pkg_input(uint8_t id, uint8_t event, uint8_t* buff, uint16_t len);

#endif

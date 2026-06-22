#ifndef LUAT_NETDRV_PKG_H
#define LUAT_NETDRV_PKG_H

#include <stdint.h>
#include "luat_netdrv_event.h"  // 提供 LUAT_NETDRV_CH_HW 等常量与回调原型

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
 * 参数 src 区分包来源 (来自哪个链路阶段, 即 RX 方向上的"上游"):
 *   - LUAT_NETDRV_CH_HW (0x10):   物理硬件 (RX 自 HW). 流程是 截获检查 -> napt_pkg_input
 *   - LUAT_NETDRV_CH_LWIP (0x20): LWIP linkoutput (TX 拦截点). 流程是 截获检查 -> (return 1 跳原 dataout)
 *   - (future) LUAT_NETDRV_CH_NAPT (0x30): NAPT 输入, 暂未启用
 *
 * 返回值 (与原 napt_pkg_input 兼容):
 *   0  = NAPT 未消费, 调用方应继续注入 LWIP (或对应 src 的下游链路)
 *   非 0 = 包已被消费 (被 Lua 截获 / 被 NAPT 消费)
 *  -1   = 错误 (adapter 异常 / buff 空 / 未知 src)
 */
int luat_netdrv_pkg_input(uint8_t id, uint8_t src, uint8_t* buff, uint16_t len);

/**
 * 硬件驱动层统一的包出口 (TX)
 * 与 pkg_input 对称,集中所有 netdrv->dataout 调用入口.
 *
 * 参数 dst 区分包去向 (去向哪个链路阶段, 即 TX 方向上的"下游"):
 *   - LUAT_NETDRV_CH_HW (0x10): 物理硬件. 流程是 调 drv->dataout
 *   - (future) LUAT_NETDRV_CH_LWIP/CH_NAPT: 未来按需扩展
 *
 * 返回值:
 *   0  = 已发出
 *  -1  = 失败 (adapter 缺失 / dataout 为空 / buff 为空 / 未知 dst)
 */
int luat_netdrv_pkg_output(uint8_t id, uint8_t dst, uint8_t* buff, uint16_t len);

#endif

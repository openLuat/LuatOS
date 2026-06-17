#ifndef LUAT_NETDRV_PKG_H
#define LUAT_NETDRV_PKG_H

#include <stdint.h>
#include "luat_netdrv_event.h"  // 提供 LUAT_NETDRV_PKG_FROM_HW 等常量与回调原型

/**
 * 硬件驱动层统一的包入口
 *
 * 设计目标:
 *   1. 把"是否注册了 EVT_PKG 回调 / 是否走 NAPT / 是否注入 LWIP"这一整套判断
 *      从各个驱动 (ch390h / airlink / wg / ovpn / ...) 中抽出来, 集中维护
 *   2. 驱动只调这一行, 不再各自实现 if/else 拦截
 *
 * 调用时机:
 *   - 驱动从硬件 / 链路层收到一个完整的 IP 包时调用
 *   - 一个包只能调一次, 内部已实现"截获 OR 转发"的二选一
 *
 * 参数 event 区分包来源 (来自哪个链路阶段), 不同来源下游路径不同:
 *   - LUAT_NETDRV_PKG_FROM_HW (0x10): 硬件 RX, 流程是 截获 -> NAPT -> LWIP
 *   - (future) FROM_LWIP         : LWIP TX linkoutput, 流程是 截获 -> drv->dataout
 *
 * 拦截语义 (与 EVT_PKG 设计一致):
 *   - 若已注册 netdrv.EVT_PKG 回调: 包交给 Lua, 本函数返回 1, 不再走下游
 *   - 否则: 走该 event 对应的下游路径
 *
 * 返回值:
 *   1  = 已被 Lua 截获 (EVT_PKG 回调已 fire, 后续链路跳过)
 *   0  = 已成功转发 (走完对应 event 的下游路径)
 *  -1  = 错误 (adapter 无效 / LWIP 注入失败 / 未知 event, 驱动应中止本轮处理)
 */
int luat_netdrv_pkg_input(uint8_t id, uint8_t event, uint8_t* buff, uint16_t len);

#endif

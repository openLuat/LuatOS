#ifndef LUAT_NETDRV_PKG_H
#define LUAT_NETDRV_PKG_H

#include <stdint.h>

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
 * 拦截语义 (与 EVT_PKG 设计一致):
 *   - 若已注册 netdrv.EVT_PKG 回调: 包交给 Lua, 本函数返回 1, 不再走 NAPT/LWIP
 *   - 否则: 走 NAPT, NAPT 消费则返回 0; 否则注入 LWIP
 *
 * 返回值:
 *   1  = 已被 Lua 截获 (EVT_PKG 回调已 fire, 后续链路跳过)
 *   0  = 已成功转发 (NAPT 消费 OR 已注入 LWIP)
 *  -1  = 错误 (adapter 无效 / LWIP 注入失败, 驱动应中止本轮处理)
 */
int luat_netdrv_pkg_input(uint8_t id, uint8_t* buff, uint16_t len);

#endif

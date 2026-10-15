#ifndef __NET_LWIP2_DNS_H__
#define __NET_LWIP2_DNS_H__

/*
 * net_lwip2 新 DNS 客户端的适配层私有声明.
 *
 * 为什么不放在 net_lwip2.h 里:
 *   SDK 的 csdk/interface/include/net_lwip.h 会把 net_lwip2.h 带给 SDK 侧的
 *   编译单元(例如 luat_ats_ccm42xx.c 经 luat_atc.h 间接引入).
 *   而 luat_netdrv_dns.h 需要 c_common.h 的 llist, c_common.h 又与 SDK 的
 *   bsp_common.h 重复定义了 Time_UserDataStruct / Date_UserDataStruct /
 *   Time_Union / Date_Union, 两者同时可见必然编译冲突.
 *   公共头保持"不带 c_common.h", 只有真正要用 DNS 的 .c 才引本文件.
 */

#include "luat_base.h"
#include "luat_netdrv_dns.h"

#if defined(LUAT_USE_DNS)

#ifdef LUAT_USE_NETDRV_DNS_CLIENT

#define NETDRV_DNS_TX_BURST	8		/* 单次 pump 最多产出的报文数 */
#define NETDRV_DNS_STAT_TIMEOUT	1000	/* netdrv.ctrl 读统计的等待上限(ms) */

/*
 * 跨线程控制块: Lua 任务侧填好 -> 投递事件 -> tcpip 线程应用 -> 置 done -> Lua 侧轮询取值.
 * 全程不加锁: done 是最后写的单字节, ARM 上对齐字节写是原子的;
 * 即便 Lua 侧读到略旧的统计值也无影响(统计本身是观测用途).
 */
typedef struct
{
	luat_netdrv_dns_cfg_t cfg;	/* 待应用的配置 */
	luat_netdrv_dns_cfg_t rcfg;	/* 回读: 当前生效配置 */
	luat_netdrv_dns_stat_t rstat;	/* 回读: 统计 */
	uint8_t has_cfg;		/* 1 = 需要应用 cfg */
	uint8_t flush;		/* 1 = 整表失效 */
	uint8_t want_stat;		/* 1 = 需要回读统计 */
	uint8_t done;		/* tcpip 线程置位, Lua 侧轮询 */
}net_lwip2_dns_ctl_t;

/**
 * 应用 DNS 配置并按需回读统计.
 * @return 0 成功并已取回回读数据; < 0 超时(回读数据可能是上一次的值)
 */
int net_lwip2_dns_ctrl(net_lwip2_dns_ctl_t *ctl, uint32_t timeout_ms);

#endif /* LUAT_USE_NETDRV_DNS_CLIENT */

#endif /* LUAT_USE_DNS */

#endif

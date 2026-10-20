/*
 * luat_ppp_dns.c - IPCP 协商出的 DNS 的落点。
 *
 * 背景: LuatOS 的 PC 与硬件 BSP 全局都是 LWIP_DNS=0, lwip 核心的
 * core/dns.c 因此编成空对象, 在 L2TP 的 PPP 子集里开 LWIP_DNS=1 也拿不到
 * dns_setserver()/dns_getserver()。而 IPCP 的 CI_MS_DNS1/2 处理、以及 ppp.c 的
 * sdns()/cdns() 都在 #if LWIP_DNS 里 —— 不开就完全不会向 LNS 要 DNS。
 *
 * 做法: 让 PPP 这一组 TU 认为 LWIP_DNS=1, 并用 luat_ppp_opts_override.h 里的宏把
 * dns_setserver/dns_getserver 重定向到本文件, 把地址存在这里; 链路 up 时由
 * netdrv 胶水层(luat_netdrv_l2tp.c)取走, 调 network_set_dns_server() 交给
 * LuatOS 适配器层(最终是 net_lwip2 的 per-adapter DNS)。
 *
 * 这样隧道内 DNS 与 lwip 核心的 dns.c 解耦, 不会改变其它网卡/其它组件的 DNS 行为。
 */
#include "netif/ppp/ppp_opts.h"
#include "luat_ppp_opts_override.h"

#include "lwip/ip_addr.h"
#include "l2tp/l2tp_client.h"

#if LWIP_DNS

#define LUAT_PPP_DNS_SERVER_NUM 2

static ip_addr_t prv_ppp_dns[LUAT_PPP_DNS_SERVER_NUM];

void luat_ppp_dns_set_server(u8_t numdns, const ip_addr_t *dnsserver)
{
    if (numdns >= LUAT_PPP_DNS_SERVER_NUM) {
        return;
    }
    if (dnsserver == NULL || ip_addr_isany(dnsserver)) {
        ip_addr_set_zero(&prv_ppp_dns[numdns]);
        return;
    }
    prv_ppp_dns[numdns] = *dnsserver;
}

const ip_addr_t* luat_ppp_dns_get_server(u8_t numdns)
{
    if (numdns >= LUAT_PPP_DNS_SERVER_NUM) {
        return IP_ADDR_ANY;
    }
    return &prv_ppp_dns[numdns];
}

uint32_t luat_ppp_dns_get_server_u32(uint8_t idx)
{
    if (idx >= LUAT_PPP_DNS_SERVER_NUM) {
        return 0;
    }
    /* 与 IPCP 内部一致: 网络字节序的 IPv4, 0 表示未协商到 */
    return ip_addr_get_ip4_u32(&prv_ppp_dns[idx]);
}

#else /* LWIP_DNS */

uint32_t luat_ppp_dns_get_server_u32(uint8_t idx)
{
    (void)idx;
    return 0;
}

#endif /* LWIP_DNS */

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#ifdef __LUATOS__
#include "luat_netdrv_ch390h.h"
#endif
#include "luat_netdrv_napt.h"
#include "luat_mcu.h"
#include "luat_mem.h"

#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/etharp.h"
#include "lwip/icmp.h"
#include "lwip/prot/etharp.h"
#include "lwip/tcpip.h"
#include "lwip/tcp.h"
#include "lwip/udp.h"
#include "lwip/prot/tcp.h"
#include "lwip/prot/udp.h"
#include "lwip/ip_addr.h"

#include "net_lwip2.h"

#define LUAT_LOG_TAG "netdrv.napt"
#include "luat_log.h"

#define UDP_MAP_TIMEOUT (60 * 1000)
#define NAPT_MAX_PACKET_SIZE (1520)

static int s_gw_adapter_id = -1;

// 同步 drvs[adapter_id]->netif 与 prvlwip.lwip_netif (SOC固件的真实netif)
// 用于解决 PDP 重激活后 drvs[]->netif 指针过时的问题
static void napt_sync_gw_netif(int adapter_id) {
    #ifdef  __USE_SDK_LWIP__
    if (adapter_id != NW_ADAPTER_INDEX_LWIP_GPRS)
        return;
    luat_netdrv_t* drv = luat_netdrv_get(adapter_id);
    if (drv == NULL) return;
    struct netif* real_netif = net_lwip_get_netif(adapter_id);
    if (real_netif == NULL) return;
    if (drv->netif == real_netif) return;
    uint32_t old_ip = drv->netif ? ip_addr_get_ip4_u32(&drv->netif->ip_addr) : 0;
    uint32_t new_ip = ip_addr_get_ip4_u32(&real_netif->ip_addr);
    /* Air8000 fix (v3): Two-layer RNDIS detection.
     * v2 (precise) layer alone is INSUFFICIENT because napt_enable runs BEFORE
     * luat_netdrv_rndis_link_up() assigns netdrv_rndis.netif, so the USB drv
     * netif is still NULL at sync time and the precise check passes.
     * v3 adds an SDK-side layer: query net_lwip_get_netif(NW_ADAPTER_INDEX_LWIP_USB),
     * which works as soon as SDK registers the RNDIS netif (even before LuatOS
     * sees it). This catches the RNDIS pollution at NAPT enable time, while
     * still avoiding the 10.x heuristic false-positives. */
    if (old_ip != 0 && new_ip != old_ip) {
    #ifdef NW_ADAPTER_INDEX_LWIP_USB
        /* Layer 1: LuatOS USB netdrv (available after rndis_link_up) */
        luat_netdrv_t* _usb_drv = luat_netdrv_get(NW_ADAPTER_INDEX_LWIP_USB);
        if (_usb_drv != NULL && _usb_drv->netif != NULL && real_netif == _usb_drv->netif) {
            LLOGW("NAPT netif sync REJECT (L1 luat-usb): adapter=%d new netif is USB/RNDIS (IP %08X), keep original (IP %08X)",
                  adapter_id, new_ip, old_ip);
            return;
        }
        /* Layer 2: SDK-side lookup (works before LuatOS USB drv is wired up) */
        struct netif* _sdk_usb_netif = net_lwip_get_netif(NW_ADAPTER_INDEX_LWIP_USB);
        if (_sdk_usb_netif != NULL && real_netif == _sdk_usb_netif) {
            LLOGW("NAPT netif sync REJECT (L2 sdk-usb): adapter=%d new netif is SDK RNDIS (IP %08X), keep original (IP %08X)",
                  adapter_id, new_ip, old_ip);
            return;
        }
        /* Layer 3: IP-equal compare. Works when SDK pollutes via DATA (not pointer):
         * if new_ip equals USB netif's IP, the GPRS slot was overwritten with RNDIS LAN IP.
         * Safe vs multi-10.x because Eth/STA WAN IPs would never equal RNDIS LAN IP. */
        if (_sdk_usb_netif != NULL) {
            uint32_t _usb_ip = ip_addr_get_ip4_u32(&_sdk_usb_netif->ip_addr);
            if (_usb_ip != 0 && new_ip == _usb_ip) {
                LLOGW("NAPT netif sync REJECT (L3 ip-eq-rndis): adapter=%d new IP %08X equals USB/RNDIS IP, keep original (IP %08X)",
                      adapter_id, new_ip, old_ip);
                return;
            }
        }
    #endif
    }
    /* Air8000 fix L4: \u591a PDP context \u4fdd\u62a4.
     * SDK \u5c42 net_lwip_get_netif() \u5355\u69fd\u8fd4\u56de prvlwip.lwip_netif,
     * \u5f53 CP \u4fa7\u6fc0\u6d3b\u591a\u4e2a PDP (IMS/VoLTE/eMBMS) \u65f6\u4f1a\u88ab\u540e\u6fc0\u6d3b\u7684\u8986\u76d6,
     * \u5bfc\u81f4 gw netif \u5207\u5230\u975e\u9ed8\u8ba4 PDP context. \u8fd0\u8425\u5546 GTP \u9694\u79bb\u4e0b, luaNAPT \u4e0a\u884c src
     * \u5199\u6210 IMS PDP IP \u4f1a\u76f4\u63a5\u4e22\u3002 \u53ea\u8981 old_ip \u5df2\u6709\u503c\u4e14 new_ip \u4e0d\u540c, \u5c31\u4fdd\u7559 old\u3002 */
    if (old_ip != 0 && new_ip != old_ip) {
        LLOGW("NAPT netif sync REJECT (L4 multi-pdp): adapter=%d new IP %08X old IP %08X, keep original (\u907f\u514d IMS/\u5907\u4efd PDP \u62a2\u5360 gw netif)",
              adapter_id, new_ip, old_ip);
        return;
    }
    LLOGI("NAPT netif sync: adapter=%d old=%p(IP %08X) -> new=%p(IP %08X)", adapter_id, drv->netif, old_ip, real_netif, new_ip);
    drv->netif = real_netif;
        #endif
}

#if !defined(LUAT_USE_PSRAM) && !defined(LUAT_USE_NETDRV_NAPT)
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    return 0;
}
#else
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    /* Air8000 诊断: 入口采样,区分 wnet/lan 来源, 重点观察 AP 上行包是否到达 */
    static uint32_t _air8k_in_cnt = 0;
    int _air8k_log = ((_air8k_in_cnt++ & 0x1F) == 0);
    int _air8k_is_wnet_arg = (s_gw_adapter_id == id);
    if (_air8k_log) {
        LLOGD("[AIR8000][napt_in] id=%d len=%u is_wnet=%d gw_ad=%d cnt=%u",
              id, (unsigned)len, _air8k_is_wnet_arg, s_gw_adapter_id, (unsigned)_air8k_in_cnt);
    }
    if (s_gw_adapter_id < 0) {
        // LLOGD("NAPT 未开启");
        return 0; // NAPT没有开启
    }
    luat_netdrv_t* drv = luat_netdrv_get(id);
    if (drv == NULL || drv->netif == NULL) {
        LLOGD("网关netif不存在,无法转发");
        return 0;
    }
    if (len < 24 || len > 1600) {
        LLOGD("包长度不合法, 拒绝改写 %d", len);
        return 0;
    }
    luat_netdrv_t* gw = luat_netdrv_get(s_gw_adapter_id);
    if (gw == NULL || gw->netif == NULL) {
        return 0; // 网关不存在, 那就没有转发
    }
    // 首先, 如果是eth网卡, 需要先判断是不是广播包
    napt_ctx_t ctx = {
        .buff = buff,
        .len = len,
        .iphdr = (struct ip_hdr*)(buff + SIZEOF_ETH_HDR),
        .eth = (struct eth_hdr*)buff,
        .is_wnet = s_gw_adapter_id == id,
        .net = drv,
        .drv_gw = gw,
    };

    if (drv->netif->flags & NETIF_FLAG_ETHARP) {
        // LLOGD("是ETH包, 先判断是不是广播包");
        if (memcmp(ctx.eth->dest.addr, "\xFF\xFF\xFF\xFF\xFF\xFF", 6) == 0 ||
            ctx.eth->dest.addr[0] == 0x01
        ) {
            // LLOGD("是广播包,不需要执行napt");
            return 0;
        }
        // LLOGD("ETH包 " MACFMT " -> " MACFMT " %04X", MAC_ARG(ctx.eth->src.addr), MAC_ARG(ctx.eth->dest.addr), ctx.eth->type);
        if (ctx.eth->type == PP_HTONS(ETHTYPE_ARP)) {
            // LLOGD("ETH包 " MACFMT " -> " MACFMT " %04X", MAC_ARG(ctx.eth->src.addr), MAC_ARG(ctx.eth->dest.addr), ctx.eth->type);
            if (s_gw_adapter_id == id) {
                // LLOGD("ETH包 " MACFMT " -> " MACFMT " %04X", MAC_ARG(ctx.eth->src.addr), MAC_ARG(ctx.eth->dest.addr), ctx.eth->type);
                // 这是网关侧的ARP包, 需要分析是否网关的ARP包, 然后更新到本地ARP表
                struct etharp_hdr* hdr = (struct etharp_hdr*)(buff + SIZEOF_ETH_HDR);
                ip4_addr_t sipaddr, dipaddr;
                // 是不是ARP回应
                // LLOGD("ARP数据 %04X %04X", hdr->opcode, PP_HTONS(ARP_REPLY));
                memcpy(&sipaddr, &hdr->sipaddr, 4);
                memcpy(&dipaddr, &hdr->dipaddr, 4);
                char tmp[16];
                ip4addr_ntoa_r(&sipaddr, tmp, 16);
                // LLOGD("ARP数据 %04X %04X from %s", hdr->opcode, PP_HTONS(ARP_REPLY), tmp);
                // if (hdr->opcode == PP_HTONS(ARP_REPLY)) {
                    // memcpy(&dipaddr, &hdr->dipaddr, 4);
                    if (gw && gw->netif) {
                        // LLOGD("sipaddr.addr %08X", sipaddr.addr);
                        memcpy(gw->gw_mac, hdr->shwaddr.addr, 6);
                        // LLOGD("网关MAC更新成功 %02X%02X%02X%02X%02X%02X", gw->gw_mac[0], gw->gw_mac[1], gw->gw_mac[2], gw->gw_mac[3], gw->gw_mac[4], gw->gw_mac[5]);
                        // return 0;
                    }
                    else {
                        // LLOGD("不是网关的ARP包? gw %p", gw);
                    }
                // }
            }
        }
        if (ctx.eth->type != PP_HTONS(ETHTYPE_IP)) {
            // LLOGD("不是IP包, 不需要执行napt");
            return 0;
        }
    }
    else {
        // LLOGD("不是ETH包, 裸IP包");
        ctx.iphdr = (struct ip_hdr*)(buff);
        ctx.eth = NULL;
    }

    // 看来是IP包了, 判断一下版本号
    u8_t ipVersion;
    ipVersion = IPH_V(ctx.iphdr);
    if (ipVersion != 4) {
        // LLOGD("不是ipv4包, 不需要执行napt");
        return 0;
    }
    if (s_gw_adapter_id != id && ctx.iphdr->dest.addr == ip_addr_get_ip4_u32(&drv->netif->ip_addr)) {
        // LLOGD("是本网关的包, 不需要执行napt");
        return 0;
    }
    if (IPH_PROTO(ctx.iphdr) != IP_PROTO_UDP && IPH_PROTO(ctx.iphdr) != IP_PROTO_TCP && IPH_PROTO(ctx.iphdr) != IP_PROTO_ICMP) {
        // LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }
    // LLOGD("按协议类型, 使用对应的NAPT修改器进行处理 id %d proto %d", id, IPH_PROTO(ctx.iphdr));
    // uint64_t tbegin = luat_mcu_tick64();
    int ret = 0;
    switch (IPH_PROTO(ctx.iphdr))
    {
    case IP_PROTO_ICMP:
        ret = luat_napt_icmp_handle(&ctx);
        break;
    case IP_PROTO_TCP:
        ret = luat_napt_tcp_handle(&ctx);
        break;
    case IP_PROTO_UDP:
        ret = luat_napt_udp_handle(&ctx);
        break;
    default:
        // LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }
    // uint64_t tend = luat_mcu_tick64();
    // uint64_t tused_us = (tend - tbegin) / luat_mcu_us_period();
    // if (tused_us > 100) {
    //     LLOGI("time used %4lld us tp %2d way %d", tused_us, IPH_PROTO(ctx.iphdr), s_gw_adapter_id == id);
    // }
    return ret;
}
#endif

// 辅助函数
int luat_netdrv_napt_pkg_input_pbuf(int id, struct pbuf* p) {
    if (p == NULL || p->tot_len > NAPT_MAX_PACKET_SIZE) {
        return 0;
    }
    // LLOGD("pbuf情况 total %d len %d", p->tot_len, p->len);
    if (p->tot_len == p->len) {
        // 单个连续pbuf, 直接使用
        return luat_netdrv_napt_pkg_input(id, p->payload, p->tot_len);
    }
    // 链式pbuf, 拷贝为连续缓冲区再处理
    uint8_t* tmp_buff = luat_heap_opt_malloc(LUAT_HEAP_AUTO, p->tot_len);
    if (tmp_buff == NULL) {
        LLOGW("NAPT链式pbuf分配缓冲区失败 %d", p->tot_len);
        return 0;
    }
    uint16_t copied = pbuf_copy_partial(p, tmp_buff, p->tot_len, 0);
    int ret = 0;
    if (copied == p->tot_len) {
        ret = luat_netdrv_napt_pkg_input(id, tmp_buff, copied);
    } else {
        LLOGW("NAPT链式pbuf拷贝不完整 %d/%d", copied, p->tot_len);
    }
    luat_heap_opt_free(LUAT_HEAP_AUTO, tmp_buff);
    return ret;
}

void luat_netdrv_napt_enable(int adapter_id) {
    if (adapter_id > 0) {
        luat_netdrv_napt_init_contexts();
    }
    s_gw_adapter_id = adapter_id;
    napt_sync_gw_netif(adapter_id);
    // struct netif* gprsnet = net_lwip_get_netif(adapter_id);
    // LLOGI("NAPT enable: adapter=%d, gprsnet=%p ip=%08X", adapter_id, gprsnet, gprsnet ? ip_addr_get_ip4_u32(&gprsnet->ip_addr) : 0);
    // luat_netdrv_t* drv = luat_netdrv_get(adapter_id);
    // if (drv != NULL && drv->netif != NULL) {
    //     LLOGI("luat_netdrv_get(%d) IP %08X", adapter_id, ip_addr_get_ip4_u32(&drv->netif->ip_addr));
    // } else {
    //     LLOGW("luat_netdrv_get(%d) 返回空或netif为空", adapter_id);
    // }
    if (adapter_id > 0) {
        luat_netdrv_t* gw = luat_netdrv_get(adapter_id);
        if (gw && gw->netif) {
            ip4_addr_t* gw_ip = &gw->netif->gw;
            if (!ip4_addr_isany(gw_ip)) {
                LLOGE("NAPT enable: sending ARP request for gw %08X", gw_ip->addr);
                err_t err = etharp_query(gw->netif, gw_ip, NULL);
                LLOGE("NAPT enable: etharp_query result=%d", err);
            } else {
                LLOGE("NAPT enable: gateway IP is empty!");
            }
        }
    }
}

void luat_netdrv_napt_disable(void) {
    if (s_gw_adapter_id < 0) {
        LLOGD("NAPT已经是关闭状态");
        return;
    }
    LLOGI("关闭NAPT, 清理所有映射表, 原网关适配器=%d", s_gw_adapter_id);
    luat_netdrv_napt_tcp_cleanup();
    luat_netdrv_napt_udp_cleanup();
    luat_netdrv_napt_icmp_cleanup();
    s_gw_adapter_id = -1;
}
void luat_netdrv_napt_set_gw(int adapter_id) {
    LLOGD("NAPT set_gw: adapter=%d", adapter_id);
    s_gw_adapter_id = adapter_id;
    napt_sync_gw_netif(adapter_id);
    if (adapter_id > 0) {
        luat_netdrv_t* gw = luat_netdrv_get(adapter_id);
        if (gw && gw->netif) {
            ip4_addr_t* gw_ip = &gw->netif->gw;
            if (!ip4_addr_isany(gw_ip)) {
                err_t err = etharp_query(gw->netif, gw_ip, NULL);
                LLOGD("NAPT set_gw: ARP query gw=%08X result=%d", gw_ip->addr, err);
            }
        }
    }
}


/* Air8000: expose current NAPT gateway adapter_id (used by CSDK wrap_ip_input.c) */
int luat_netdrv_napt_get_gw_adapter(void) {
    return s_gw_adapter_id;
}
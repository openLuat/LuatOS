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

#define LUAT_LOG_TAG "netdrv.napt"
#include "luat_log.h"

#define UDP_MAP_TIMEOUT (60 * 1000)
#define NAPT_MAX_PACKET_SIZE (1520)

static int s_gw_adapter_id = -1;

#if !defined(LUAT_USE_PSRAM) && !defined(LUAT_USE_NETDRV_NAPT)
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    return 0;
}
#else
__NETDRV_CODE_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
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
}
 

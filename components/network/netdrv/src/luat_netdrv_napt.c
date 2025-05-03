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

#define LUAT_LOG_TAG "netdrv.napt"
#include "luat_log.h"

#define ICMP_MAP_SIZE (32)
#define IP_MAP_SIZE (1024)

/* napt icmp id range: 3000-65535 */
#define NAPT_ICMP_ID_RANGE_START     0xBB8
#define NAPT_ICMP_ID_RANGE_END       0xFFFF

int luat_netdrv_gw_adapter_id = -1;

#define u32 uint32_t
#define u16 uint16_t
#define u8 uint8_t
#define NAPT_ETH_HDR_LEN             sizeof(struct ethhdr)
#define NAPT_CHKSUM_16BIT_LEN        sizeof(u16)

#ifndef __USER_FUNC_IN_RAM__
#define __USER_FUNC_IN_RAM__ 
#endif

#if !defined(LUAT_USE_PSRAM) && !defined(LUAT_USE_NETDRV_NAPT)
__USER_FUNC_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    return 0;
}
#else
__USER_FUNC_IN_RAM__ int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len) {
    if (luat_netdrv_gw_adapter_id < 0) {
        // LLOGD("NAPT 未开启");
        return 0; // NAPT没有开启
    }
    luat_netdrv_t* net = luat_netdrv_get(id);
    if (net == NULL || net->netif == NULL) {
        LLOGD("网关netif不存在,无法转发");
        return 0;
    }
    if (len < 24 || len > 1600) {
        LLOGD("包长度不合法, 拒绝改写 %d", len);
        return 0;
    }
    
    // 首先, 如果是eth网卡, 需要先判断是不是广播包
    napt_ctx_t ctx = {
        .buff = buff,
        .len = len,
        .iphdr = (struct ip_hdr*)(buff + SIZEOF_ETH_HDR),
        .eth = (struct eth_hdr*)buff,
        .is_wnet = luat_netdrv_gw_adapter_id == id,
        .net = net
    };

    if (net->netif->flags & NETIF_FLAG_ETHARP) {
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
            if (luat_netdrv_gw_adapter_id == id) {
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
                    luat_netdrv_t* gw = luat_netdrv_get(luat_netdrv_gw_adapter_id);
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
    if (luat_netdrv_gw_adapter_id != id && ctx.iphdr->dest.addr == ip_addr_get_ip4_u32(&net->netif->ip_addr)) {
        // LLOGD("是本网关的包, 不需要执行napt");
        return 0;
    }
    if (IPH_PROTO(ctx.iphdr) != IP_PROTO_UDP && IPH_PROTO(ctx.iphdr) != IP_PROTO_TCP && IPH_PROTO(ctx.iphdr) != IP_PROTO_ICMP) {
        // LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }
    // LLOGD("按协议类型, 使用对应的NAPT修改器进行处理 id %d proto %d", id, IPH_PROTO(ctx.iphdr));
    uint64_t tbegin = luat_mcu_tick64();
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
        LLOGD("不是tcp/udp/icmp包, 不需要执行napt");
        return 0;
    }
    uint64_t tend = luat_mcu_tick64();
    uint64_t tused_us = (tend - tbegin) / luat_mcu_us_period();
    LLOGI("time used %lld us tp %d", tused_us, IPH_PROTO(ctx.iphdr));
    return ret;
}
#endif

static uint8_t napt_buff[1600];
err_t netdrv_ip_input_cb(int id, struct pbuf *p, struct netif *inp) {
    if (p->tot_len > 1600) {
        return 1;
    }
    if (p->tot_len < 24) {
        return 1;
    }
    pbuf_copy_partial(p, napt_buff, p->tot_len, 0);
    int ret = luat_netdrv_napt_pkg_input(id, napt_buff, p->tot_len);
    // LLOGD("napt_pkg_input ret %d", ret);
    return ret == 0 ? 1 : 0;
    // return 1;
}

// 辅助函数
int luat_netdrv_napt_pkg_input_pbuf(int id, struct pbuf* p) {
    if (p == NULL || p->tot_len > 1600) {
        return 0;
    }
    // LLOGD("pbuf情况 total %d len %d", p->tot_len, p->len);
    if (p->tot_len == p->len) {
        // LLOGD("其实就是单个pbuf");
        return luat_netdrv_napt_pkg_input(id, p->payload, p->tot_len);
    }
    return 0; // lwip继续处理 
}


// --- TCP/UDP的映射关系维护

static luat_rtos_mutex_t tcp_mutex;
static luat_netdrv_napt_llist_t node_head;

// 端口分配
#define NAPT_TCP_RANGE_START     0x1BBC
#define NAPT_TCP_RANGE_END       0x5AAA
// static uint32_t port_used;
static u16 luat_napt_tcp_port_alloc(void) {
    luat_netdrv_napt_llist_t* head = node_head.next;
    size_t used = 0;
    for (size_t i = NAPT_TCP_RANGE_END; i <= NAPT_TCP_RANGE_START; i++)
    {
        head = node_head.next;
        used = 0;
        while (head != NULL) {
            if (head->item.wnet_local_port == i) {
                used = 1;
                break;
            }
            head = head->next;
        }
        if (used == 0) {
            return i;
        }
    }
    return 0;
}

// 外网到内网
int luat_netdrv_napt_tcp_wan2lan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping) {
    int ret = -1;
    luat_netdrv_napt_llist_t* head = node_head.next;
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr* ip_hdr = ctx->iphdr;
    uint64_t tnow = luat_mcu_tick64_ms();
    luat_netdrv_napt_tcpudp_t tmp = {0};
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);

    tmp.wnet_ip = ctx->iphdr->src.addr;
    tmp.wnet_port = tcp_hdr->src;
    tmp.wnet_local_port = tcp_hdr->dest;

    // TODO Lock
    if (tcp_mutex == NULL) {
        luat_rtos_mutex_create(&tcp_mutex);
    }
    luat_rtos_mutex_lock(tcp_mutex, 5000);
    while (head != NULL) {
        if (memcmp(&tmp.wnet_ip, &head->item.wnet_ip, 8) == 0) {
            memcpy(mapping, &head->item, sizeof(luat_netdrv_napt_tcpudp_t));
            head->item.tm_ms = tnow;
            ret = 0;
            break;
        }
        head = head->next;
    }
    // TODO UnLock
    luat_rtos_mutex_unlock(tcp_mutex);
    return ret;
}

// 内网到外网
int luat_netdrv_napt_tcp_lan2wan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping) {
    int ret = -1;
    luat_netdrv_napt_llist_t* head = node_head.next;
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr* ip_hdr = ctx->iphdr;
    uint64_t tnow = luat_mcu_tick64_ms();
    luat_netdrv_napt_tcpudp_t tmp = {0};
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);

    tmp.inet_ip = ctx->iphdr->src.addr;
    tmp.inet_port = tcp_hdr->src;
    tmp.wnet_ip = ctx->iphdr->dest.addr;
    tmp.wnet_port = tcp_hdr->dest;

    if (tcp_mutex == NULL) {
        luat_rtos_mutex_create(&tcp_mutex);
    }
    luat_rtos_mutex_lock(tcp_mutex, 5000);

    while (head != NULL) {
        if (memcmp(&tmp.inet_ip, &head->item.inet_ip, 8 + 8) == 0) {
            memcpy(mapping, &head->item, sizeof(luat_netdrv_napt_tcpudp_t));
            head->item.tm_ms = tnow;
            ret = 0;
            break;
        }
        head = head->next;
    }
    while (ret != 0) {
        tmp.wnet_local_port = luat_napt_tcp_port_alloc();
        if (tmp.wnet_local_port == 0) {
            LLOGE("TCP映射关系已经用完");
            ret = - 2;
            break;
        }
        // 没找到, 那就新增一个
        luat_netdrv_napt_llist_t* node = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, sizeof(luat_netdrv_napt_llist_t));
        if (node == NULL) {
            // 内存不够了
            ret = -3;
            break;
        }
        else {
            node->item.wnet_local_port = tcp_hdr->dest;
            memcpy(&node->item, mapping, sizeof(luat_netdrv_napt_tcpudp_t));
            node->item.tm_ms = luat_mcu_tick64_ms();
            node->next = node_head.next;
            node_head.next = node;
            ret = 0;
        }
        break;
    }

    // unlock
    luat_rtos_mutex_unlock(tcp_mutex);

    return ret;
}

int luat_netdrv_napt_watch_task_main(void) {
    return 0;
}

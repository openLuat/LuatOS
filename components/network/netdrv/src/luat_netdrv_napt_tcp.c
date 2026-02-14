#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_napt.h"
#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/etharp.h"
#include "lwip/tcp.h"
#include "lwip/prot/tcp.h"
#include "luat_mcu.h"
#include "lwip/ip_addr.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "netdrv.napt.tcp"
#include "luat_log.h"

static uint8_t *tcp_buff;
extern luat_netdrv_napt_ctx_t *g_napt_tcp_ctx;

__NETDRV_CODE_IN_RAM__ int luat_napt_tcp_handle(napt_ctx_t* ctx) {
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr* ip_hdr = ctx->iphdr;
    struct tcp_hdr *tcp_hdr = (struct tcp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);
    luat_netdrv_t* gw = ctx->drv_gw;
    int ret = 0;
    if (gw == NULL || gw->netif == NULL) {
        return 0;
    }
    if (tcp_buff == NULL) {
        tcp_buff = luat_heap_opt_zalloc(LUAT_HEAP_AUTO, 1600);
        if (tcp_buff == NULL) {
            LLOGE("NAPT TCP缓冲区分配失败");
            return 0;
        }
    }
    // uint64_t tnow = luat_mcu_tick64_ms();
    luat_netdrv_napt_tcpudp_t mapping = {0};
    if (ctx->is_wnet) {
        // 这是从外网到内网的TCP包
        // LLOGD("wnet.search dst port %d", ntohs(tcp_hdr->dest));
        ret = luat_netdrv_napt_tcp_wan2lan(ctx, &mapping, g_napt_tcp_ctx);
        if (ret == 0) {
            // 修改目标端口
            uint16_t old_dst_port = tcp_hdr->dest;
            uint32_t old_dst_ip = ip_hdr->dest.addr;
            uint16_t ip_sum = ip_hdr->_chksum;
            uint16_t tcp_sum = tcp_hdr->chksum;
            tcp_hdr->dest = mapping.inet_port;

            // 修改目标地址到内网地址,并增量更新ip的checksum
            ip_hdr->dest.addr = mapping.inet_ip;
            ip_sum = napt_chksum_replace_u32(ip_sum, old_dst_ip, mapping.inet_ip);
            IPH_CHKSUM_SET(ip_hdr, ip_sum);

            // 重新计算TCP的checksum
            if (tcp_sum)
            {
                tcp_sum = napt_chksum_replace_u32(tcp_sum, old_dst_ip, mapping.inet_ip);
                tcp_sum = napt_chksum_replace_u16(tcp_sum, old_dst_port, mapping.inet_port);
                tcp_hdr->chksum = tcp_sum;
            }
            else
            {
                tcp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                       ip_hdr->dest.addr,
                                                       IP_PROTO_TCP,
                                                       (u16 *)tcp_hdr,
                                                       ntohs(ip_hdr->_len) - iphdr_len);
            }
            return napt_output_to_lan(ctx, &mapping, ip_hdr, tcp_buff);
        }
        // LLOGD("没有找到TCP映射关系, 放行给LWIP处理");
        return 0;
    }
    else {
        // 内网, 尝试对外网的请求吗?
        if (ip_hdr->dest.addr == ip_addr_get_ip4_u32(&ctx->net->netif->ip_addr)) {
            return 0; // 对网关的TCP请求, 交给LWIP处理
        }
        ret = luat_netdrv_napt_tcp_lan2wan(ctx, &mapping, g_napt_tcp_ctx);
        if (ret != 0)
            return 0;
        // 改写源地址/端口 + 校验和
        uint16_t old_src_port = tcp_hdr->src;
        uint32_t old_src_ip = ip_hdr->src.addr;
        uint32_t new_src_ip = ip_addr_get_ip4_u32(&gw->netif->ip_addr);
        uint16_t ip_sum = ip_hdr->_chksum;
        uint16_t tcp_sum = tcp_hdr->chksum;
        ip_hdr->src.addr = new_src_ip;
        IPH_CHKSUM_SET(ip_hdr, napt_chksum_replace_u32(ip_sum, old_src_ip, new_src_ip));
        tcp_hdr->src = mapping.wnet_local_port;
        if (tcp_sum) {
            tcp_sum = napt_chksum_replace_u32(tcp_sum, old_src_ip, new_src_ip);
            tcp_hdr->chksum = napt_chksum_replace_u16(tcp_sum, old_src_port, mapping.wnet_local_port);
        } else {
            tcp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr, ip_hdr->dest.addr,
                IP_PROTO_TCP, (u16*)tcp_hdr, ntohs(ip_hdr->_len) - iphdr_len);
        }
        return napt_output_to_wan(ctx, gw, ip_hdr);
    }
    // return 0;
}

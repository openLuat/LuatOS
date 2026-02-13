#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_napt.h"
#include "lwip/pbuf.h"
#include "lwip/ip.h"
#include "lwip/etharp.h"
#include "lwip/udp.h"
#include "luat_mcu.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "netdrv.napt.udp"
#include "luat_log.h"

extern luat_netdrv_napt_ctx_t *g_napt_udp_ctx;

static uint8_t *udp_buff;

__NETDRV_CODE_IN_RAM__ int luat_napt_udp_handle(napt_ctx_t *ctx)
{
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr *ip_hdr = ctx->iphdr;
    struct udp_hdr *udp_hdr = (struct udp_hdr *)(((uint8_t *)ctx->iphdr) + iphdr_len);
    luat_netdrv_t *gw = ctx->drv_gw;
    int ret = 0;
    if (gw == NULL || gw->netif == NULL) {
        return 0;
    }
    if (udp_buff == NULL)
    {
        udp_buff = luat_heap_opt_zalloc(LUAT_HEAP_AUTO, 1600);
        if (udp_buff == NULL) {
            LLOGE("NAPT UDP缓冲区分配失败");
            return 0;
        }
    }
    // uint64_t tnow = luat_mcu_tick64_ms();
    luat_netdrv_napt_tcpudp_t mapping = {0};
    if (ctx->is_wnet)
    {
        // 这是从外网到内网的UDP包
        ret = luat_netdrv_napt_tcp_wan2lan(ctx, &mapping, g_napt_udp_ctx);
        if (ret == 0)
        {
            // 找到映射关系了!!! 修改目标ID
            uint16_t old_dst_port = udp_hdr->dest;
            uint32_t old_dst_ip = ip_hdr->dest.addr;
            udp_hdr->dest = mapping.inet_port;

            // 修改目标地址到内网地址,并增量更新ip的checksum
            uint16_t ip_sum = ip_hdr->_chksum;
            ip_hdr->dest.addr = mapping.inet_ip;
            ip_sum = napt_chksum_replace_u32(ip_sum, old_dst_ip, mapping.inet_ip);
            IPH_CHKSUM_SET(ip_hdr, ip_sum);

            // 重新计算UDP的checksum
            if (udp_hdr->chksum)
            {
                udp_hdr->chksum = napt_chksum_replace_u32(udp_hdr->chksum, old_dst_ip, mapping.inet_ip);
                udp_hdr->chksum = napt_chksum_replace_u16(udp_hdr->chksum, old_dst_port, mapping.inet_port);
            }
            else
            {
                udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                       ip_hdr->dest.addr,
                                                       IP_PROTO_UDP,
                                                       (u16 *)udp_hdr,
                                                       ntohs(ip_hdr->_len) - iphdr_len);
            }
            return napt_output_to_lan(ctx, &mapping, ip_hdr, udp_buff);
        }
        // LLOGD("没有找到UDP映射关系, 放行给LWIP处理");
        return 0;
    }
    else
    {
        // 内网, 尝试对外网的请求吗?
        if (ip_hdr->dest.addr == ip_addr_get_ip4_u32(&ctx->net->netif->ip_addr))
        {
            return 0; // 对网关的UDP请求, 交给LWIP处理
        }
        ret = luat_netdrv_napt_tcp_lan2wan(ctx, &mapping, g_napt_udp_ctx);
        if (ret != 0)
            return 0;
        // 改写源地址/端口 + 校验和
        uint16_t old_src_port = udp_hdr->src;
        uint32_t old_src_ip = ip_hdr->src.addr;
        uint32_t new_src_ip = ip_addr_get_ip4_u32(&gw->netif->ip_addr);
        uint16_t ip_sum = ip_hdr->_chksum;
        ip_hdr->src.addr = new_src_ip;
        IPH_CHKSUM_SET(ip_hdr, napt_chksum_replace_u32(ip_sum, old_src_ip, new_src_ip));
        udp_hdr->src = mapping.wnet_local_port;
        if (udp_hdr->chksum) {
            udp_hdr->chksum = napt_chksum_replace_u32(udp_hdr->chksum, old_src_ip, new_src_ip);
            udp_hdr->chksum = napt_chksum_replace_u16(udp_hdr->chksum, old_src_port, mapping.wnet_local_port);
        } else {
            udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr, ip_hdr->dest.addr,
                IP_PROTO_UDP, (u16*)udp_hdr, ntohs(ip_hdr->_len) - iphdr_len);
        }
        return napt_output_to_wan(ctx, gw, ip_hdr);
    }
    // return 0;
}

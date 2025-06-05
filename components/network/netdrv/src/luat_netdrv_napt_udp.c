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

#define u32 uint32_t
#define u16 uint16_t
#define u8 uint8_t
#define NAPT_ETH_HDR_LEN sizeof(struct ethhdr)

static uint8_t *udp_buff;
int luat_napt_udp_handle(napt_ctx_t *ctx)
{
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr *ip_hdr = ctx->iphdr;
    struct udp_hdr *udp_hdr = (struct udp_hdr *)(((uint8_t *)ctx->iphdr) + iphdr_len);
    luat_netdrv_t *gw = ctx->drv_gw;
    int ret = 0;
    if (udp_buff == NULL)
    {
        udp_buff = luat_heap_opt_zalloc(LUAT_HEAP_SRAM, 1600);
    }
    uint64_t tnow = luat_mcu_tick64_ms();
    luat_netdrv_napt_tcpudp_t mapping = {0};
    if (ctx->is_wnet)
    {
        // 这是从外网到内网的UDP包
        ret = luat_netdrv_napt_tcp_wan2lan(ctx, &mapping, g_napt_udp_ctx);
        if (ret == 0)
        {
            // 找到映射关系了!!! 修改目标ID
            udp_hdr->dest = mapping.inet_port;

            // 修改目标地址到内网地址,并重新计算ip的checksum
            ip_hdr->dest.addr = mapping.inet_ip;
            ip_hdr->_chksum = 0;
            ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

            // 重新计算icmp的checksum
            if (udp_hdr->chksum)
            {
                udp_hdr->chksum = 0;
                udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                       ip_hdr->dest.addr,
                                                       IP_PROTO_UDP,
                                                       (u16 *)udp_hdr,
                                                       ntohs(ip_hdr->_len) - iphdr_len);
            }

            // 如果是ETH包, 那还需要修改源MAC和目标MAC
            if (ctx->eth)
            {
                memcpy(ctx->eth->src.addr, ctx->net->netif->hwaddr, 6);
                memcpy(ctx->eth->dest.addr, mapping.inet_mac, 6);
            }
            luat_netdrv_t *dst = luat_netdrv_get(mapping.adapter_id);
            if (dst == NULL)
            {
                LLOGE("能找到UDP映射关系, 但目标netdrv不存在, 这肯定是BUG啊!!");
                return 1;
            }
            if (dst->dataout)
            {
                if (ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP)
                {
                    // LLOGD("输出到内网netdrv,无需额外添加eth头");
                    dst->dataout(dst, dst->userdata, ctx->eth, ctx->len);
                }
                else if (!ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP)
                {
                    // 需要补全一个ETH头部
                    memcpy(udp_buff, mapping.inet_mac, 6);
                    memcpy(udp_buff + 6, dst->netif->hwaddr, 6);
                    memcpy(udp_buff + 12, "\x08\x00", 2);
                    memcpy(udp_buff + 14, ip_hdr, ctx->len);
                    dst->dataout(dst, dst->userdata, udp_buff, ctx->len + 14);
                    // LLOGD("输出到内网netdrv,已额外添加eth头");
                    // luat_netdrv_print_pkg("下行数据", udp_buff, ctx->len + 14);
                }
                else
                {
                    // 那就是IP2IP, 不需要加ETH头了
                    dst->dataout(dst, dst->userdata, ip_hdr, ctx->len);
                }
            }
            else
            {
                LLOGE("能找到UDP映射关系, 但目标netdrv不支持dataout!!");
            }
            return 1; // 全部修改完成
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
        if (ret != 0) {
            return 0;
        }
        // 2. 修改信息
        ip_hdr->src.addr = ip_addr_get_ip4_u32(&gw->netif->ip_addr);
        udp_hdr->src = mapping.wnet_local_port;
        // 3. 与ICMP不同, 先计算IP的checksum
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);
        // 4. 计算IP包的checksum
        if (udp_hdr->chksum)
        {
            udp_hdr->chksum = 0;
            udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                   ip_hdr->dest.addr,
                                                   IP_PROTO_UDP,
                                                   (u16 *)udp_hdr,
                                                   ntohs(ip_hdr->_len) - iphdr_len);
            // udp_hdr->chksum = 0; // 强制不校验
        }

        // 发送出去
        if (gw && gw->dataout && gw->netif)
        {
            // LLOGD("ICMP改写完成, 发送到GW");
            if (gw->netif->flags & NETIF_FLAG_ETHARP)
            {
                if (ctx->eth)
                {
                    memcpy(ctx->eth->dest.addr, gw->gw_mac, 6);
                    gw->dataout(gw, gw->userdata, ctx->eth, ctx->len);
                }
                else
                {
                    LLOGD("网关netdrv是ETH,源网卡不是ETH, 当前不支持");
                    return 0;
                }
            }
            else
            {
                if (ctx->eth)
                {
                    gw->dataout(gw, gw->userdata, ip_hdr, ctx->len - 14);
                }
                else
                {
                    gw->dataout(gw, gw->userdata, ip_hdr, ctx->len);
                }
            }
        }
        else
        {
            LLOGD("UDP改写完成, 但GW不支持dataout回调?!!");
        }
        return 1;
    }
    return 0;
}

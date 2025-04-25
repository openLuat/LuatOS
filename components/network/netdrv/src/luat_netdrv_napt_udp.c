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

#ifdef LUAT_USE_PSRAM
#define UDP_MAP_SIZE (8*1024)
#else
#define UDP_MAP_SIZE (1024)
#endif
#define UDP_MAP_TIMEOUT (60*1000)

/* napt udp port range: 7100-23210 */
#define NAPT_UDP_RANGE_START     0x1BBC
#define NAPT_UDP_RANGE_END       0x5AAA

extern int luat_netdrv_gw_adapter_id;
static uint16_t napt_curr_id = NAPT_UDP_RANGE_START;
static luat_netdrv_napt_tcpudp_t* udps;

#define u32 uint32_t
#define u16 uint16_t
#define u8 uint8_t
#define NAPT_ETH_HDR_LEN             sizeof(struct ethhdr)



static u16 luat_napt_udp_port_alloc(void)
{
    u16 cnt = 0;

again:
    if (napt_curr_id++ == NAPT_UDP_RANGE_END)
    {
        napt_curr_id = NAPT_UDP_RANGE_START;
    }

    for (size_t i = 0; i < UDP_MAP_SIZE; i++)
    {
        if (napt_curr_id == udps[i].wnet_local_port)
        {
            if (++cnt > (NAPT_UDP_RANGE_END - NAPT_UDP_RANGE_START))
            {
                return 0;
            }

	       goto again;
        }
    }

    return napt_curr_id;
}

static uint8_t *udp_buff;
int luat_napt_udp_handle(napt_ctx_t* ctx) {
    uint16_t iphdr_len = (ctx->iphdr->_v_hl & 0x0F) * 4;
    struct ip_hdr* ip_hdr = ctx->iphdr;
    struct udp_hdr *udp_hdr = (struct udp_hdr*)(((uint8_t*)ctx->iphdr) + iphdr_len);
    luat_netdrv_t* gw = luat_netdrv_get(luat_netdrv_gw_adapter_id);
    if (gw == NULL || gw->netif == NULL) {
        return 0;
    }
    if (udps == NULL) {
        udps = luat_heap_opt_zalloc(LUAT_HEAP_PSRAM, sizeof(luat_netdrv_napt_tcpudp_t) * UDP_MAP_SIZE);
    }
    if (udp_buff == NULL) {
        udp_buff = luat_heap_opt_zalloc(LUAT_HEAP_SRAM, 1600);
    }
    uint64_t tnow = luat_mcu_tick64_ms();
    if (ctx->is_wnet) {
        // 这是从外网到内网的UDP包
        for (size_t i = 0; i < UDP_MAP_SIZE; i++)
        {
            if (udps[i].is_vaild == 0) {
                continue;
            }
            if (udps[i].is_vaild && (tnow - udps[i].tm_ms) > UDP_MAP_TIMEOUT) {
                udps[i].is_vaild = 0;
                continue;
            }
            // TODO 是否还应该校验远程IP呢?

            // 下行的目标端口, 与本地端口, 是否一直
            if (udp_hdr->dest == udps[i].wnet_local_port) {
                // 找到映射关系了!!!
                // LLOGD("UDP port %u -> %d", ntohs(udp_hdr->dest), ntohs(udps[i].inet_port));
                // 修改目标ID
                udp_hdr->dest = udps[i].inet_port;

                // 修改目标地址到内网地址,并重新计算ip的checksu
                ip_hdr->dest.addr = udps[i].inet_ip;
                ip_hdr->_chksum = 0;
                ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);

                // 重新计算icmp的checksum
                if (udp_hdr->chksum) {
                    udp_hdr->chksum = 0;
                    udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                   ip_hdr->dest.addr,
                                                   IP_PROTO_UDP,
                                                   (u16 *)udp_hdr,
                                                   ntohs(ip_hdr->_len) - iphdr_len);
                }

                // 如果是ETH包, 那还需要修改源MAC和目标MAC
                if (ctx->eth) {
                    memcpy(ctx->eth->src.addr, ctx->net->netif->hwaddr, 6);
                    memcpy(ctx->eth->dest.addr, udps[i].inet_mac, 6);
                }
                luat_netdrv_t* dst = luat_netdrv_get(udps[i].adapter_id);
                if (dst == NULL) {
                    LLOGE("能找到UDP映射关系, 但目标netdrv不存在, 这肯定是BUG啊!!");
                    return 1;
                }
                if (dst->dataout) {
                    if (ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
                        // LLOGD("输出到内网netdrv,无需额外添加eth头");
                        dst->dataout(dst, dst->userdata, ctx->eth, ctx->len);
                    }
                    else if (!ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
                        // 需要补全一个ETH头部
                        memcpy(udp_buff, udps[i].inet_mac, 6);
                        memcpy(udp_buff + 6, dst->netif->hwaddr, 6);
                        memcpy(udp_buff + 12, "\x08\x00", 2);
                        memcpy(udp_buff + 14, ip_hdr, ctx->len);
                        dst->dataout(dst, dst->userdata, udp_buff, ctx->len + 14);
                        // LLOGD("输出到内网netdrv,已额外添加eth头");
                        // luat_netdrv_print_pkg("下行数据", udp_buff, ctx->len + 14);
                    }
                    else {
                        // 那就是IP2IP, 不需要加ETH头了
                        dst->dataout(dst, dst->userdata, ip_hdr, ctx->len);
                    }
                }
                else {
                    LLOGE("能找到UDP映射关系, 但目标netdrv不支持dataout!!");
                }
                return 1; // 全部修改完成,
            }
        }
        // LLOGD("没有找到UDP映射关系, 放行给LWIP处理");
        return 0;
    }
    else {
        // 内网, 尝试对外网的请求吗?
        if (ip_hdr->dest.addr == ip_addr_get_ip4_u32(&ctx->net->netif->ip_addr)) {
            return 0; // 对网关的UDP请求, 交给LWIP处理
        }
        // 寻找一个空位
        // 第一轮循环, 是否有已知映射
        luat_netdrv_napt_tcpudp_t* it = NULL;
        luat_netdrv_napt_tcpudp_t* it_map = NULL;
        for (size_t i = 0; i < UDP_MAP_SIZE; i++)
        {
            it = &udps[i];
            if (it->is_vaild == 0) {
                continue;
            }
            if ((tnow - it->tm_ms) > UDP_MAP_TIMEOUT) {
                it->is_vaild = 0;
                it->tm_ms = 0;
                continue;
            }
            // 几个要素都要相同 源IP/源端口/目标IP/目标端口, 如果是MAC包, 源MAC也要相同
            if (it->inet_ip != ip_hdr->src.addr) {
                // LLOGD("源IP不匹配, 继续下一条");
                continue;
            }
            if (it->inet_port != udp_hdr->src) {
                // LLOGD("源port不匹配, 继续下一条");
                continue;
            }
            if (it->wnet_ip != ip_hdr->dest.addr) {
                // LLOGD("目标IP不匹配, 继续下一条");
                continue;
            }
            if (it->wnet_port != udp_hdr->dest) {
                // LLOGD("目标port不匹配, 继续下一条");
                continue;
            }
            if (ctx->eth && memcmp(ctx->eth->src.addr, it->inet_mac, 6)) {
                // LLOGD("源MAC不匹配, 继续下一条");
                continue;
            }
            // 都相同, 那就是同一个映射了, 可以服用
            it->tm_ms = tnow;
            it_map = it;
        }
        if (it_map == NULL) {
            for (size_t i = 0; i < UDP_MAP_SIZE; i++) {
                it = &udps[i];
                if (it->is_vaild) {
                    continue;
                }
                // 有空位了, 马上分配
                it_map = it;
                it->adapter_id = ctx->net->id;
                it->inet_port = udp_hdr->src;
                it->wnet_port = udp_hdr->dest;
                it->inet_ip = ip_hdr->src.addr;
                it->wnet_ip = ip_hdr->dest.addr;
                it->wnet_local_port = luat_napt_udp_port_alloc();
                it->tm_ms = tnow;
                if (ctx->eth) {
                    memcpy(it->inet_mac, ctx->eth->src.addr, 6);
                }
                it->is_vaild = 1;
                //LLOGD("分配新的UDP映射 inet %d wnet %d", it->inet_port, it->wnet_local_port);
                break;
            }
            if (it_map == NULL) {
                LLOGE("没有空闲的UDP映射了!!!!");
                return 0;
            }
        }
        it->tm_ms = tnow;
        // 2. 修改信息
        ip_hdr->src.addr = ip_addr_get_ip4_u32(&gw->netif->ip_addr);
        udp_hdr->src = it_map->wnet_local_port;
        // 3. 与ICMP不同, 先计算IP的checksum
        ip_hdr->_chksum = 0;
        ip_hdr->_chksum = alg_iphdr_chksum((u16 *)ip_hdr, iphdr_len);
        // 4. 计算IP包的checksum
        if (udp_hdr->chksum) {
            udp_hdr->chksum = 0;
            udp_hdr->chksum = alg_tcpudphdr_chksum(ip_hdr->src.addr,
                                                   ip_hdr->dest.addr,
                                                   IP_PROTO_UDP,
                                                   (u16 *)udp_hdr,
                                                   ntohs(ip_hdr->_len) - iphdr_len);
            // udp_hdr->chksum = 0; // 强制不校验
        }

        // 发送出去
        if (gw && gw->dataout && gw->netif) {
            // LLOGD("ICMP改写完成, 发送到GW");
            if (gw->netif->flags & NETIF_FLAG_ETHARP) {
                if (ctx->eth) {
                    memcpy(ctx->eth->dest.addr, gw->gw_mac, 6);
                    gw->dataout(gw, gw->userdata, ctx->eth, ctx->len);
                }
                else {
                    LLOGD("网关netdrv是ETH,源网卡不是ETH, 当前不支持");
                    return 0;
                }
            }
            else {
                if (ctx->eth) {
                    gw->dataout(gw, gw->userdata, ip_hdr, ctx->len - 14);
                }
                else {
                    gw->dataout(gw, gw->userdata, ip_hdr, ctx->len);
                }
            }
        }
        else {
            LLOGD("UDP改写完成, 但GW不支持dataout回调?!!");
        }
        return 1;
    }
    return 0;
}

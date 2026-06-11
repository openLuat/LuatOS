/*
 * luat_netdrv_lwip_compat.c
 *
 * 见 luat_netdrv_lwip_compat.h 头文件注释.
 *
 * 该文件实现 luat_netdrv_ip4_input - 一个最小子集的 IPv4 入栈分发函数,
 * 仅供 LuatOS netdrv 注册的叶子 netif 使用.
 *
 * 我们直接调用 PLAT/lwIP 已经导出的标准下游 API
 *   raw_input / udp_input / tcp_input / icmp_input
 * 并写入 PLAT/lwIP 全局变量 ip_data 来设置当前包的上下文.
 * 这样做不依赖任何 PLAT 私有 API, 也不会跟下游协议栈分发产生冲突
 * (PCB 表 / 全局状态都是 PLAT lwIP 那一份).
 *
 * 与标准 lwIP ip4_input 相比, 我们去掉了下列功能:
 *   - 扫所有 netif 看包给谁 (我们的 netif 是叶子, 包必然给本机)
 *   - ip4_forward / NAT64 / CLAT
 *   - PLAT 私有的 ip4_input_adpt_process + NetGetBind*
 *   - PLAT 私有的 NetifIncreaseLoad 流量统计 (LuatOS netdrv 不需要)
 *   - IGMP (PLAT 通常未编译)
 *   - LWIP_HOOK_IP4_INPUT (LuatOS 暂不用)
 *
 * 异常路径 fallback: IP options 长 / 分片 / IP 版本异常 / IP 头校验失败,
 * 都直接 pbuf_free, 不再 fallback 给 PLAT ip4_input,
 * 因为 PLAT ip4_input 对 LuatOS netif 的处理本来就有那个 bug.
 */

#include "lwip/opt.h"
#include "lwip/ip.h"
#include "lwip/ip4.h"
#include "lwip/inet_chksum.h"
#include "lwip/raw.h"
#include "lwip/udp.h"
#include "lwip/tcp.h"
#include "lwip/icmp.h"
#include "lwip/pbuf.h"
#include "lwip/netif.h"
#include "lwip/prot/ip4.h"
#include "lwip/stats.h"

#include "luat_netdrv_lwip_compat.h"

/* PLAT/lwIP 导出的全局, 用于给下游 input 提供当前包的上下文 */
extern struct ip_globals ip_data;

void luat_netdrv_ip4_input(struct pbuf *p, struct netif *inp)
{
    const struct ip_hdr *iphdr;
    u16_t iphdr_hlen;
    u16_t iphdr_len;

    LWIP_ASSERT("luat_netdrv_ip4_input: invalid pbuf", p != NULL);
    LWIP_ASSERT("luat_netdrv_ip4_input: invalid netif", inp != NULL);

    IP_STATS_INC(ip.recv);
    MIB2_STATS_INC(mib2.ipinreceives);

    /* === 1. 基本头校验 === */
    if (p->len < IP_HLEN) {
        goto drop;
    }
    iphdr = (const struct ip_hdr *)p->payload;
    if (IPH_V(iphdr) != 4) {
        goto drop;
    }

    iphdr_hlen = IPH_HL(iphdr) * 4;
    iphdr_len  = lwip_ntohs(IPH_LEN(iphdr));

    /* header / total 长度合法性 */
    if ((iphdr_hlen < IP_HLEN) || (iphdr_hlen > p->len) || (iphdr_len > p->tot_len) || (iphdr_len < iphdr_hlen)) {
        goto drop;
    }

#if CHECKSUM_CHECK_IP
    IF__NETIF_CHECKSUM_ENABLED(inp, NETIF_CHECKSUM_CHECK_IP) {
        if (inet_chksum(iphdr, iphdr_hlen) != 0) {
            goto drop;
        }
    }
#endif

    /* === 2. 把 tot_len 截到 IP header 声明的长度 === */
    if (iphdr_len < p->tot_len) {
        if (p->len == p->tot_len) {
            pbuf_realloc(p, iphdr_len);
        }
    }

    /* === 3. 处理分片 ===
     * 我们的 ip4_input 不做分片重组, 凡是带 MF 或非零 offset 的, 直接丢.
     * DHCP / TCP / 常见 UDP 都不会分片, 影响极小.
     */
    if ((IPH_OFFSET(iphdr) & PP_HTONS(IP_OFFMASK | IP_MF)) != 0) {
        goto drop;
    }

    /* === 4. 设置全局上下文(下游 input 函数依赖) === */
    ip_addr_copy_from_ip4(ip_data.current_iphdr_dest, iphdr->dest);
    ip_addr_copy_from_ip4(ip_data.current_iphdr_src,  iphdr->src);
    ip_data.current_netif             = inp;
    ip_data.current_input_netif       = inp;
    ip_data.current_ip4_header        = (struct ip_hdr *)iphdr;
    ip_data.current_ip_header_tot_len = iphdr_hlen;

    /* === 5. 剥掉 IP 头, payload 指向上层协议头 === */
    if (pbuf_header(p, -(s16_t)iphdr_hlen)) {
        /* 罕见: 跨 pbuf 链不能 in-place 调整 */
        goto drop_clear_ctx;
    }

    /* === 6. 按 protocol 分发 ===
     * RAW PCB 先尝, 再走下游协议栈.
     */
#if LWIP_RAW
    if (raw_input(p, inp) != 0) {
        /* RAW PCB 吃掉了, 我们不再分发 */
        goto cleanup_ctx;
    }
#endif

    switch (IPH_PROTO(iphdr)) {
#if LWIP_UDP
        case IP_PROTO_UDP:
#if LWIP_UDPLITE
        case IP_PROTO_UDPLITE:
#endif
            udp_input(p, inp);
            break;
#endif
#if LWIP_TCP
        case IP_PROTO_TCP:
            tcp_input(p, inp);
            break;
#endif
#if LWIP_ICMP
        case IP_PROTO_ICMP:
            icmp_input(p, inp);
            break;
#endif
        default:
            /* 未知协议: 静默丢弃 */
            pbuf_free(p);
            IP_STATS_INC(ip.proterr);
            IP_STATS_INC(ip.drop);
            MIB2_STATS_INC(mib2.ipinunknownprotos);
            break;
    }

cleanup_ctx:
    ip_data.current_netif             = NULL;
    ip_data.current_input_netif       = NULL;
    ip_data.current_ip4_header        = NULL;
    ip_data.current_ip_header_tot_len = 0;
    ip4_addr_set_any(ip_2_ip4(&ip_data.current_iphdr_src));
    ip4_addr_set_any(ip_2_ip4(&ip_data.current_iphdr_dest));
    return;

drop_clear_ctx:
    ip_data.current_netif             = NULL;
    ip_data.current_input_netif       = NULL;
    ip_data.current_ip4_header        = NULL;
    ip_data.current_ip_header_tot_len = 0;
    ip4_addr_set_any(ip_2_ip4(&ip_data.current_iphdr_src));
    ip4_addr_set_any(ip_2_ip4(&ip_data.current_iphdr_dest));
    /* fallthrough */
drop:
    IP_STATS_INC(ip.drop);
    pbuf_free(p);
}
/*
 * luat_netdrv_lwip_compat.c
 *
 * 见同目录头文件 luat_netdrv_lwip_compat.h 中的设计动机说明.
 *
 * 本文件提供 luat_netdrv_ip4_input —— 一个最小子集的 IPv4 入栈分发函数,
 * 仅供 LuatOS netdrv 注册的叶子 netif 使用 (airlink wifi 等).
 *
 * 我们直接调用底层 lwIP 实现已经导出的标准下游 API:
 *   raw_input / udp_input / tcp_input / icmp_input
 * 并直接写入 lwIP 全局变量 ip_data 来设置当前包的上下文, 这样:
 *   - 不引入第二份 lwip 实例
 *   - 不依赖任何 vendor-specific 私有 API
 *   - PCB 表 / 全局状态都跟底层 lwip 共享, 业务侧代码 0 改动
 *
 * 与标准 lwIP ip4_input 相比, 我们略去了下列功能:
 *   - 扫所有 netif 查路由 (netdrv 的 netif 是叶子, 包必然给本机)
 *   - ip4_forward / NAT / NAT64 / CLAT
 *   - vendor 私有的 adpt_process / 流量统计
 *   - IGMP (大多数 vendor 未编译)
 *   - LWIP_HOOK_IP4_INPUT
 *
 * 异常分支 (IP options 长 / 分片 / 头校验失败) 直接 pbuf_free.
 *
 * 编译开关: 本文件主体仅在定义了 LUAT_USE_NETDRV_LWIP_ARP 时启用,
 * 跟 luat_netdrv_lwip_netif_ethernet.c 的保护条件保持一致.
 * 在未开启 LWIP-ARP 的 SDK (例如 CCM42xx Air1601) 上, 本文件等同空文件,
 * 不会引入任何对底层 lwip 私有 API 的链接依赖.
 */

#include "luat_base.h"
#include "luat_netdrv_lwip_compat.h"
#include "lwip/opt.h"

#if (LWIP_ARP || LWIP_ETHERNET) && defined(LUAT_USE_NETDRV_LWIP_ARP)

#include "lwip/ip.h"
#include "lwip/ip4.h"
#include "lwip/pbuf.h"
#include "lwip/netif.h"
#include "lwip/prot/ip4.h"
#include "lwip/stats.h"

/*
 * 下面这些函数在标准 lwIP 里属于 'priv' 范畴, 不同 vendor 的头文件组织方式不一致
 * (有的把它们暴露在 lwip/raw.h, 有的塞在 lwip/priv/raw_priv.h, 有的甚至两边都不暴露).
 * 为避免依赖具体头文件路径, 这里手动给出前置声明 —— 链接时只要 vendor 的 liblwip.a
 * 真的导出了这些 T 符号即可 (实测 EC718HM-ims/PLAT lwip 全部导出).
 */
extern u8_t   raw_input(struct pbuf *p, struct netif *inp);
extern void   udp_input(struct pbuf *p, struct netif *inp);
extern void   tcp_input(struct pbuf *p, struct netif *inp);
extern void   icmp_input(struct pbuf *p, struct netif *inp);

/* lwIP 全局上下文变量, 由 vendor liblwip.a 导出. 用于给下游 *_input 提供当前包信息. */
extern struct ip_globals ip_data;

void luat_netdrv_ip4_input(struct pbuf *p, struct netif *inp)
{
    const struct ip_hdr *iphdr;
    u16_t iphdr_hlen;
    u16_t iphdr_len;

    LWIP_ASSERT("luat_netdrv_ip4_input: invalid pbuf",  p   != NULL);
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

    if ((iphdr_hlen < IP_HLEN)
        || (iphdr_hlen > p->len)
        || (iphdr_len  > p->tot_len)
        || (iphdr_len  < iphdr_hlen)) {
        goto drop;
    }

    /* === 2. 把 pbuf 截到 IP header 声明的长度 (上层依赖 tot_len) === */
    if (iphdr_len < p->tot_len) {
        if (p->len == p->tot_len) {
            pbuf_realloc(p, iphdr_len);
        }
    }

    /* === 3. 分片包: 不处理, 直接丢
     * DHCP / 常见 TCP / 常见 UDP 包都不分片, 影响极小.
     */
    if ((IPH_OFFSET(iphdr) & PP_HTONS(IP_OFFMASK | IP_MF)) != 0) {
        goto drop;
    }

    /* === 4. 设置 lwIP 全局上下文 (下游 *_input 依赖) === */
    ip_addr_copy_from_ip4(ip_data.current_iphdr_dest, iphdr->dest);
    ip_addr_copy_from_ip4(ip_data.current_iphdr_src,  iphdr->src);
    ip_data.current_netif             = inp;
    ip_data.current_input_netif       = inp;
    ip_data.current_ip4_header        = (struct ip_hdr *)iphdr;
    ip_data.current_ip_header_tot_len = iphdr_hlen;

    /* === 5. 剥 IP 头, payload 指向 transport header === */
    if (pbuf_header(p, -(s16_t)iphdr_hlen)) {
        /* 跨 pbuf 链不能 in-place 调整, 罕见 */
        goto drop_clear_ctx;
    }

    /* === 6. 按 protocol 分发 ===
     * RAW PCB 优先, 没人接才走标准协议栈.
     */
#if LWIP_RAW
    if (raw_input(p, inp) != 0) {
        /* RAW PCB 吃掉了 */
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

#endif /* (LWIP_ARP || LWIP_ETHERNET) && defined(LUAT_USE_NETDRV_LWIP_ARP) */
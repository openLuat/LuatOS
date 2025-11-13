#include "luat_base.h"
#include "luat_icmp.h"
#include "luat_mem.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_mcu.h"

#include "lwip/init.h"
#include "lwip/prot/icmp.h"
#include "lwip/prot/ip.h"
#if LWIP_IPV6
#include "lwip/prot/ip6.h"
#include "lwip/prot/icmp6.h"
#include "lwip/ip6_addr.h"
#endif
#include "lwip/pbuf.h"
#include "lwip/inet_chksum.h"
#include <stddef.h>

#define LUAT_LOG_TAG "icmp"
#include "luat_log.h"

static luat_icmp_ctx_t* ctxs[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];

uint8_t g_icmp_debug;

static u8_t luat_icmp_recv(void *arg, struct raw_pcb *pcb, struct pbuf *p, const ip_addr_t *addr)
{
    if (p == NULL || addr == NULL) {
        return 0;
    }
    char buff[64] = {0};
    ipaddr_ntoa_r(addr, buff, sizeof(buff));
    if (g_icmp_debug) {
        LLOGD("ICMP recv %p %p %d %s", arg, pcb, p->tot_len, buff);
    }
    uint32_t adapter_id = (uint32_t)arg;
    if (adapter_id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        return 0;
    }
    luat_icmp_ctx_t* ctx = ctxs[adapter_id];
    if (ctx == NULL || ctx->send_time == 0) {
        return 0; // 并没有待接收的ICMP数据
    }

    LWIP_UNUSED_ARG(pcb);

    if (IP_IS_V4(addr)) {
        if (p->tot_len >= (sizeof(struct icmp_echo_hdr) + sizeof(struct ip_hdr)) && p->len >= sizeof(struct ip_hdr)) {
            struct ip_hdr *iphdr = (struct ip_hdr *)p->payload;
            u16_t ip_header_len = (u16_t)(IPH_HL(iphdr) * 4);
            if (p->tot_len >= ip_header_len + sizeof(struct icmp_echo_hdr) && p->len >= ip_header_len + sizeof(struct icmp_echo_hdr)) {
                const struct icmp_echo_hdr *iecho = (const struct icmp_echo_hdr *)((uint8_t *)p->payload + ip_header_len);
                if (g_icmp_debug) {
                    LLOGD("ICMPv4 recv type=%d id=%d seq=%d", iecho->type, htons(iecho->id), htons(iecho->seqno));
                }
                if (iecho->type == ICMP_ER && htons(iecho->id) == ctx->id && htons(iecho->seqno) == ctx->seqno) {
                    uint32_t elapsed = (uint32_t)(luat_mcu_tick64_ms() - ctx->send_time);
                    if (elapsed < 16 * 1000 && ctx->cb) {
                        ctx->cb(ctx, elapsed);
                    }
                    pbuf_free(p);
                    return 1;
                }
            }
        }
    }
#if LWIP_IPV6
    else if (IP_IS_V6(addr)) {
        if (p->tot_len >= (sizeof(struct icmp6_echo_hdr) + sizeof(struct ip6_hdr)) && p->len >= sizeof(struct ip6_hdr)) {
            const struct icmp6_echo_hdr *iecho6 = (const struct icmp6_echo_hdr *)((uint8_t *)p->payload + sizeof(struct ip6_hdr));
            if (g_icmp_debug) {
                LLOGD("ICMPv6 recv type=%d id=%d seq=%d", iecho6->type, htons(iecho6->id), htons(iecho6->seqno));
            }
            if (iecho6->type == ICMP6_TYPE_EREP && htons(iecho6->id) == ctx->id && htons(iecho6->seqno) == ctx->seqno) {
                uint32_t elapsed = (uint32_t)(luat_mcu_tick64_ms() - ctx->send_time);
                if (elapsed < 16 * 1000 && ctx->cb) {
                    ctx->cb(ctx, elapsed);
                }
                pbuf_free(p);
                return 1;
            }
        }
    }
#endif
    return 0;               // 继续传递数据包
}

static void ping_fill_payload(void *hdr, u16_t header_len, u16_t total_len)
{
    size_t data_len = total_len > header_len ? (size_t)(total_len - header_len) : 0;
    char *payload = (char *)hdr + header_len;
    for (size_t i = 0; i < data_len; i++) {
        payload[i] = (char)i;
    }
}

/** Prepare an IPv4 ICMP echo request */
static void ping_prepare_echo4(struct icmp_echo_hdr *iecho, u16_t len, u16_t id, u16_t seq_num)
{
    ICMPH_TYPE_SET(iecho, ICMP_ECHO);
    ICMPH_CODE_SET(iecho, 0);
    iecho->chksum = 0;
    iecho->id     = htons(id);
    iecho->seqno  = htons(seq_num);
    ping_fill_payload(iecho, sizeof(struct icmp_echo_hdr), len);
    iecho->chksum = inet_chksum(iecho, len);
}

#if LWIP_IPV6
/** Prepare an IPv6 ICMP echo request */
static void ping_prepare_echo6(struct icmp6_echo_hdr *iecho6, u16_t len, u16_t id, u16_t seq_num)
{
    iecho6->type = ICMP6_TYPE_EREQ;
    iecho6->code = 0;
    iecho6->chksum = 0;
    iecho6->id    = htons(id);
    iecho6->seqno = htons(seq_num);
    ping_fill_payload(iecho6, sizeof(struct icmp6_echo_hdr), len);
}

static int luat_icmp_select_ipv6_src(luat_icmp_ctx_t *ctx, ip_addr_t *src)
{
    if (ctx == NULL || ctx->netif == NULL || src == NULL) {
        return -1;
    }
    const ip6_addr_t *candidate = NULL;
    for (int i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++) {
        if (ip6_addr_isvalid(netif_ip6_addr_state(ctx->netif, i))) {
            const ip6_addr_t *addr = netif_ip6_addr(ctx->netif, i);
            if (ip6_addr_isglobal(addr)) {
                ip_addr_copy_from_ip6(*src, *addr);
                return 0;
            }
            if (candidate == NULL) {
                candidate = addr;
            }
        }
    }
    if (candidate) {
        ip_addr_copy_from_ip6(*src, *candidate);
        return 0;
    }
    return -1;
}
#endif

luat_icmp_ctx_t* luat_icmp_get(uint8_t adapter_id) {
    luat_netdrv_t* netdrv = luat_netdrv_get(adapter_id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return NULL;
    }
    return ctxs[adapter_id];
}

luat_icmp_ctx_t* luat_icmp_init(uint8_t adapter_id) {
    luat_netdrv_t* netdrv = luat_netdrv_get(adapter_id);
    if (netdrv == NULL || netdrv->netif == NULL) {
        return NULL;
    }
    if (ctxs[adapter_id] != NULL) {
        return ctxs[adapter_id];
    }
    ctxs[adapter_id] = luat_heap_malloc(sizeof(luat_icmp_ctx_t));
    if (ctxs[adapter_id] == NULL) {
        return NULL;
    }
    luat_icmp_ctx_t* ctx = ctxs[adapter_id];
    memset(ctx, 0, sizeof(luat_icmp_ctx_t));
    ctx->netif = netdrv->netif;
    ctx->pcb_v4 = raw_new(IP_PROTO_ICMP);
    if (ctx->pcb_v4 == NULL) {
        LLOGE("分配ICMP RAW PCB失败!!");
        luat_heap_free(ctxs[adapter_id]);
        ctxs[adapter_id] = NULL;
        return NULL;
    }
#if LWIP_IPV6
    ctx->pcb_v6 = NULL;
#endif
    ctx->id = 0x02;
    ctx->seqno = 0x01;
    ctx->adapter_id = adapter_id;
    #if LWIP_VERSION_MAJOR == 2 && LWIP_VERSION_MINOR >= 1
    raw_bind_netif(ctx->pcb_v4, ctx->netif);
    #endif
    raw_bind(ctx->pcb_v4, &ctx->netif->ip_addr);
    raw_recv(ctx->pcb_v4, luat_icmp_recv, (void*)(uint32_t)adapter_id);
    return ctx;
}

void luat_icmp_ping(luat_icmp_ctx_t* ctx) {
    if (ctx == NULL || ctx->netif == NULL) {
        return;
    }
    int ret = 0;
    char src_buff[64] = {0};
    char dst_buff[64] = {0};
    memcpy(&ctx->dst, &ctx->tmpdst, sizeof(ip_addr_t));
    ctx->send_time = 0;
    ctx->recv_time = 0;
    uint16_t header_len = IP_IS_V6(&ctx->dst) ?
#if LWIP_IPV6
        sizeof(struct icmp6_echo_hdr)
#else
        sizeof(struct icmp_echo_hdr)
#endif
        : sizeof(struct icmp_echo_hdr);
    uint16_t ping_size = header_len + (uint16_t)ctx->len;
    struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, ping_size, PBUF_RAM);
    if (p == NULL) {
        return;
    }

    ctx->id ++;
    ctx->seqno ++;
    struct raw_pcb *pcb = NULL;

    if (IP_IS_V6(&ctx->dst)) {
#if LWIP_IPV6
        if (ctx->pcb_v6 == NULL) {
            ctx->pcb_v6 = raw_new_ip_type(IPADDR_TYPE_V6, IP6_NEXTH_ICMP6);
            if (ctx->pcb_v6 == NULL) {
                pbuf_free(p);
                LLOGE("ICMPv6 RAW PCB alloc failed");
                return;
            }
            ctx->pcb_v6->chksum_offset = offsetof(struct icmp6_echo_hdr, chksum);
            ctx->pcb_v6->chksum_reqd = 1;
            #if LWIP_VERSION_MAJOR == 2 && LWIP_VERSION_MINOR >= 1
            raw_bind_netif(ctx->pcb_v6, ctx->netif);
            #endif
            raw_recv(ctx->pcb_v6, luat_icmp_recv, (void*)(uint32_t)ctx->adapter_id);
        }
        ip_addr_t src = {0};
        if (luat_icmp_select_ipv6_src(ctx, &src) != 0) {
            pbuf_free(p);
            LLOGW("ICMPv6 no valid local address");
            return;
        }
        ping_prepare_echo6((struct icmp6_echo_hdr *)p->payload, ping_size, ctx->id, ctx->seqno);
        raw_bind(ctx->pcb_v6, &src);
        pcb = ctx->pcb_v6;
        ipaddr_ntoa_r(&src, src_buff, sizeof(src_buff));
#else
        pbuf_free(p);
        LLOGW("ICMPv6 unsupported in this build");
        return;
#endif
    } else {
        if (ctx->pcb_v4 == NULL) {
            pbuf_free(p);
            LLOGE("ICMPv4 PCB invalid");
            return;
        }
        ping_prepare_echo4((struct icmp_echo_hdr *)p->payload, ping_size, ctx->id, ctx->seqno);
        raw_bind(ctx->pcb_v4, &ctx->netif->ip_addr);
        pcb = ctx->pcb_v4;
        ipaddr_ntoa_r(&ctx->netif->ip_addr, src_buff, sizeof(src_buff));
    }

    ipaddr_ntoa_r(&ctx->dst, dst_buff, sizeof(dst_buff));
    ctx->send_time = luat_mcu_tick64_ms();
    ret = raw_sendto(pcb, p, &ctx->dst);
    pbuf_free(p);
    if (ret) {
        LLOGW("ICMP sendto error %d %s --> %s", ret, src_buff, dst_buff);
    } else if (g_icmp_debug) {
        LLOGD("ICMP sendto %s --> %s len=%u", src_buff, dst_buff, ping_size);
    }
}

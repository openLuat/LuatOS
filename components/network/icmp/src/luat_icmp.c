#include "luat_base.h"
#include "luat_icmp.h"
#include "luat_mem.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_mcu.h"

#include "lwip/prot/icmp.h"
#include "lwip/prot/ip.h"
#include "lwip/pbuf.h"
#include "lwip/inet_chksum.h"

#define LUAT_LOG_TAG "icmp"
#include "luat_log.h"

static luat_icmp_ctx_t* ctxs[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];

uint8_t g_icmp_debug;

static u8_t luat_icmp_recv(void *arg, struct raw_pcb *pcb, struct pbuf *p, const ip_addr_t *addr)
{
    char buff[32] = {0};
    ipaddr_ntoa_r(addr, buff, 32);
    if (g_icmp_debug) {
        LLOGD("ICMP recv %p %p %d", arg, pcb, p->tot_len);
    }
    uint32_t adapter_id = (uint32_t)arg;
    if (adapter_id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        return 0;
    }
    if (ctxs[adapter_id] == NULL) {
        return 0;
    }
    luat_icmp_ctx_t* ctx = ctxs[adapter_id];
    if (ctx->send_time == 0) {
        return 0; // 并没有待接收的ICMP数据
    }
    struct icmp_echo_hdr *iecho;
    
    LWIP_UNUSED_ARG(arg);
    LWIP_UNUSED_ARG(pcb);
    LWIP_UNUSED_ARG(addr);

    if (p->tot_len >= sizeof(struct icmp_echo_hdr) + sizeof(struct ip_hdr)) {
        iecho = (struct icmp_echo_hdr *)(p->payload + sizeof(struct ip_hdr));
        if (g_icmp_debug) {
            LLOGD("ICMP recv %d %d %d", iecho->type, htons(iecho->id), htons(iecho->seqno));
        }
        /* 验证是否为ICMP Echo回复 */
        if (iecho->type == ICMP_ER && htons(iecho->id) == ctx->id && htons(iecho->seqno) == ctx->seqno) {
            
            /* 计算往返时间（示例中需要计时器支持）*/
            uint32_t elapsed = (uint32_t)(luat_mcu_tick64_ms() - ctx->send_time);
            if (elapsed < 16 *1000 && ctx->cb) {
                ctx->cb(ctx, elapsed);
            }
            pbuf_free(p);   // 释放pbuf
            return 1;       // 已处理该包
        }
    }
    return 0;               // 继续传递数据包
}

/** Prepare a echo ICMP request */
static void ping_prepare_echo( struct icmp_echo_hdr *iecho, u16_t len, u16_t id, uint32_t seq_num)
{
    size_t i;
    size_t data_len = len - sizeof(struct icmp_echo_hdr);

    ICMPH_TYPE_SET(iecho, ICMP_ECHO);
    ICMPH_CODE_SET(iecho, 0);
    iecho->chksum = 0;
    iecho->id     = htons(id);
    iecho->seqno  = htons(seq_num);

    /* fill the additional data buffer with some data */
    for (i = 0; i < data_len; i++)
    {
        ((char*) iecho)[sizeof(struct icmp_echo_hdr) + i] = (char) i;
    }

    iecho->chksum = inet_chksum(iecho, len);
}

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
    ctx->netif = netdrv->netif;
    ctx->pcb = raw_new(IP_PROTO_ICMP);
    if (ctx->pcb == NULL) {
        LLOGE("分配ICMP RAW PCB失败!!");
        luat_heap_free(ctxs[adapter_id]);
        ctxs[adapter_id] = NULL;
        return NULL;
    }
    ctx->id = 0x02;
    ctx->seqno = 0x01;
    ctx->adapter_id = adapter_id;
    // raw_bind_netif(ctx->pcb, ctx->netif);
    raw_bind(ctx->pcb, &ctx->netif->ip_addr);
    raw_recv(ctx->pcb, luat_icmp_recv, (void*)(uint32_t)adapter_id);
    return ctx;
}

void luat_icmp_ping(luat_icmp_ctx_t* ctx) {
    int ret = 0;
    struct icmp_echo_hdr *iecho;
    memcpy(&ctx->dst, &ctx->tmpdst, sizeof(ip_addr_t));
    ctx->send_time = 0;
    ctx->recv_time = 0;
    int ping_size = sizeof(struct icmp_echo_hdr) + ctx->len;
    struct pbuf *p = pbuf_alloc(PBUF_TRANSPORT, ping_size, PBUF_RAM);
    if (p == NULL) {
        return;
    }
    raw_bind(ctx->pcb, &ctx->netif->ip_addr);
    iecho = (struct icmp_echo_hdr *)(p->payload);
    ctx->id ++;
    ctx->seqno ++;
    ping_prepare_echo(iecho, ping_size, ctx->id, ctx->seqno);

    // ret = raw_sendto_if_src(ctx->pcb, p, dst, ctx->netif, &ctx->netif->ip_addr);
    char buff[32] = {0};
    char buff2[32] = {0};
    ipaddr_ntoa_r(&ctx->netif->ip_addr, buff, 32);
    ipaddr_ntoa_r(&ctx->dst, buff2, 32);
    // LLOGD("ICMP sendto %s --> %s", buff, buff2);
    ctx->send_time = luat_mcu_tick64_ms();
    ret = raw_sendto(ctx->pcb, p, &ctx->dst);
    pbuf_free(p);
    if (ret) {
        LLOGW("ICMP sendto error %d %s --> %s", ret, buff, buff2);
    }
}

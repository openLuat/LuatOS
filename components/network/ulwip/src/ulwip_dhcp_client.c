
#include "luat_base.h"
#include "luat_ulwip.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "ulwip"
#include "luat_log.h"

#include "lwip/opt.h"
#include "lwip/udp.h"
#include "lwip/ip.h"
#include "lwip/ip_addr.h"

// -------------------------------------
//           DHCP 客户端逻辑
// -------------------------------------
static struct udp_pcb* s_ulwip_dhcp;

static void dhcp_client_timer_cb(void *arg);
static ulwip_ctx_t* s_ctxs[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];

static int ulwip_dhcp_client_run(ulwip_ctx_t* ctx, char* rxbuff, size_t len) {
    PV_Union uIP;
    // 检查dhcp的状态
    dhcp_client_info_t* dhcp = ctx->dhcp_client;
    struct netif* netif = ctx->netif;

    Buffer_Struct rx_msg_buf = {0,0,0};
    Buffer_Struct tx_msg_buf = {0,0,0};
	uint32_t remote_ip = 0;
    int result = 0;

    if (!netif_is_up(netif) || !netif_is_link_up(netif)) {
        LLOGD("网卡未就绪,不发送dhcp请求 %d", ctx->adapter_index);
        if (rxbuff) {
            luat_heap_free(rxbuff);
            rxbuff = NULL;
        }
        return 0;
    }

    if (rxbuff) {
        rx_msg_buf.Data = (uint8_t*)rxbuff;
        rx_msg_buf.Pos = len;
        rx_msg_buf.MaxLen = len;
    }

    // 看看是不是获取成功了
    if (DHCP_STATE_CHECK == dhcp->state) {
on_check:
        uIP.u32 = dhcp->ip;
		LLOGD("动态IP:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = dhcp->submask;
		LLOGD("子网掩码:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		uIP.u32 = dhcp->gateway;
		LLOGD("网关:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
		LLOGD("租约时间:%u秒", dhcp->lease_time);

        if (dhcp->dns_server[0] != 0) {
            uIP.u32 = dhcp->dns_server[0];
            LLOGD("DNS服务器1:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
        }
        if (dhcp->dns_server[1] != 0) {
            uIP.u32 = dhcp->dns_server[1];
            LLOGD("DNS服务器2:%d.%d.%d.%d", uIP.u8[0], uIP.u8[1], uIP.u8[2], uIP.u8[3]);
        }

        // 设置到netif
        ip_addr_set_ip4_u32(&netif->ip_addr, dhcp->ip);
        ip_addr_set_ip4_u32(&netif->netmask, dhcp->submask);
        ip_addr_set_ip4_u32(&netif->gw,      dhcp->gateway);
        dhcp->state = DHCP_STATE_WAIT_LEASE_P1;
        if (rxbuff) {
            luat_heap_free(rxbuff);
            rxbuff = NULL;
        }
        ulwip_netif_ip_event(ctx);
        luat_rtos_timer_stop(ctx->dhcp_timer);
        luat_rtos_timer_start(ctx->dhcp_timer, 60000, 1, dhcp_client_timer_cb, ctx);
        return 0;
    }
    result = ip4_dhcp_run(dhcp, rxbuff == NULL ? NULL : &rx_msg_buf, &tx_msg_buf, &remote_ip);
    if (rxbuff) {
        luat_heap_free(rxbuff);
        rxbuff = NULL;
    }
    if (result) {
        LLOGE("ip4_dhcp_run error %d", result);
        return 0;
    }
    if (!tx_msg_buf.Pos) {
        if (DHCP_STATE_CHECK == dhcp->state) {
            goto on_check;
        }
        return 0; // 没有数据需要发送
    }
    // 通过UDP发出来
    struct pbuf *p;
    struct pbuf *q;
    // LLOGD("待发送DHCP包长度 %d 前4个字节分别是 %02X%02X%02X%02X", tx_msg_buf.Pos, 
    //     tx_msg_buf.Data[0], tx_msg_buf.Data[1], tx_msg_buf.Data[2], tx_msg_buf.Data[3]);
    p = pbuf_alloc(PBUF_TRANSPORT, tx_msg_buf.Pos, PBUF_RAM);
    char* data = (char*)tx_msg_buf.Data;
    for (q = p; q != NULL; q = q->next) {
        memcpy(q->payload, data, q->len);
        data += q->len;
    }
    data = p->payload;
    LLOGI("dhcp payload len %d %02X%02X%02X%02X", p->tot_len, data[0], data[1], data[2], data[3]);
    result = udp_sendto_if(s_ulwip_dhcp, p, IP_ADDR_BROADCAST, 67, netif);
    if (result != ERR_OK) {
        LLOGE("dhcp udp_sendto_if error %d", result);
    }
    pbuf_free(p);
    return 0;
}

static int ulwip_dhcp_recv(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port) {
    if (addr == NULL || port != 67 || pcb == NULL) {
        return 0;
    }
    LLOGD("收到DHCP数据包(len=%d)", p->tot_len);
    u16_t total_len = p->tot_len;
    char* ptr = luat_heap_malloc(total_len);
    if (!ptr) {
        return ERR_OK;
    }
    pbuf_copy_partial(p, ptr, total_len, 0);

    // 解析DHCP数据包中的mac地址
    uint8_t received_mac[6];
    memcpy(received_mac, ptr + 28, 6);
    
    u16_t ip_header_length = IP_IS_V6(addr) ? 40 : 20;
    u16_t udp_header_length = 8;
    ulwip_ctx_t* ctx = NULL;
    u16_t max_dhcp_packet_len;

    // 收到DHCP数据包, 需要逐个ctx查一遍, 对照xid
    for (size_t i = 0; i < NW_ADAPTER_INDEX_LWIP_NETIF_QTY; i++)
    {
        ctx = s_ctxs[i];
        if (ctx == NULL || ctx->dhcp_client == NULL || ctx->netif == NULL) {
            continue;
        }

        // 获取网络接口的mac地址
        struct netif *netif = ctx->netif;
        uint8_t *local_mac = netif->hwaddr;

        // LLOGD("mac %02X:%02X:%02X:%02X:%02X:%02X", local_mac[0], local_mac[1], local_mac[2], local_mac[3], local_mac[4], local_mac[5]);
        // LLOGD("received_mac %02X:%02X:%02X:%02X:%02X:%02X", received_mac[0], received_mac[1], received_mac[2], received_mac[3], received_mac[4], received_mac[5]);
        // 比较mac地址
        if (0 == memcmp(local_mac, received_mac, 6)) {
            // 如果找到匹配的网络接口
            // 先检查数据包长度是否足够
            max_dhcp_packet_len = ctx->netif->mtu - ip_header_length - udp_header_length;
            if (total_len > max_dhcp_packet_len) {
                LLOGE("dhcp pkg too large %d mtu %d len %d", ctx->adapter_index, ctx->netif->mtu, max_dhcp_packet_len);
                break;
            }
            // 注意, ulwip_dhcp_client_run是会释放ptr的, 所以不能在这里释放
            ulwip_dhcp_client_run(ctx, ptr, total_len);
            ptr = NULL; // 防止重复释放
            break;
        }
    }
    if (ptr) {
        luat_heap_free(ptr);
        ptr = NULL;
    }
    return ERR_OK;
}

static void ulwip_dhcp_client_run_proxy(void* ctx) {
    ulwip_dhcp_client_run((ulwip_ctx_t *)ctx, NULL, 0);
}

// timer回调, 或者是直接被调用, arg是nets的索引号
static void dhcp_client_timer_cb(void *arg) {
    ulwip_ctx_t *ctx = (ulwip_ctx_t *)arg;
    // 简单防御一下
    if (ctx->dhcp_client == NULL || ctx->dhcp_enable == 0) {
        return;
    }
    #if NO_SYS
    ulwip_dhcp_client_run_proxy(ctx);
    #else
    tcpip_callback(ulwip_dhcp_client_run_proxy, ctx);
    #endif
}

static void reset_dhcp_client(ulwip_ctx_t *ctx) {
    memset(ctx->dhcp_client, 0, sizeof(dhcp_client_info_t));
    memcpy(ctx->dhcp_client->mac, ctx->netif->hwaddr, 6);
    ctx->ip_ready = 0;
    luat_crypto_trng((char*)&ctx->dhcp_client->xid, sizeof(ctx->dhcp_client->xid));
    #if LWIP_NETIF_HOSTNAME
    if (ctx->netif && ctx->netif->hostname) {
        strncpy(ctx->dhcp_client->name, ctx->netif->hostname, strlen(ctx->dhcp_client->name) + 1);
    }
    #endif
    if (ctx->dhcp_client->name[0] == 0) {
        sprintf_(ctx->dhcp_client->name, "LuatOS_%02X%02X%02X%02X%02X%02X",
                ctx->dhcp_client->mac[0],ctx->dhcp_client->mac[1], ctx->dhcp_client->mac[2],
                ctx->dhcp_client->mac[3],ctx->dhcp_client->mac[4], ctx->dhcp_client->mac[5]);
    }
}

void ulwip_dhcp_client_start(ulwip_ctx_t *ctx) {
    // LLOGD("dhcp start netif %p", ctx->netif);
    if (ctx->netif == NULL) {
        LLOGE("ctx->netif is NULL!!!!");
        return;
    }
    if (s_ulwip_dhcp == NULL) {
        s_ulwip_dhcp = udp_new();
        ip_set_option(s_ulwip_dhcp, SOF_BROADCAST);
        udp_bind(s_ulwip_dhcp, IP4_ADDR_ANY, 68);
        // #ifdef udp_bind_netif
        // udp_bind_netif(ctx->dhcp_pcb, ctx->netif);
        // #endif
        udp_connect(s_ulwip_dhcp, IP4_ADDR_ANY, 67);
        udp_recv(s_ulwip_dhcp, ulwip_dhcp_recv, ctx);
    }
    if (!ctx->dhcp_client) {
        ctx->dhcp_client = luat_heap_malloc(sizeof(dhcp_client_info_t));
        reset_dhcp_client(ctx);
        luat_rtos_timer_create(&ctx->dhcp_timer);
        s_ctxs[ctx->adapter_index] = ctx; // 保存到全局数组中
    }
    ip_addr_set_any(0, &ctx->netif->ip_addr);
    ctx->dhcp_client->state = DHCP_STATE_DISCOVER;
    ctx->dhcp_client->discover_cnt = 0;
    if (!luat_rtos_timer_is_active(ctx->dhcp_timer))
    {
        luat_rtos_timer_start(ctx->dhcp_timer, 1000, 1, dhcp_client_timer_cb, ctx);
    }
    dhcp_client_timer_cb(ctx);
}

void ulwip_dhcp_client_stop(ulwip_ctx_t *ctx) {
    // LLOGD("dhcp stop netif %p", ctx->netif);
    if (ctx->dhcp_timer != NULL && luat_rtos_timer_is_active(ctx->dhcp_timer)) {
        luat_rtos_timer_stop(ctx->dhcp_timer);
        reset_dhcp_client(ctx);
    }
}

#include "luat_base.h"
#include "luat_netdrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv_uart.h"
#include "luat_malloc.h"
#include "luat_spi.h"
#include "luat_gpio.h"
#include "net_lwip2.h"
#include "luat_ulwip.h"
#include "lwip/tcp.h"
#include "lwip/sys.h"
#include "lwip/tcpip.h"
#include "luat_ulwip.h"
#include "luat_uart.h"
#include "crc.h"

#define LUAT_LOG_TAG "netdrv.uart"
#include "luat_log.h"

#define MAX_UART_CTX_ID (2)

static luat_netdrv_uart_ctx_t* ctxs[MAX_UART_CTX_ID];

static void uart_ip_output(void* userdata, uint8_t* buff, uint16_t len) {
    luat_netdrv_uart_ctx_t* uc = (luat_netdrv_uart_ctx_t*)userdata;
    
    memcpy(uc->txbuff, "LU\x00\x00", 4);
    uc->txbuff[2] = len & 0xFF;
    uc->txbuff[3] = (len >> 8) & 0xFF;
    
    // 计算CRC32
    uint32_t crc = calcCRC32(uc->txbuff + 4, len);
    memcpy(uc->txbuff + 4 + len, &crc, 4);
    // 写到UART去
    luat_uart_write(uc->uart_id, uc->txbuff, len + 8);
}

static void uart_data_input(int uart_id, uint32_t data_len) {

}

static err_t netif_output(struct netif *netif, struct pbuf *p) {
    luat_netdrv_uart_ctx_t* uc = NULL;
    for (size_t i = 0; i < MAX_UART_CTX_ID; i++)
    {
        if (ctxs[i] == NULL || ctxs[i]->netdrv.netif != netif) {
            continue;
        }
        uc = (luat_netdrv_uart_ctx_t*)netif->state;
        break;
    }
    if (uc == NULL) {
        return 0;
    }
    pbuf_copy_partial(p, uc->txbuff + 4, p->tot_len, 0);
    uart_ip_output(uc, uc->txbuff, p->tot_len);
    return 0;
}

static err_t uart_netif_init(struct netif *netif) {
    luat_netdrv_uart_ctx_t* uc = (luat_netdrv_uart_ctx_t*)netif->state;
    netif->linkoutput = netif_output;
    netif->output     = ulwip_etharp_output;
    #if LWIP_IPV6
    netif->output_ip6 = ethip6_output;
    #endif
    netif->mtu        = 1420;
    netif->flags      = NETIF_FLAG_BROADCAST;
    // memcpy(netif->hwaddr, uc->hwaddr, ETH_HWADDR_LEN);
    // netif->hwaddr_len = ETH_HWADDR_LEN;
    net_lwip2_set_netif(uc->netdrv.id, uc->netdrv.netif);
    net_lwip2_register_adapter(uc->netdrv.id);
    netif_set_up(uc->netdrv.netif);
    return 0;
}

luat_netdrv_t* luat_netdrv_uart_setup(luat_netdrv_conf_t *conf) {
    luat_netdrv_uart_ctx_t* ctx = NULL;
    for (size_t i = 0; i < MAX_UART_CTX_ID; i++)
    {
        if (ctxs[i] == NULL) {
            ctxs[i] = luat_heap_malloc(sizeof(luat_netdrv_uart_ctx_t));
            ctx = ctxs[i];
            memset(ctx, 0, sizeof(luat_netdrv_uart_ctx_t));
            break;
        }
    }
    if (ctx == NULL) {
        return NULL;
    }
    ctx->netdrv.userdata = ctx;
    ctx->uart_id = conf->spiid;
    ctx->netdrv.netif = luat_heap_malloc(sizeof(struct netif));
    ctx->netdrv.netif->state = ctx;
    ctx->netdrv.id = conf->id;
    ctx->netdrv.dataout = uart_ip_output;
    // ctx->netdrv.dhcp = uart_dhcp;
    ctx->ulwip.adapter_index = conf->id;
    ctx->ulwip.netif = ctx->netdrv.netif;
    ctx->ulwip.mtu = 1420;

    netif_add(ctx->netdrv.netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4, ctx, uart_netif_init, netif_input);
    netif_set_up(ctx->netdrv.netif);
    netif_set_link_up(ctx->netdrv.netif);

    luat_uart_ctrl(ctx->uart_id, LUAT_UART_SET_RECV_CALLBACK, uart_data_input);

    return &ctx->netdrv;
}

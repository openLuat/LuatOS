#include "luat_netdrv.h"
#include "luat_netdrv_event.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "net_lwip2.h"
#include "lwip/netif.h"
#include "lwip/pbuf.h"
#include "lwip/tcpip.h"
#include "lwip/etharp.h"

#include "luat_common_api.h"
#include "luat_usb.h"

#define LUAT_LOG_TAG "usb_eth"
#include "luat_log.h"

#define LUAT_USB_ETH_ADAPTER_ID NW_ADAPTER_INDEX_LWIP_USB

#ifndef LUAT_USB_ETH_TX_CACHE_POWER
#define LUAT_USB_ETH_TX_CACHE_POWER 5
#endif

#ifndef LUAT_USB_ETH_RX_CACHE_POWER
#define LUAT_USB_ETH_RX_CACHE_POWER 5
#endif

#ifndef LUAT_USB_ETH_DEFAULT_FRAME_U32_SIZE
#define LUAT_USB_ETH_DEFAULT_FRAME_U32_SIZE (400)
#define LUAT_USB_ETH_DEFAULT_FRAME_SIZE (LUAT_USB_ETH_DEFAULT_FRAME_U32_SIZE << 2)
#endif

typedef struct
{
	union {
		uint32_t data_u32[LUAT_USB_ETH_DEFAULT_FRAME_U32_SIZE];
		uint8_t data_u8[LUAT_USB_ETH_DEFAULT_FRAME_SIZE];
	};
	uint32_t total_len;
}luat_usb_eth_data_cache_t;

typedef struct
{
	luat_no_data_fifo_t rx_cache_fifo;
	luat_no_data_fifo_t tx_cache_fifo;
	luat_usb_eth_data_cache_t *rx_cache;
	luat_usb_eth_data_cache_t *tx_cache;
	luat_usb_eth_data_cache_t temp_rx_cache;
	luat_netdrv_t drv;
	ulwip_ctx_t ulwip;
	struct netif netif;
	uint16_t usb_packet_max_size;
	uint8_t usb_eth_id;
	uint8_t is_tx_busy;
	uint8_t is_data_ready;
	uint8_t link_up:1;
	uint8_t is_connected:1;
}luat_usb_eth_netif_t;

static luat_usb_eth_netif_t _usb_eth_netif;


static __NETDRV_CODE_IN_RAM__ err_t _usb_eth_netif_output(struct netif *netif, struct pbuf *p)
{
	luat_usb_eth_netif_t *ctx = (luat_usb_eth_netif_t *)netif->state;
	
	int ret;

	if (!ctx) {
		return ERR_IF;
	}

	if (!p || !p->tot_len || p->tot_len > LUAT_USB_ETH_DEFAULT_FRAME_SIZE) {
		return ERR_BUF;
	}

	if (!luat_no_data_fifo_check_free_space(&ctx->tx_cache_fifo)) {
		luat_netdrv_stat_inc(&ctx->drv.statics.drop, p->tot_len);
		LLOGE("tx_cache_fifo is full, drop %d bytes", p->tot_len);
		return ERR_IF;
	}
	uint32_t tx_index = luat_no_data_fifo_next_write_index(&ctx->tx_cache_fifo);
	pbuf_copy_partial(p, ctx->tx_cache[tx_index].data_u8, p->tot_len, 0);
	ctx->tx_cache[tx_index].total_len = p->tot_len;
	luat_no_data_fifo_put(&ctx->tx_cache_fifo);
	uint32_t cr = luat_rtos_entry_critical();
	volatile uint8_t is_tx_busy = ctx->is_tx_busy;
	luat_rtos_exit_critical(cr);
	if (!is_tx_busy) {
		ctx->is_tx_busy = 1;
		ret = luat_usb_eth_start_tx(ctx->usb_eth_id, ctx->tx_cache[tx_index].data_u32, p->tot_len);
		if (ret) {
			luat_netdrv_stat_inc(&ctx->drv.statics.drop, p->tot_len);
			LLOGE("usb_eth_start_tx failed, drop%d bytes", p->tot_len);
			return ERR_IF;
		}
	}
	return ERR_OK;
}

static err_t _usb_eth_netif_init(struct netif *netif)
{
	//luat_usb_eth_netif_t *ctx = (luat_usb_eth_netif_t *)netif->state;

	netif->name[0] = 'u';
	netif->name[1] = 'e';
	netif->mtu = 1500;
	netif->flags = NETIF_FLAG_BROADCAST | NETIF_FLAG_ETHARP | NETIF_FLAG_ETHERNET;
#if LWIP_IGMP
	netif->flags |= NETIF_FLAG_IGMP;
#endif
#if LWIP_IPV6
	netif->flags |= NETIF_FLAG_MLD6;
	netif->output_ip6 = ethip6_output;
#endif
	netif->hwaddr_len = ETH_HWADDR_LEN;
	//memcpy(netif->hwaddr, ecm->mac, 6);
	netif->linkoutput = _usb_eth_netif_output;
	netif->output = etharp_output;
	return ERR_OK;
}

static void _usb_eth_netif_add(void *param)
{
	luat_usb_eth_netif_t *ctx = (luat_usb_eth_netif_t *)param;

	netif_add(&ctx->netif, IP4_ADDR_ANY4, IP4_ADDR_ANY4, IP4_ADDR_ANY4,
			  ctx, _usb_eth_netif_init, ethernet_input);
	netif_set_up(&ctx->netif);
	net_lwip2_set_netif(ctx->drv.id, &ctx->netif);
	net_lwip2_register_adapter(ctx->drv.id);
	luat_netdrv_register(ctx->drv.id, &ctx->drv);
}

static void _usb_log(void *param)
{
	LLOGE("%s", (char *)param);
}

static void _usb_eth_rx_drain_to_lwip(void *param)
{
	luat_usb_eth_netif_t *ctx = (luat_usb_eth_netif_t *)param;
	struct pbuf *p = NULL;
	err_t ret;

	LWIP_UNUSED_ARG(param);
	while (luat_no_data_fifo_check_used_space(&ctx->rx_cache_fifo)) {
		uint32_t index = luat_no_data_fifo_get(&ctx->rx_cache_fifo);
		luat_no_data_fifo_delete(&ctx->rx_cache_fifo);
		p = pbuf_alloc(PBUF_RAW, ctx->rx_cache[index].total_len, PBUF_ROM);
		if (p) {
			p->payload = ctx->rx_cache[index].data_u8;
			ret = ctx->drv.netif->input(p, ctx->drv.netif);
			if (ret) {
				pbuf_free(p);
				luat_netdrv_stat_inc(&ctx->drv.statics.drop, ctx->rx_cache[index].total_len);
			} else {
				luat_netdrv_stat_inc(&ctx->drv.statics.in, ctx->rx_cache[index].total_len);
			}	
		}
	}
}

static void _usb_eth_run_other(luat_usb_eth_netif_t *ctx, uint32_t event, void *data_or_p_param, uint32_t size_or_u32_param)
{
	switch (event)
	{
	case LUAT_USB_ETH_EVENT_LINK_STATE:
		if (ctx->link_up != size_or_u32_param)
		{
			ctx->link_up = size_or_u32_param;
			LLOGD("usb_eth: link_up %d", ctx->link_up);
			luat_netdrv_set_link_updown(&ctx->drv, ctx->link_up);
		}
		break;
	case LUAT_USB_ETH_EVENT_MSS:
		ctx->netif.mtu = size_or_u32_param - 14;
		LLOGD("usb_eth: set mtu to %d", ctx->netif.mtu);
		break;
	case LUAT_USB_ETH_EVENT_MAC:
		if (size_or_u32_param > NETIF_MAX_HWADDR_LEN) {
			size_or_u32_param = NETIF_MAX_HWADDR_LEN;
		}
		memcpy(ctx->netif.hwaddr, data_or_p_param, size_or_u32_param);
		ctx->netif.hwaddr_len = size_or_u32_param;
		break;
	case LUAT_USB_ETH_EVENT_CONNECT:
		ctx->is_connected = 1;
		ctx->usb_packet_max_size = size_or_u32_param;
		ctx->tx_cache = luat_heap_malloc(sizeof(luat_usb_eth_data_cache_t) * (1 << LUAT_USB_ETH_TX_CACHE_POWER));
		ctx->rx_cache = luat_heap_malloc(sizeof(luat_usb_eth_data_cache_t) * (1 << LUAT_USB_ETH_RX_CACHE_POWER));
		if (ctx->tx_cache && ctx->rx_cache) {
			ctx->is_data_ready = 1;
		} else {
			LLOGE("usb_eth: malloc tx_cache or rx_cache failed");
			luat_heap_free(ctx->tx_cache);
			luat_heap_free(ctx->rx_cache);
			ctx->is_data_ready = 0;
		}
		ctx->is_tx_busy = 0;
		luat_no_data_fifo_clear(&ctx->tx_cache_fifo);
		luat_no_data_fifo_clear(&ctx->rx_cache_fifo);
		ctx->temp_rx_cache.total_len = 0;
		ctx->link_up = 1;
		LLOGD("usb_eth: connect force link up");
		luat_netdrv_set_link_updown(&ctx->drv, ctx->link_up);
		break;
	case LUAT_USB_ETH_EVENT_DISCONNECT:
		ctx->is_connected = 0;
		ctx->is_data_ready = 0;
		luat_heap_free(ctx->tx_cache);
		luat_heap_free(ctx->rx_cache);
		ctx->tx_cache = NULL;
		ctx->rx_cache = NULL;
		ctx->link_up = 0;
		LLOGD("usb_eth: disconnect force link down");
		luat_netdrv_set_link_updown(&ctx->drv, ctx->link_up);
		break;
	default:
		break;
	}
}

static __NETDRV_CODE_IN_ISR__ void _usb_eth_event_callback(uint32_t event, void *data_or_p_param, uint32_t size_or_u32_param, void *user_param)
{
	luat_usb_eth_netif_t *ctx = (luat_usb_eth_netif_t *)user_param;
	int ret;
	switch (event)
	{
	case LUAT_USB_ETH_EVENT_TX_DONE:
		if (ctx->is_data_ready) {
			volatile uint32_t pos = luat_no_data_fifo_get(&ctx->tx_cache_fifo);
			if (!size_or_u32_param) {	//发送成功
				luat_netdrv_stat_inc(&ctx->drv.statics.out, ctx->tx_cache[pos].total_len);
			} else {
				luat_netdrv_stat_inc(&ctx->drv.statics.drop, ctx->tx_cache[pos].total_len);
			}
			luat_no_data_fifo_delete(&ctx->tx_cache_fifo);
			while (luat_no_data_fifo_check_used_space(&ctx->tx_cache_fifo)){
				pos = luat_no_data_fifo_get(&ctx->tx_cache_fifo);
				ret = luat_usb_eth_continue_tx(ctx->usb_eth_id, ctx->tx_cache[pos].data_u32, ctx->tx_cache[pos].total_len);
				if (ret != LUAT_ERROR_NONE) {	//新数据发送直接失败
					luat_netdrv_stat_inc(&ctx->drv.statics.drop, ctx->tx_cache[pos].total_len);
					luat_no_data_fifo_delete(&ctx->tx_cache_fifo);
				} else {	//新数据发送中
					return;
				}
			}
			ctx->is_tx_busy = 0;
			break;
		}
		break;
	case LUAT_USB_ETH_EVENT_NEW_RX:
		if (ctx->is_data_ready) {
			if ((ctx->temp_rx_cache.total_len + size_or_u32_param) <= LUAT_USB_ETH_DEFAULT_FRAME_SIZE) {	//数据长度在限制内
				memcpy(ctx->temp_rx_cache.data_u8 + ctx->temp_rx_cache.total_len, data_or_p_param, size_or_u32_param);
				ctx->temp_rx_cache.total_len += size_or_u32_param;
				if (size_or_u32_param < ctx->usb_packet_max_size) {	 //数据接收完成
					if (luat_no_data_fifo_check_free_space(&ctx->rx_cache_fifo)) {	//有空闲缓存
						uint32_t index = luat_no_data_fifo_next_write_index(&ctx->rx_cache_fifo);
						memcpy(ctx->rx_cache[index].data_u8, ctx->temp_rx_cache.data_u8, ctx->temp_rx_cache.total_len);
						ctx->rx_cache[index].total_len = ctx->temp_rx_cache.total_len;
						luat_no_data_fifo_put(&ctx->rx_cache_fifo);
						ctx->temp_rx_cache.total_len = 0;
						if (luat_no_data_fifo_check_used_space(&ctx->rx_cache_fifo) <= 3) {	//最多发3次input请求
							tcpip_callback_with_block(_usb_eth_rx_drain_to_lwip, ctx, 0);
						}
					} else { 						//没有空闲缓存，直接返回
						luat_netdrv_stat_inc(&ctx->drv.statics.drop, ctx->temp_rx_cache.total_len);
						tcpip_callback_with_block(_usb_log, "no free rx_cache", 0);
						ctx->temp_rx_cache.total_len = 0;
					}
				}
			} else {
				tcpip_callback_with_block(_usb_log, "rx data overflow", 0);
				luat_netdrv_stat_inc(&ctx->drv.statics.drop, ctx->temp_rx_cache.total_len + size_or_u32_param);
				ctx->temp_rx_cache.total_len = 0;
			}
		}
		break;
	default:
		_usb_eth_run_other(ctx, event, data_or_p_param, size_or_u32_param);
		break;
	}
}

void luat_netdrv_usb_eth_init(void)
{
	_usb_eth_netif.usb_eth_id = LUAT_USB_ETH_ID_0;
	luat_usb_bind_eth(_usb_eth_netif.usb_eth_id, _usb_eth_event_callback, &_usb_eth_netif);
	_usb_eth_netif.drv.id = LUAT_USB_ETH_ADAPTER_ID;
	_usb_eth_netif.drv.netif = &_usb_eth_netif.netif;
	_usb_eth_netif.drv.userdata = &_usb_eth_netif;
	_usb_eth_netif.drv.ulwip = &_usb_eth_netif.ulwip;
	_usb_eth_netif.drv.dhcp = luat_netdrv_dhcp_opt;
	_usb_eth_netif.ulwip.adapter_index = _usb_eth_netif.drv.id;
	_usb_eth_netif.ulwip.netif = &_usb_eth_netif.netif;
	_usb_eth_netif.ulwip.dhcp_enable = 1;
	luat_no_data_fifo_init(&_usb_eth_netif.rx_cache_fifo, LUAT_USB_ETH_RX_CACHE_POWER);
	luat_no_data_fifo_init(&_usb_eth_netif.tx_cache_fifo, LUAT_USB_ETH_TX_CACHE_POWER);
	tcpip_callback_with_block(_usb_eth_netif_add, &_usb_eth_netif, 0);
	_usb_eth_netif.link_up = 0;
}
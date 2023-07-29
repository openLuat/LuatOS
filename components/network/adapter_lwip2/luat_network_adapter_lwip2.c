#include "platform_def.h"
#include "luat_base.h"
#if defined(LUAT_USE_NETWORK) && defined(LUAT_USE_LWIP)
#include "luat_timer.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "dns_def.h"
#include "luat_network_adapter.h"
#include "lwip/tcpip.h"
#include "lwip/udp.h"
#include "lwip/sockets.h"
#include "net_lwip.h"

#include "luat_crypto.h"

#define LUAT_LOG_TAG "net"
#include "luat_log.h"

void* luat_heap_zalloc(size_t len);

#define MAX_SOCK_NUM 8
#define NET_DBG	LLOGD
#define NET_ERR LLOGE

#ifndef SOCKET_BUF_LEN
#define SOCKET_BUF_LEN	(3 * TCP_MSS)
#endif

static int network_state = 0;
static int net_lwip_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data);

enum
{
	EV_LWIP_EVENT_START = USER_EVENT_ID_START + 0x2000000,
	EV_LWIP_SOCKET_TX,
	EV_LWIP_NETIF_INPUT,
	EV_LWIP_TCP_TIMER,
	EV_LWIP_COMMON_TIMER,
	EV_LWIP_SOCKET_RX_DONE,
	EV_LWIP_SOCKET_CREATE,
	EV_LWIP_SOCKET_CONNECT,
	EV_LWIP_SOCKET_DNS,
	EV_LWIP_SOCKET_DNS_IPV6,
	EV_LWIP_SOCKET_LISTEN,
	EV_LWIP_SOCKET_ACCPET,
	EV_LWIP_SOCKET_CLOSE,
	EV_LWIP_NETIF_LINK_STATE,
	EV_LWIP_DHCP_TIMER,
	EV_LWIP_FAST_TIMER,
	EV_LWIP_NETIF_SET_IP,
	EV_LWIP_NETIF_IPV6_BY_MAC,
};

#define SOCKET_LOCK(ID)		platform_lock_mutex(prvlwip.socket[ID].mutex)
#define SOCKET_UNLOCK(ID)	platform_unlock_mutex(prvlwip.socket[ID].mutex)
#undef platform_send_event

// static net_lwip_ctrl_struct* lwip_ctrls[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
static net_lwip_ctrl_struct prvlwip;
static void net_lwip_check_network_ready(uint8_t adapter_index);
static void net_lwip_task(void *param);
static void net_lwip_create_socket_now(uint8_t adapter_index, uint8_t socket_id);
static void platform_send_event(void *p, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3);
static ip_addr_t *net_lwip_get_ip6(void);
static err_t net_lwip_dns_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port);

static uint32_t register_statue;


static LUAT_RT_RET_TYPE net_lwip_timer_cb(LUAT_RT_CB_PARAM)
{
	platform_send_event(NULL, (uint32_t)EV_LWIP_COMMON_TIMER, 0, 0, (uint32_t)param);
	return LUAT_RT_RET;
}

void net_lwip_init(uint8_t adapter_index)
{

	uint8_t i;
	for(i = 0; i < MAX_SOCK_NUM; i++)
	{
		INIT_LLIST_HEAD(&prvlwip.socket[i].wait_ack_head);
		INIT_LLIST_HEAD(&prvlwip.socket[i].tx_head);
		INIT_LLIST_HEAD(&prvlwip.socket[i].rx_head);
		prvlwip.socket[i].mutex = platform_create_mutex();
	}
	// mbedtls_debug_set_threshold(0);
	prvlwip.dns_timer = platform_create_timer(net_lwip_timer_cb, (void *)adapter_index, 0);
}

// static net_lwip_ctrl_struct* get_lwip_ctrl(uint8_t adapter_index) {
// 	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
// 		return NULL; // 超范围了
// 	}
// 	return lwip_ctrls[adapter_index];
// }

static uint8_t prvlwip_inited = 0;

void net_lwip_set_netif(struct netif * lwip_netif, uint8_t adapter_index) {
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
		return; // 超范围了
	}
	if (prvlwip_inited == 0) {
		prvlwip_inited = 1;
		net_lwip_init(adapter_index);
		
		prvlwip.dns_adapter_index = adapter_index;
		prvlwip.dns_udp = udp_new();
		prvlwip.dns_udp->recv = net_lwip_dns_recv_cb;
		prvlwip.dns_udp->recv_arg = adapter_index;
		//udp_bind(prvlwip.dns_udp, &lwip_netif->gw, 55);
		dns_init_client(&prvlwip.dns_client);
	}

	prvlwip.lwip_netif[adapter_index] = lwip_netif;
}

static int net_lwip_del_data_cache(void *p, void *u)
{
	socket_data_t *pdata = (socket_data_t *)p;
	luat_heap_free(pdata->data);
	return LIST_DEL;
}

static int net_lwip_next_data_cache(void *p, void *u)
{
	socket_ctrl_t *socket = (socket_ctrl_t *)u;
	socket_data_t *pdata = (socket_data_t *)p;
	if (socket->tag != pdata->tag)
	{
		NET_DBG("tag error");
		luat_heap_free(pdata->data);
		return LIST_DEL;
	}
	return LIST_FIND;
}


static socket_data_t * net_lwip_create_data_node(uint8_t socket_id, uint8_t *data, uint32_t len, luat_ip_addr_t *remote_ip, uint16_t remote_port)
{
	socket_data_t *p = (socket_data_t *)luat_heap_malloc(sizeof(socket_data_t));
	if (p)
	{
		memset(p, 0, sizeof(socket_data_t));
		p->len = len;
		p->port = remote_port;
		if (remote_ip)
		{
			p->ip = *remote_ip;
		}
		else
		{
			ip_addr_set_zero(&p->ip);
		}
		p->tag = prvlwip.socket[socket_id].tag;
		if (data && len)
		{
			p->data = luat_heap_malloc(len);
			if (p->data)
			{
				memcpy(p->data, data, len);
			}
			else
			{
				luat_heap_free(p);
				return NULL;
			}
		}
	}
	return p;
}

static void net_lwip_callback_to_nw_task(uint8_t adapter_index, uint32_t event_id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	luat_network_cb_param_t param = {.tag = 0, .param = prvlwip.user_data};
	OS_EVENT event = { .ID = event_id, .Param1 = param1, .Param2 = param2, .Param3 = param3};
	if ((event_id > EV_NW_DNS_RESULT))
	{
		if (event_id != EV_NW_SOCKET_CLOSE_OK)
		{
			event.Param3 = prvlwip.socket[param1].param;
			param.tag = prvlwip.socket[param1].tag;
		}
		else
		{
			event.Param3 = ((luat_network_cb_param_t *)param3)->param;
			param.tag = ((luat_network_cb_param_t *)param3)->tag;
		}
	}
	switch(event_id)
	{
	case EV_NW_SOCKET_CLOSE_OK:
	case EV_NW_SOCKET_CONNECT_OK:
	case EV_NW_SOCKET_ERROR:
		prvlwip.socket_busy &= ~(1 << param1);
		break;
	}
	prvlwip.socket_cb(&event, &param);
}

static void net_lwip_tcp_error(uint8_t adapter_index, int socket_id)
{
	prvlwip.socket[socket_id].remote_close = 1;
	net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
}

static err_t net_lwip_tcp_connected_cb(void *arg, struct tcp_pcb *tpcb, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	prvlwip.socket_connect &= ~(1 << socket_id);
	net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
	return ERR_OK;
}

static int net_lwip_rx_data(int socket_id, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
	int is_mem_err = 0;
	SOCKET_LOCK(socket_id);
	socket_data_t *data_p = net_lwip_create_data_node(socket_id, NULL, 0, addr, port);
	if (data_p)
	{
		data_p->data = luat_heap_malloc(p->tot_len);
		if (data_p->data)
		{
			data_p->len = pbuf_copy_partial(p, data_p->data, p->tot_len, 0);
//			NET_DBG("new data %ubyte", p->tot_len);
			llist_add_tail(&data_p->node, &prvlwip.socket[socket_id].rx_head);
			prvlwip.socket[socket_id].rx_wait_size += p->tot_len;
		}
		else
		{
			luat_heap_free(data_p);
			is_mem_err = 1;
		}
	}
	else
	{
		is_mem_err = 1;
	}
	SOCKET_UNLOCK(socket_id);


	return is_mem_err;
}

static void net_lwip_tcp_close_done(uint8_t adapter_index, int socket_id, uint8_t notify)
{
	luat_network_cb_param_t cb_param;
	// LLOGD("net_lwip_tcp_close_done 1");
	// OS_LOCK;
	// LLOGD("net_lwip_tcp_close_done 2");
	SOCKET_LOCK(socket_id);
	// LLOGD("net_lwip_tcp_close_done 3");
	cb_param.param = prvlwip.socket[socket_id].param;
	cb_param.tag = prvlwip.socket[socket_id].tag;
	prvlwip.socket[socket_id].pcb.ip = NULL;
	prvlwip.socket[socket_id].listen_tcp = NULL;
	prvlwip.socket[socket_id].remote_close = 0;
	prvlwip.socket[socket_id].state = 0;
	prvlwip.socket[socket_id].in_use = 0;
	prvlwip.socket[socket_id].param = NULL;
	prvlwip.socket[socket_id].rx_wait_size = 0;
	prvlwip.socket[socket_id].tx_wait_size = 0;
	llist_traversal(&prvlwip.socket[socket_id].wait_ack_head, net_lwip_del_data_cache, NULL);
	llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip_del_data_cache, NULL);
	llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip_del_data_cache, NULL);
	prvlwip.socket_busy &= ~(1 << socket_id);
	prvlwip.socket_connect &= ~(1 << socket_id);
	// OS_UNLOCK;
	SOCKET_UNLOCK(socket_id);
	if (notify)
	{
		net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CLOSE_OK, socket_id, 0, &cb_param);
	}
}

static err_t net_lwip_tcp_recv_cb(void *arg, struct tcp_pcb *tpcb,
                             struct pbuf *p, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	uint16_t len;
	if (p)
	{
//		tcp_recved(tpcb, p->tot_len);
		len = p->tot_len;
		if (net_lwip_rx_data(socket_id, p, NULL, 0))
		{
			NET_DBG("no memory!");
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
		}
		else
		{
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_RX_NEW, socket_id, len, 0);
		}
		pbuf_free(p);
	}
	else if (err == ERR_OK)
	{
		{
			prvlwip.socket[socket_id].remote_close = 1;
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_REMOTE_CLOSE, socket_id, 0, 0);
		}
	}
	else
	{
		net_lwip_tcp_error(adapter_index, socket_id);
	}
	return ERR_OK;
}

static err_t net_lwip_tcp_sent_cb(void *arg, struct tcp_pcb *tpcb,
                              u16_t len)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	volatile uint16_t check_len = 0;
	volatile uint32_t rest_len;
	socket_data_t *p;
	SOCKET_LOCK(socket_id);
	while(check_len < len)
	{
		if (llist_empty(&prvlwip.socket[socket_id].wait_ack_head))
		{
			NET_DBG("!");
			goto SOCEKT_ERROR;
		}
		p = (socket_data_t *)prvlwip.socket[socket_id].wait_ack_head.next;
		rest_len = p->len - p->read_pos;
		if ((len - check_len) >= rest_len)
		{
//			NET_DBG("adapter %d socket %d, %ubytes ack", adapter_index, socket_id, p->len);
			llist_del(&p->node);
			luat_heap_free(p->data);
			luat_heap_free(p);
			check_len += rest_len;
		}
		else
		{
			p->read_pos += (len - check_len);
			check_len = len;
//			NET_DBG("adapter %d socket %d, all %ubytes ack %ubytes ", adapter_index, socket_id, p->len, p->read_pos);
		}
	}
	while (!llist_empty(&prvlwip.socket[socket_id].tx_head))
	{
		p = llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip_next_data_cache, &prvlwip.socket[socket_id]);
		if (p)
		{
			if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, 0))
			{
				llist_del(&p->node);
				llist_add_tail(&p->node, &prvlwip.socket[socket_id].wait_ack_head);
			}
			else
			{
//				NET_DBG("tcp buf is full, wait ack and send again");
				break;
			}
		}
	}

	SOCKET_UNLOCK(socket_id);
	tcp_output(tpcb);
	net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_TX_OK, socket_id, len, 0);
	return ERR_OK;
SOCEKT_ERROR:
	SOCKET_UNLOCK(socket_id);
	net_lwip_tcp_error(adapter_index, socket_id);
	return ERR_OK;
}

static err_t net_lwip_tcp_err_cb(void *arg, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	if (prvlwip.socket[socket_id].is_tcp)
	{
		if (prvlwip.socket[socket_id].pcb.tcp)
		{
			prvlwip.socket[socket_id].pcb.tcp = NULL;
		}
	}
	if (!prvlwip.socket[socket_id].state && !prvlwip.socket[socket_id].remote_close)
	{
		NET_DBG("adapter %d socket %d not closing, but error %d", adapter_index, socket_id, err);
		net_lwip_tcp_error(adapter_index, socket_id);
	}
	return 0;
}

static err_t net_lwip_tcp_fast_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	if (err || !newpcb)
	{
		net_lwip_tcp_error(adapter_index, socket_id);
		return 0;
	}
	prvlwip.socket[socket_id].pcb.tcp = newpcb;
	// prvlwip.socket[socket_id].pcb.tcp->sockid = socket_id;
	prvlwip.socket[socket_id].rx_wait_size = 0;
	prvlwip.socket[socket_id].tx_wait_size = 0;
	prvlwip.socket[socket_id].pcb.tcp->callback_arg = arg;
	prvlwip.socket[socket_id].pcb.tcp->recv = net_lwip_tcp_recv_cb;
	prvlwip.socket[socket_id].pcb.tcp->sent = net_lwip_tcp_sent_cb;
	prvlwip.socket[socket_id].pcb.tcp->errf = net_lwip_tcp_err_cb;
	prvlwip.socket[socket_id].pcb.tcp->so_options |= SOF_KEEPALIVE|SOF_REUSEADDR;
	net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
	return ERR_OK;
}

static err_t net_lwip_tcp_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err)
{
	// int socket_id = ((uint32_t)arg) & 0x0000ffff;
	// uint8_t adapter_index = ((uint32_t)arg) >> 16;
	return ERR_OK;
}

static err_t net_lwip_udp_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p,
    const ip_addr_t *addr, u16_t port)
{
	int socket_id = ((uint32_t)arg) & 0x0000ffff;
	uint8_t adapter_index = ((uint32_t)arg) >> 16;
	uint16_t len = 0;
	// LLOGD("net_lwip_udp_recv_cb %d %d", socket_id, adapter_index);
	if (p)
	{
		len = p->tot_len;
		if (net_lwip_rx_data(socket_id, p, addr, port))
		{
			NET_DBG("no memory!");
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
		}
		else
		{
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_RX_NEW, socket_id, len, 0);
		}
		pbuf_free(p);
	}
	return ERR_OK;
}

static int32_t net_lwip_dns_check_result(void *data, void *param)
{
	luat_dns_require_t *require = (luat_dns_require_t *)data;
	if (require->result != 0)
	{
		luat_heap_free(require->uri.Data);
		require->uri.Data = NULL;
		if (require->result > 0)
		{
			luat_dns_ip_result *ip_result = zalloc(sizeof(luat_dns_ip_result) * require->result);
			int i;
			for(i = 0; i < require->result; i++)
			{
				ip_result[i] = require->ip_result[i];
			}
			net_lwip_callback_to_nw_task(require->adapter_index, EV_NW_DNS_RESULT, require->result, ip_result, require->param);
		}
		else
		{
			net_lwip_callback_to_nw_task(require->adapter_index, EV_NW_DNS_RESULT, 0, 0, require->param);
		}

		return LIST_DEL;
	}
	else
	{
		return LIST_PASS;
	}
}

static err_t net_lwip_dns_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p, const ip_addr_t *addr, u16_t port)
{
	Buffer_Struct msg_buf;
	Buffer_Struct tx_msg_buf = {0,0,0};
	struct pbuf *out_p;
	ip_addr_t *t_ip;
	int i;
	uint8_t adapter_index = (uint32_t)arg;
	if (prvlwip.lwip_netif[prvlwip.dns_adapter_index] == NULL) {
		return ERR_OK;
	} 
	// char ip_string[64];
	//LLOGD("%s:%d", __FILE__, __LINE__);
	if (p)
	{
		OS_InitBuffer(&msg_buf, p->tot_len);
		pbuf_copy_partial(p, msg_buf.Data, p->tot_len, 0);
		pbuf_free(p);
		dns_run(&prvlwip.dns_client, &msg_buf, NULL, &i);
		OS_DeInitBuffer(&msg_buf);
		llist_traversal(&prvlwip.dns_client.require_head, net_lwip_dns_check_result, NULL);
		{
			dns_run(&prvlwip.dns_client, NULL, &tx_msg_buf, &i);
			if (tx_msg_buf.Pos)
			{
				out_p = pbuf_alloc(PBUF_RAW, tx_msg_buf.Pos, PBUF_ROM);
				if (out_p)
				{
					out_p->payload = tx_msg_buf.Data;
					// if (prvlwip.dns_client.dns_server[i].type == IPADDR_TYPE_V4)
					// {
						prvlwip.dns_udp->local_ip = prvlwip.lwip_netif[prvlwip.dns_adapter_index]->ip_addr;
						// ipaddr_ntoa_r(&prvlwip.lwip_netif->ip_addr, ip_string, 64);
						// LLOGD("net_lwip_dns_recv_cb local_ip %s", ip_string);

					// }
					// else
					// {
					// 	t_ip = net_lwip_get_ip6();
					// 	if (t_ip)
					// 	{
					// 		prvlwip.dns_udp->local_ip = *t_ip;
					// 	}
					// }
					err_t err = udp_sendto(prvlwip.dns_udp, out_p, &prvlwip.dns_client.dns_server[i], DNS_SERVER_PORT);
					pbuf_free(out_p);
				}
				OS_DeInitBuffer(&tx_msg_buf);
				llist_traversal(&prvlwip.dns_client.require_head, net_lwip_dns_check_result, NULL);
			}

		}

	}
	if (!prvlwip.dns_client.is_run)
	{
		platform_stop_timer(prvlwip.dns_timer);
	}
	return ERR_OK;
}




static void net_lwip_dns_tx_next(Buffer_Struct *tx_msg_buf)
{
	int i;
	err_t err;
	struct pbuf *p;
	// LLOGD("CALL net_lwip_dns_tx_next");
	dns_run(&prvlwip.dns_client, NULL, tx_msg_buf, &i);
	char ip_string[64];
	if (tx_msg_buf->Pos || prvlwip.dns_client.new_result)
	{
		p = pbuf_alloc(PBUF_RAW, tx_msg_buf->Pos, PBUF_ROM);
		if (p)
		{
			p->payload = tx_msg_buf->Data;
			// if (prvlwip.dns_client.dns_server[i].type == IPADDR_TYPE_V4)
			// {
				// prvlwip.dns_udp->local_ip = prvlwip.lwip_netif->ip_addr;

			// }
			// else
			// {
			// 	for (i = 0; i < LWIP_IPV6_NUM_ADDRESSES; i++)
			// 	{
			// 		if (prvlwip.lwip_netif->ip6_addr_state[i] & IP6_ADDR_VALID)
			// 		{
			// 			prvlwip.dns_udp->local_ip = prvlwip.lwip_netif->ip6_addr[i];
			// 			break;
			// 		}
			// 	}
			// }
			// prvlwip.dns_udp->local_ip = prvlwip.lwip_netif->ip_addr;
			err = udp_connect(prvlwip.dns_udp, &prvlwip.dns_client.dns_server[i], DNS_SERVER_PORT);
			if (err) {
				LLOGI("udp_connect ret %d");
			}
			else {
				err = udp_sendto(prvlwip.dns_udp, p, &prvlwip.dns_client.dns_server[i], DNS_SERVER_PORT);
				if (err) {
					LLOGI("udp_sendto ret %d");
				}
			}
			// NET_DBG("udp_connect dns_udp %d:%s",i, ipaddr_ntoa_r(&prvlwip.dns_client.dns_server[i], ip_string, sizeof(ip_string)), err);
			// LLOGD("udp_sendto dns_udp");
			// err = udp_sendto(prvlwip.dns_udp, p, &prvlwip.dns_client.dns_server[i], DNS_SERVER_PORT);
			// NET_DBG("udp_sendto dns_udp %d:%s ret %d",i, ipaddr_ntoa_r(&prvlwip.dns_client.dns_server[i], ip_string, sizeof(ip_string)), err);
			pbuf_free(p);
		}
		OS_DeInitBuffer(tx_msg_buf);
		llist_traversal(&prvlwip.dns_client.require_head, net_lwip_dns_check_result, NULL);
		prvlwip.dns_client.new_result = 0;
	}

}

// uint32_t net_lwip_rand()
// {
// 	PV_Union uPV;
// 	luat_crypto_trng(uPV.u8, 4);
// 	return uPV.u32;
// }


// void net_lwip_set_local_ip6(ip6_addr_t *ip)
// {
// 	prvlwip.ec618_ipv6.u_addr.ip6 = *ip;
// 	prvlwip.ec618_ipv6.type = IPADDR_TYPE_V6;
// }

static void net_lwip_close_tcp(int socket_id)
{
	prvlwip.socket[socket_id].pcb.tcp->sent = NULL;
	prvlwip.socket[socket_id].pcb.tcp->errf = NULL;
	prvlwip.socket[socket_id].pcb.tcp->recv = tcp_recv_null;
	prvlwip.socket[socket_id].pcb.tcp->callback_arg = 0;
	prvlwip.socket[socket_id].pcb.tcp->pollinterval = 2;
	if (tcp_close(prvlwip.socket[socket_id].pcb.tcp))
	{
		tcp_abort(prvlwip.socket[socket_id].pcb.tcp);
	}
	prvlwip.socket[socket_id].pcb.tcp = NULL;
}

static void net_lwip_task(void *param)
{
	luat_network_cb_param_t cb_param;
	OS_EVENT event = *((OS_EVENT *)param);
	luat_heap_free(param);
	Buffer_Struct tx_msg_buf = {0,0,0};
	HANDLE cur_task = luat_get_current_task();
	struct netif *netif;
	socket_data_t *p;
	ip_addr_t *p_ip, *local_ip;
	struct pbuf *out_p;
	int error, i;
	PV_Union uPV;
//	uint8_t active_flag;
	uint8_t socket_id;
	uint8_t adapter_index;
	socket_id = event.Param1;
	adapter_index = event.Param3;
	char ip_string[64] = {0};

	// LLOGD("CALL net_lwip_task event %08X adapter_index %d", event.ID, adapter_index);

	switch(event.ID)
	{
	case EV_LWIP_SOCKET_TX:

		SOCKET_LOCK(socket_id);
		if (prvlwip.socket[socket_id].in_use && prvlwip.socket[socket_id].pcb.ip)
		{
//			if (!prvlwip.socket[socket_id].pcb.tcp->unsent && !prvlwip.socket[socket_id].pcb.tcp->unacked)
//			{
//				active_flag = 0;
//			}
//			else
//			{
//				active_flag = 1;
//			}
			if (prvlwip.socket[socket_id].is_tcp)
			{
				while (!llist_empty(&prvlwip.socket[socket_id].tx_head))
				{
					p = llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip_next_data_cache, &prvlwip.socket[socket_id]);
					if (p->len <= tcp_sndbuf(prvlwip.socket[socket_id].pcb.tcp))
					{
						if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, 0))
						{
							llist_del(&p->node);
							llist_add_tail(&p->node, &prvlwip.socket[socket_id].wait_ack_head);
						}
						else
						{
							//	NET_DBG("tcp buf is full, wait ack and send again");
							break;
						}
					}
					else
					{
						//	NET_DBG("tcp buf is full, wait ack and send again");
						break;
					}
				}
				SOCKET_UNLOCK(socket_id);
				tcp_output(prvlwip.socket[socket_id].pcb.tcp);
				prvlwip.socket_busy |= (1 << socket_id);
			}
			else
			{
				p = llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip_next_data_cache, &prvlwip.socket[socket_id]);
				if (p)
				{
					llist_del(&p->node);
				}
				SOCKET_UNLOCK(socket_id);
				if (p)
				{
					uint32_t len = p->len;
					out_p = pbuf_alloc(PBUF_RAW, p->len, PBUF_ROM);
					if (out_p)
					{
						out_p->payload = p->data;
						error = udp_sendto(prvlwip.socket[socket_id].pcb.udp, out_p, &p->ip, p->port);
						// LLOGD("udp_sendto ret %d", error);
						pbuf_free(out_p);
					}
					else
					{
						NET_DBG("mem err send fail");
					}

					luat_heap_free(p->data);
					luat_heap_free(p);
					net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_TX_OK, socket_id, len, 0);

				}
			}
		}
		else
		{
			NET_DBG("adapter %d socket %d no in use! %x", adapter_index, socket_id, prvlwip.socket[socket_id].pcb.ip);
			SOCKET_UNLOCK(socket_id);
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
		}


		break;

	case EV_LWIP_COMMON_TIMER:
#ifdef LUAT_USE_DNS
		net_lwip_dns_tx_next(&tx_msg_buf);
#endif
		if (!prvlwip.dns_client.is_run)
		{
			platform_stop_timer(prvlwip.dns_timer);
		}
		break;
	case EV_LWIP_SOCKET_RX_DONE:
		if (!prvlwip.socket[socket_id].in_use || !prvlwip.socket[socket_id].pcb.ip || !prvlwip.socket[socket_id].is_tcp)
		{
			NET_DBG("error socket %d state %d,%x,%d", socket_id, prvlwip.socket[socket_id].in_use, prvlwip.socket[socket_id].pcb.ip, prvlwip.socket[socket_id].is_tcp);
			break;
		}
//			NET_DBG("socket %d rx ack %dbytes", socket_id, event.Param2);
		tcp_recved(prvlwip.socket[socket_id].pcb.tcp, event.Param2);
		break;
	case EV_LWIP_SOCKET_CREATE:
		net_lwip_create_socket_now(adapter_index, socket_id);
		break;
	case EV_LWIP_SOCKET_CONNECT:
		if (!prvlwip.socket[socket_id].in_use || !prvlwip.socket[socket_id].pcb.ip)
		{
			NET_DBG("adapter %d socket %d cannot use! %d,%x", adapter_index, socket_id, prvlwip.socket[socket_id].in_use, prvlwip.socket[socket_id].pcb.ip);
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			break;
		}
		p_ip = (ip_addr_t *)event.Param2;
		ipaddr_ntoa_r(p_ip, ip_string, 64);
		LLOGD("connect %s:%d %s", ip_string, prvlwip.socket[socket_id].remote_port, prvlwip.socket[socket_id].is_tcp ? "TCP" : "UDP");
		local_ip = NULL;
		// if (p_ip->type == IPADDR_TYPE_V4)
		// {
			local_ip = &prvlwip.lwip_netif[adapter_index]->ip_addr;
			// char ip_string[64];
			// ipaddr_ntoa_r(&prvlwip.lwip_netif->ip_addr, ip_string, 64);
			// LLOGD("EV_LWIP_SOCKET_CONNECT local_ip %s", ip_string);
		// }
		// else
		// {
		// 	local_ip = net_lwip_get_ip6();

		// }
		if (!local_ip)
		{
			NET_DBG("netif no ip !!!!!!");
			net_lwip_tcp_error(adapter_index, socket_id);
			break;
		}
		if (prvlwip.socket[socket_id].is_tcp)
		{

			//tcp_bind(prvlwip.socket[socket_id].pcb.tcp, local_ip, prvlwip.socket[socket_id].local_port);
			error = tcp_connect(prvlwip.socket[socket_id].pcb.tcp, p_ip, prvlwip.socket[socket_id].remote_port, net_lwip_tcp_connected_cb);
			if (error)
			{
				NET_DBG("adapter %d socket %d connect error %d", adapter_index, socket_id, error);
				net_lwip_tcp_error(adapter_index, socket_id);
			}
			else
			{
				prvlwip.socket_connect |= (1 << socket_id);
			}
		}
		else
		{
			if (prvlwip.socket[socket_id].local_port) {
				error = udp_bind(prvlwip.socket[socket_id].pcb.udp, local_ip, prvlwip.socket[socket_id].local_port);
				// LLOGD("udp bind ret %d port %d", error, prvlwip.socket[socket_id].local_port);
			}
			error = udp_connect(prvlwip.socket[socket_id].pcb.udp, p_ip, prvlwip.socket[socket_id].remote_port);
			if (error)
			{
				NET_DBG("adapter %d socket %d connect error %d", adapter_index, socket_id, error);
				net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			}
			else
			{
				if (!prvlwip.socket[socket_id].remote_port)
				{
					prvlwip.socket[socket_id].pcb.udp->flags &= ~UDP_FLAGS_CONNECTED;
				}
				net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
			}

		}
		break;
	case EV_LWIP_SOCKET_DNS:
	case EV_LWIP_SOCKET_DNS_IPV6:
		// LLOGD("event dns query");
		if (!prvlwip.dns_client.is_run)
		{
			platform_start_timer(prvlwip.dns_timer, 1000, 1);
		}
		dns_require_ipv6(&prvlwip.dns_client, event.Param1, event.Param2, event.Param3, (event.ID - EV_LWIP_SOCKET_DNS));
		// LLOGD("event dns query 2");
		net_lwip_dns_tx_next(&tx_msg_buf);
		// LLOGD("event dns query 3");
		break;
	case EV_LWIP_SOCKET_LISTEN:
		if (!prvlwip.socket[socket_id].in_use || !prvlwip.socket[socket_id].pcb.ip)
		{
			NET_DBG("adapter %d socket %d cannot use! %d,%x", adapter_index, socket_id, prvlwip.socket[socket_id].in_use, prvlwip.socket[socket_id].pcb.ip);
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			break;
		}
		//tcp_bind(prvlwip.socket[socket_id].pcb.tcp, NULL, prvlwip.socket[socket_id].local_port);
        IP_SET_TYPE_VAL(prvlwip.socket[socket_id].pcb.tcp->local_ip,  IPADDR_TYPE_ANY);
        IP_SET_TYPE_VAL(prvlwip.socket[socket_id].pcb.tcp->remote_ip, IPADDR_TYPE_ANY);
        // prvlwip.socket[socket_id].pcb.tcp->sockid = -1;
        prvlwip.socket[socket_id].listen_tcp = tcp_listen_with_backlog(prvlwip.socket[socket_id].pcb.tcp, 1);
        if (!prvlwip.socket[socket_id].listen_tcp) {
        	NET_DBG("socket %d listen failed");
        	net_lwip_tcp_error(adapter_index, socket_id);
        } else {
        	PV_Union uPV;
        	uPV.u16[0] = socket_id;
        	uPV.u16[1] = adapter_index;
        	prvlwip.socket[socket_id].listen_tcp->callback_arg = uPV.u32;
        	prvlwip.socket[socket_id].listen_tcp->accept = net_lwip_tcp_fast_accept_cb;
        	prvlwip.socket[socket_id].pcb.tcp = NULL;
        	net_lwip_callback_to_nw_task(adapter_index, EV_NW_SOCKET_LISTEN, socket_id, 0, 0);
        }
		break;
//	case EV_LWIP_SOCKET_ACCPET:
//
//		break;
	case EV_LWIP_SOCKET_CLOSE:
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 1");
		if (!prvlwip.socket[socket_id].in_use)
		{
			NET_DBG("socket %d no in use!,%x", socket_id);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 2");
		if (prvlwip.socket[socket_id].listen_tcp)
		{
			tcp_close(prvlwip.socket[socket_id].listen_tcp);
			prvlwip.socket[socket_id].listen_tcp = NULL;
			if (prvlwip.socket[socket_id].pcb.tcp)
			{
				net_lwip_close_tcp(socket_id);
			}
			net_lwip_tcp_close_done(adapter_index, socket_id, event.Param2);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 3");
		if (prvlwip.socket[socket_id].pcb.ip)
		{
			if (prvlwip.socket[socket_id].is_tcp)
			{
				net_lwip_close_tcp(socket_id);
			}
			else
			{
				// LLOGD("event EV_LWIP_SOCKET_CLOSE 31");
				udp_remove(prvlwip.socket[socket_id].pcb.udp);
				// LLOGD("event EV_LWIP_SOCKET_CLOSE 32");
			}
			net_lwip_tcp_close_done(adapter_index, socket_id, event.Param2);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE 4");
		if (prvlwip.socket[socket_id].remote_close)
		{
			net_lwip_tcp_close_done(adapter_index, socket_id, event.Param2);
			break;
		}
		// LLOGD("event EV_LWIP_SOCKET_CLOSE DONE");
		break;
	case EV_LWIP_NETIF_LINK_STATE:
		net_lwip_check_network_ready(event.Param3);
		break;
	default:
		NET_DBG("unknow event %x,%x", event.ID, event.Param1);
		break;
	}
	// LLOGD("End of lwip task");
}


static void platform_send_event(void *p, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	OS_EVENT *event = luat_heap_malloc(sizeof(OS_EVENT));
	event->ID = id;
	event->Param1 = param1;
	event->Param2 = param2;
	event->Param3 = param3;
	tcpip_callback_with_block(net_lwip_task, event, 1);
}


static void net_lwip_check_network_ready(uint8_t adapter_index)
{
	int i;
	char ip_string[64];
	uint8_t active_flag = network_state;
	
	// LLOGD("CALL net_lwip_check_network_ready %d", adapter_index);

	if (prvlwip.netif_network_ready[adapter_index] != active_flag)
	{
		prvlwip.netif_network_ready[adapter_index] = active_flag;
		if (!active_flag)
		{
			if (prvlwip.dns_adapter_index == adapter_index) {
				dns_clear(&prvlwip.dns_client);
				prvlwip.dns_client.is_run = 0;
			}
//			NET_DBG("network not ready");
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_STATE, 0, 0, adapter_index);
		}
		else
		{
			NET_DBG("network ready");
			if (prvlwip.dns_adapter_index == adapter_index) {
				luat_ip_addr_t addr = {
					.addr = 0
				};
				if (prvlwip.lwip_netif[adapter_index] != 0) {
					net_lwip_set_dns_server(0, &prvlwip.lwip_netif[adapter_index]->gw, (void*)adapter_index);
				}
				ip4addr_aton("114.114.114.114", &addr);
				net_lwip_set_dns_server(2, &addr, (void*)adapter_index);
				ip4addr_aton("223.5.5.5", &addr);
				net_lwip_set_dns_server(3, &addr, (void*)adapter_index);
			}

			// for(i = 0; i < MAX_DNS_SERVER; i++)
			// {
			// 	#if LWIP_IPV6
			// 	if (prvlwip.dns_client.dns_server[i].type != 0xff)
			// 	#else
			// 	if (prvlwip.dns_client.dns_server[i].addr != 0)
			// 	#endif
			// 	{
			// 		NET_DBG("DNS%d:%s",i, ipaddr_ntoa_r(&prvlwip.dns_client.dns_server[i], ip_string, sizeof(ip_string)));
			// 	}
			// }
			net_lwip_callback_to_nw_task(adapter_index, EV_NW_STATE, 0, 1, adapter_index);
		}

	}
	// LLOGD("done net_lwip_check_network_ready");
}

static int net_lwip_check_socket(void *user_data, int socket_id, uint64_t tag)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (socket_id >= MAX_SOCK_NUM) return -1;
	if (prvlwip.socket[socket_id].tag != tag) return -1;
	if (!prvlwip.socket[socket_id].in_use || prvlwip.socket[socket_id].state) return -1;
	return 0;
}

static int net_lwip_socket_check(int socket_id, uint64_t tag, void *user_data)
{
	return net_lwip_check_socket(user_data, socket_id, tag);
}


static uint8_t net_lwip_check_ready(void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	return (prvlwip.netif_network_ready[adapter_index]);
}

static void net_lwip_create_socket_now(uint8_t adapter_index, uint8_t socket_id)
{
	PV_Union uPV;
	uPV.u16[0] = socket_id;
	uPV.u16[1] = adapter_index;
	if (socket_id >= MAX_SOCK_NUM)
		return;
	if (prvlwip.socket[socket_id].is_tcp)
	{
		prvlwip.socket[socket_id].pcb.tcp = tcp_new();
		if (!prvlwip.socket[socket_id].pcb.tcp)
		{
			NET_DBG("try to abort fin wait 1 tcp");
			struct tcp_pcb *pcb, *dpcb;
			uint32_t low_time = (uint32_t)(luat_mcu_tick64_ms() / 1000);
			dpcb = NULL;
			for (pcb = tcp_active_pcbs; pcb != NULL; pcb = pcb->next)
			{
				if (FIN_WAIT_1 == pcb->state)
				{
					if (((uint32_t)pcb->callback_arg) < low_time)
					{
						dpcb = pcb;
						low_time = (uint32_t)pcb->callback_arg;
					}
				}
			}
			if (dpcb)
			{
				tcp_abort(dpcb);
			}
			prvlwip.socket[socket_id].pcb.tcp = tcp_new();
		}
		if (prvlwip.socket[socket_id].pcb.tcp)
		{
			// prvlwip.socket[socket_id].pcb.tcp->sockid = socket_id;
			// prvlwip.socket[socket_id].pcb.tcp->local_ip = prvlwip.lwip_netif->ip_addr;
			prvlwip.socket[socket_id].rx_wait_size = 0;
			prvlwip.socket[socket_id].tx_wait_size = 0;
			prvlwip.socket[socket_id].pcb.tcp->callback_arg = uPV.p;
			prvlwip.socket[socket_id].pcb.tcp->recv = net_lwip_tcp_recv_cb;
			prvlwip.socket[socket_id].pcb.tcp->sent = net_lwip_tcp_sent_cb;
			prvlwip.socket[socket_id].pcb.tcp->errf = net_lwip_tcp_err_cb;
			prvlwip.socket[socket_id].pcb.tcp->so_options |= SOF_KEEPALIVE|SOF_REUSEADDR;
//					tcp_set_flags(prvlwip.socket[socket_id].pcb.tcp, TCP_NODELAY);

		}
		else
		{
			NET_DBG("tcp pcb full!");
			net_lwip_tcp_error(adapter_index, socket_id);
		}
	}
	else
	{
		prvlwip.socket[socket_id].pcb.udp = udp_new();
		if (prvlwip.socket[socket_id].pcb.udp)
		{
			prvlwip.socket[socket_id].pcb.udp->recv_arg = uPV.p;
			prvlwip.socket[socket_id].pcb.udp->recv = net_lwip_udp_recv_cb;
			prvlwip.socket[socket_id].pcb.udp->so_options |= SOF_BROADCAST|SOF_REUSEADDR;
		}
		else
		{
			NET_DBG("udp pcb full!");
			net_lwip_tcp_error(adapter_index, socket_id);
		}
	}
}

static int net_lwip_create_socket(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data)
{
	uint8_t index = (uint32_t)user_data;
	uint8_t adapter_index = (uint32_t)user_data;
	if ((uint32_t)adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	int i, socket_id;
	socket_id = -1;
	// OS_LOCK;
	if (!prvlwip.socket[prvlwip.next_socket_index].in_use)
	{
		socket_id = prvlwip.next_socket_index;
		prvlwip.next_socket_index++;
	}
	else
	{
		for (i = 0; i < MAX_SOCK_NUM; i++)
		{
			if (!prvlwip.socket[i].in_use)
			{
				socket_id = i;
				prvlwip.next_socket_index = i + 1;
				break;
			}
		}
	}
	if (prvlwip.next_socket_index >= MAX_SOCK_NUM)
	{
		prvlwip.next_socket_index = 0;
	}
	if (socket_id >= 0)
	{
		LWIP_ASSERT("socket must free before create", !prvlwip.socket[socket_id].pcb.ip);
		prvlwip.socket_busy &= ~(1 << socket_id);
		prvlwip.socket_connect &= ~(1 << socket_id);
		prvlwip.socket_tag++;
		*tag = prvlwip.socket_tag;
		prvlwip.socket[socket_id].in_use = 1;
		prvlwip.socket[socket_id].tag = *tag;
		prvlwip.socket[socket_id].param = param;
		prvlwip.socket[socket_id].is_tcp = is_tcp;
		llist_traversal(&prvlwip.socket[socket_id].wait_ack_head, net_lwip_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].tx_head, net_lwip_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip_del_data_cache, NULL);
		// OS_UNLOCK;
		// if (platform_get_current_task() == prvlwip.task_handle)
		{
			net_lwip_create_socket_now(index, socket_id);
			return socket_id;
		}
		// platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_CREATE, socket_id, 0, user_data);
	}
	else
	{
		// OS_UNLOCK;
	}

	return socket_id;
}

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
static int net_lwip_socket_connect(int socket_id, uint64_t tag,  uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	prvlwip.socket[socket_id].local_port = local_port;
	prvlwip.socket[socket_id].remote_port = remote_port;
	platform_send_event(NULL, EV_LWIP_SOCKET_CONNECT, socket_id, remote_ip, user_data);
	return 0;
}
//作为server绑定一个port，开始监听
static int net_lwip_socket_listen(int socket_id, uint64_t tag,  uint16_t local_port, void *user_data)
{
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	prvlwip.socket[socket_id].local_port = local_port;
	platform_send_event(NULL, EV_LWIP_SOCKET_LISTEN, socket_id, local_port, user_data);
	return 0;
}
//作为server接受一个client
static int net_lwip_socket_accept(int socket_id, uint64_t tag,  luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	*remote_ip = prvlwip.socket[socket_id].pcb.tcp->remote_ip;
	*remote_port = prvlwip.socket[socket_id].pcb.tcp->remote_port;
	return 0;
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
static int net_lwip_socket_disconnect(int socket_id, uint64_t tag,  void *user_data)
{
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	prvlwip.socket[socket_id].state = 1;
	platform_send_event(NULL, EV_LWIP_SOCKET_CLOSE, socket_id, 1, user_data);
	return 0;
}

static int net_lwip_socket_force_close(int socket_id, void *user_data)
{
	if (socket_id >= MAX_SOCK_NUM) return -1;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (prvlwip.socket[socket_id].in_use && !prvlwip.socket[socket_id].state)
	{
		prvlwip.socket[socket_id].state = 1;
		platform_send_event(NULL, EV_LWIP_SOCKET_CLOSE, socket_id, 0, user_data);
	}
	return 0;
}

static int net_lwip_socket_close(int socket_id, uint64_t tag,  void *user_data)
{
	if (socket_id >= MAX_SOCK_NUM) return -1;
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (prvlwip.socket[socket_id].tag != tag)
	{
		NET_DBG("socket %d used by other!", socket_id);
		return -1;
	}
	if (!prvlwip.socket[socket_id].in_use) return 0;
	net_lwip_socket_force_close(socket_id, user_data);
	return 0;

}

static uint32_t net_lwip_socket_read_data(int socket_id, uint8_t *buf, uint32_t *read_len, uint32_t len, socket_data_t *p)
{
	uint32_t dummy_len;
	dummy_len = ((p->len - p->read_pos) > (len - *read_len))?(len - *read_len):(p->len - p->read_pos);
	memcpy(buf, p->data + p->read_pos, dummy_len);
	p->read_pos += dummy_len;
	if (p->read_pos >= p->len)
	{
		if (prvlwip.socket[socket_id].is_tcp)
		{
			platform_send_event(NULL, EV_LWIP_SOCKET_RX_DONE, socket_id, p->len, prvlwip.dns_adapter_index);
		}
		llist_del(&p->node);
		luat_heap_free(p->data);
		luat_heap_free(p);
	}
	*read_len += dummy_len;
	return dummy_len;
}

static int net_lwip_socket_receive(int socket_id, uint64_t tag,  uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	if (socket_id >= MAX_SOCK_NUM) return -1;
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;

	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;

	uint32_t read_len = 0;
	if (buf)
	{
		SOCKET_LOCK(socket_id);
		socket_data_t *p = (socket_data_t *)llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip_next_data_cache, &prvlwip.socket[socket_id]);

		if (prvlwip.socket[socket_id].is_tcp)
		{
			while((read_len < len) && p)
			{
				prvlwip.socket[socket_id].rx_wait_size -= net_lwip_socket_read_data(socket_id, buf + read_len, &read_len, len, p);
				p = (socket_data_t *)llist_traversal(&prvlwip.socket[socket_id].rx_head, net_lwip_next_data_cache, &prvlwip.socket[socket_id]);
			}
		}
		else
		{
			if (p)
			{
				if (remote_ip)
				{
					*remote_ip = p->ip;
				}
				if (remote_port)
				{
					*remote_port = p->port;
				}
				prvlwip.socket[socket_id].rx_wait_size -= net_lwip_socket_read_data(socket_id, buf + read_len, &read_len, len, p);
			}
		}
		if (llist_empty(&prvlwip.socket[socket_id].rx_head))
		{
			prvlwip.socket[socket_id].rx_wait_size = 0;
		}
		SOCKET_UNLOCK(socket_id);
	}
	else
	{
		read_len = prvlwip.socket[socket_id].rx_wait_size;
	}
	return read_len;
}
static int net_lwip_socket_send(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	SOCKET_LOCK(socket_id);
	uint32_t save_len = 0;
	uint32_t dummy_len = 0;
	socket_data_t *p;
	if (prvlwip.socket[socket_id].is_tcp)
	{
		while(save_len < len)
		{
			dummy_len = ((len - save_len) > SOCKET_BUF_LEN)?SOCKET_BUF_LEN:(len - save_len);


			p = net_lwip_create_data_node(socket_id, &buf[save_len], dummy_len, remote_ip, remote_port);

			if (p)
			{
				llist_add_tail(&p->node, &prvlwip.socket[socket_id].tx_head);
			}
			else
			{
				SOCKET_UNLOCK(socket_id);
				return -1;
			}
			save_len += dummy_len;
		}
	}
	else
	{
		p = net_lwip_create_data_node(socket_id, buf, len, remote_ip, remote_port);
		if (p)
		{
			llist_add_tail(&p->node, &prvlwip.socket[socket_id].tx_head);
		}
		else
		{
			SOCKET_UNLOCK(socket_id);
			return -1;
		}
	}

	SOCKET_UNLOCK(socket_id);
	platform_send_event(NULL, EV_LWIP_SOCKET_TX, socket_id, 0, user_data);
	result = len;
	return result;
}

void net_lwip_socket_clean(int *vaild_socket_list, uint32_t num, void *user_data)
{
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	int socket_list[MAX_SOCK_NUM];
	memset(socket_list, 0, sizeof(socket_list));
	uint32_t i;
	for(i = 0; i < num; i++)
	{
		if ( (vaild_socket_list[i] > 0) && (vaild_socket_list[i] < MAX_SOCK_NUM) )
		{
			socket_list[vaild_socket_list[i]] = 1;
		}
		NET_DBG("%d,%d",i,vaild_socket_list[i]);
	}
	for(i = 0; i < MAX_SOCK_NUM; i++)
	{
		NET_DBG("%d,%d",i,socket_list[i]);
		if ( !socket_list[i] )
		{
			net_lwip_socket_force_close(i, user_data);
		}
	}
}


static int net_lwip_get_local_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (!prvlwip.lwip_netif[adapter_index]) return -1;
	*ip = prvlwip.lwip_netif[adapter_index]->ip_addr;
	*submask = prvlwip.lwip_netif[adapter_index]->netmask;
	*gateway = prvlwip.lwip_netif[adapter_index]->gw;
	return 0;
}

static int net_lwip_get_full_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (!prvlwip.lwip_netif[adapter_index]) return -1;
	*ip = prvlwip.lwip_netif[adapter_index]->ip_addr;
	*submask = prvlwip.lwip_netif[adapter_index]->netmask;
	*gateway = prvlwip.lwip_netif[adapter_index]->gw;
	// luat_ip_addr_t *local_ip = net_lwip_get_ip6();
	// if (local_ip)
	// {
	// 	*ipv6 = *local_ip;
	// }
	// else
	// {
	// 	ipv6->type = 0xff;
	// }
	return 0;
}

static int net_lwip_user_cmd(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data)
{
	return 0;
}

static int net_lwip_dns(const char *domain_name, uint32_t len, void *param, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	char *prv_domain_name = (char *)zalloc(len + 1);
	memcpy(prv_domain_name, domain_name, len);
	platform_send_event(NULL, EV_LWIP_SOCKET_DNS, prv_domain_name, param, user_data);
	return 0;
}

static int net_lwip_dns_ipv6(const char *domain_name, uint32_t len, void *param, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	char *prv_domain_name = (char *)zalloc(len + 1);
	memcpy(prv_domain_name, domain_name, len);
	// platform_send_event(prvlwip.task_handle, (prvlwip.ec618_ipv6.type != IPADDR_TYPE_V6)?EV_LWIP_SOCKET_DNS:EV_LWIP_SOCKET_DNS_IPV6, prv_domain_name, param, user_data);
	platform_send_event(NULL, EV_LWIP_SOCKET_DNS, prv_domain_name, param, user_data);
	return 0;
}

static int net_lwip_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (server_index >= MAX_DNS_SERVER) return -1;
	prvlwip.dns_client.dns_server[server_index] = *ip;
	prvlwip.dns_client.is_static_dns[server_index] = 1;
	return 0;
}

static int net_lwip_set_mac(uint8_t *mac, void *user_data)
{
	// uint8_t index = (uint32_t)user_data;
	// if (index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	// if (!prvlwip.lwip_netif) return -1;
	// memcpy(prvlwip.lwip_netif->hwaddr, mac, 6);
	return -1;
}
int net_lwip_set_static_ip(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, luat_ip_addr_t *ipv6, void *user_data)
{
	// uint8_t index = (uint32_t)user_data;
	// if (index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	// if (!prvlwip.lwip_netif) return -1;
	// luat_ip_addr_t *p_ip = zalloc(sizeof(luat_ip_addr_t) * 5);
	// p_ip[0] = ip?(*ip):ip_addr_any_type;
	// p_ip[1] = submask?(*submask):ip_addr_any_type;
	// p_ip[2] = gateway?(*gateway):ip_addr_any_type;
	// p_ip[3] = ipv6?(*ipv6):ip_addr_any_type;
	// platform_send_event(prvlwip.task_handle, EV_LWIP_NETIF_SET_IP, p_ip, ipv6, user_data);
	return 0;
}

static int32_t net_lwip_dummy_callback(void *pData, void *pParam)
{
	return 0;
}

static void net_lwip_socket_set_callback(CBFuncEx_t cb_fun, void *param, void *user_data)
{
	uint8_t adapter_index = (uint32_t)user_data;
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	prvlwip.socket_cb = cb_fun?cb_fun:net_lwip_dummy_callback;
	prvlwip.user_data = param;
}

int net_lwip_getsockopt2(int socket_id, uint64_t tag,  int level, int optname, void *optval, uint32_t *optlen, void *user_data) {
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	return lwip_getsockopt(socket_id, level, optname, optval, optlen);
}

int net_lwip_setsockopt2(int socket_id, uint64_t tag,  int level, int optname, const void *optval, uint32_t optlen, void *user_data) {
	int result = net_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	return lwip_setsockopt(socket_id, level, optname, optval, optlen);
}

static const network_adapter_info prv_net_lwip_adapter =
{
		.check_ready = net_lwip_check_ready,
		.create_soceket = net_lwip_create_socket,
		.socket_connect = net_lwip_socket_connect,
		.socket_listen = net_lwip_socket_listen,
		.socket_accept = net_lwip_socket_accept,
		.socket_disconnect = net_lwip_socket_disconnect,
		.socket_close = net_lwip_socket_close,
		.socket_force_close = net_lwip_socket_force_close,
		.socket_receive = net_lwip_socket_receive,
		.socket_send = net_lwip_socket_send,
		.socket_check = net_lwip_socket_check,
		.socket_clean = net_lwip_socket_clean,
		.getsockopt = net_lwip_getsockopt2,
		.setsockopt = net_lwip_setsockopt2,
		.user_cmd = net_lwip_user_cmd,
		.dns = net_lwip_dns,
		.set_dns_server = net_lwip_set_dns_server,
		// .dns = net_lwip_dns,
		.dns_ipv6 = net_lwip_dns_ipv6,
		.set_mac = net_lwip_set_mac,
		.set_static_ip = net_lwip_set_static_ip,
		.get_local_ip_info = net_lwip_get_local_ip_info,
		.get_full_ip_info = net_lwip_get_full_ip_info,
		.socket_set_callback = net_lwip_socket_set_callback,
		.name = "lwip",
		.max_socket_num = MAX_SOCK_NUM,
		.no_accept = 1,
		.is_posix = 1,
};


void net_lwip_register_adapter(uint8_t adapter_index)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
		return; // 超范围了
	}
	if ( (1 << adapter_index) & register_statue) {
		return; // 注册过了
	}
	network_register_adapter(adapter_index, &prv_net_lwip_adapter, adapter_index);

	register_statue |= (1 << adapter_index);
}

int net_lwip_check_all_ack(int socket_id)
{

	if (!llist_empty(&prvlwip.socket[socket_id].wait_ack_head))
	{
		NET_ERR("socekt %d not all ack", socket_id);
		prvlwip.socket_busy |= (1 << socket_id);
		return -1;
	}
	if (!llist_empty(&prvlwip.socket[socket_id].tx_head))
	{
		NET_ERR("socekt %d not all send", socket_id);
		prvlwip.socket_busy |= (1 << socket_id);
		return -1;
	}
	if (prvlwip.socket[socket_id].pcb.tcp->snd_buf != TCP_SND_BUF)
	{
		NET_ERR("socket %d send buf %ubytes, need %u",socket_id, prvlwip.socket[socket_id].pcb.tcp->snd_buf, TCP_SND_BUF);
		prvlwip.socket_busy |= (1 << socket_id);
	}
	else
	{
		prvlwip.socket_busy &= ~(1 << socket_id);
	}
	return 0;
}


void net_lwip_set_link_state(uint8_t adapter_index, uint8_t updown)
{
	network_state = updown;
	// LLOGD("net_lwip_set_link_state %d %d", adapter_index, updown);
	platform_send_event(NULL, EV_LWIP_NETIF_LINK_STATE, updown, 0, adapter_index);
}

struct netif * net_lwip_get_netif(uint8_t adapter_index)
{
	if (adapter_index >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY)
		return NULL;
	return prvlwip.lwip_netif[adapter_index];
}

#endif

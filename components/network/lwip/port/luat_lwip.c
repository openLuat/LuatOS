#include "platform_def.h"
#include "luat_base.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "dns_def.h"
#include "luat_network_adapter.h"
#include "luat_lwip.h"
#define MAX_SOCK_NUM LWIP_NUM_SOCKETS
extern LUAT_WEAK void DBG_Printf(const char* format, ...);

#define NET_DBG(x,y...) DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
enum
{
	EV_LWIP_EVENT_START = USER_EVENT_ID_START + 0x2000000,
	EV_LWIP_SOCKET_TX,
	EV_LWIP_NETIF_INPUT,
	EV_LWIP_TCP_TIMER,
	EV_LWIP_COMMON_TIMER,
	EV_LWIP_SOCKET_CREATE,
	EV_LWIP_SOCKET_CONNECT,
	EV_LWIP_SOCKET_DNS,
	EV_LWIP_SOCKET_LISTEN,
	EV_LWIP_SOCKET_ACCPET,
	EV_LWIP_SOCKET_CLOSE,
	EV_LWIP_REQUIRE_DHCP,
	EV_LWIP_DHCP_TIMER,
	EV_LWIP_FAST_TIMER,
	EV_LWIP_NETIF_LINK_STATE,
	EV_LWIP_MLD6_ON_OFF,
};
extern u32_t tcp_ticks;
extern struct tcp_pcb *tcp_active_pcbs;
extern struct tcp_pcb *tcp_tw_pcbs;
#define SOCKET_LOCK(ID)		platform_lock_mutex(prvlwip.socket[ID].mutex)
#define SOCKET_UNLOCK(ID)	platform_unlock_mutex(prvlwip.socket[ID].mutex)


typedef struct
{
	llist_head node;
	uint64_t tag;	//考虑到socket复用的问题，必须有tag来做比对
	luat_ip_addr_t ip;
	uint8_t *data;
	uint32_t read_pos;
	uint32_t len;
	uint16_t port;
	uint8_t is_sending;
}socket_data_t;

typedef struct
{
	dns_client_t dns_client;
	socket_ctrl_t socket[MAX_SOCK_NUM];
	struct netif *lwip_netif[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	uint64_t last_sleep_ms;
	uint64_t socket_tag;
	CBFuncEx_t socket_cb;
	void *user_data;
	void *task_handle;
	struct udp_pcb *dns_udp;
	HANDLE socket_mutex;
	HANDLE tcp_timer;//tcp_tmr
	HANDLE common_timer;//ip_reass_tmr,etharp_tmr,dns_tmr,nd6_tmr,ip6_reass_tmr
	HANDLE fast_timer;//igmp_tmr,mld6_tmr,autoip_tmr
	HANDLE dhcp_timer;//dhcp_fine_tmr,dhcp6_tmr
	uint8_t tcpip_tcp_timer_active;
	uint8_t common_timer_active;
	uint8_t dhcp_timer_active;
	uint8_t fast_timer_active;
	uint8_t dhcp_check_cnt;
	uint8_t next_socket_index;
}luat_lwip_ctrl_struct;

static luat_lwip_ctrl_struct prvlwip;

static void luat_lwip_task(void *param);

static int luat_lwip_del_data_cache(void *p, void *u)
{
	socket_data_t *pdata = (socket_data_t *)p;
	free(pdata->data);
	return LIST_DEL;
}

static int luat_lwip_next_data_cache(void *p, void *u)
{
	socket_ctrl_t *socket = (socket_ctrl_t *)u;
	socket_data_t *pdata = (socket_data_t *)p;
	if (socket->tag != pdata->tag)
	{
		NET_DBG("tag error");
		free(pdata->data);
		return LIST_DEL;
	}
	return LIST_FIND;
}


static socket_data_t * luat_lwip_create_data_node(uint8_t socket_id, uint8_t *data, uint32_t len, luat_ip_addr_t *remote_ip, uint16_t remote_port)
{
	socket_data_t *p = (socket_data_t *)malloc(sizeof(socket_data_t));
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
			p->ip.type = 0xff;
		}
		p->tag = prvlwip.socket[socket_id].tag;
		if (data && len)
		{
			p->data = malloc(len);
			if (p->data)
			{
				memcpy(p->data, data, len);
			}
			else
			{
				free(p);
				return NULL;
			}
		}
	}
	return p;
}

static LUAT_RT_RET_TYPE luat_lwip_timer_cb(LUAT_RT_CB_PARAM)
{
	luat_send_event_to_task(prvlwip.task_handle, (uint32_t)param, 0, 0, 0);
	return LUAT_RT_RET;
}

static int luat_lwip_udp_send(struct udp_pcb *udp, const char *data, uint16_t len)
{

}

static void luat_lwip_callback_to_nw_task(uint32_t event_id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	luat_network_cb_param_t param = {.tag = 0, .param = prvlwip.user_data};
	OS_EVENT event = { .ID = event_id, .Param1 = param1, .Param2 = param2, .Param3 = param3};
	if (event_id > EV_NW_DNS_RESULT)
	{
		event.Param3 = prvlwip.socket[param1].param;
		param.tag = prvlwip.socket[param1].tag;
	}
	prvlwip.socket_cb(&event, &param);
}


static err_t luat_lwip_tcp_connected_cb(void *arg, struct tcp_pcb *tpcb, err_t err)
{
	int socket_id = (int)arg;
	luat_lwip_callback_to_nw_task(EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
	return ERR_OK;
}

static err_t luat_lwip_tcp_accept_cb(void *arg, struct tcp_pcb *newpcb, err_t err)
{
	int socket_id = (int)arg;
	return ERR_OK;
}

static err_t luat_lwip_tcp_recv_cb(void *arg, struct tcp_pcb *tpcb,
                             struct pbuf *p, err_t err)
{
	int socket_id = (int)arg;
	if (p)
	{
		tcp_recved(tpcb, p->tot_len);
		SOCKET_LOCK(socket_id);
		SOCKET_UNLOCK(socket_id);
		pbuf_free(p);
	}
	else if (err == ERR_OK)
	{

	}
	else
	{

	}
	return ERR_OK;
}

static err_t luat_lwip_tcp_sent_cb(void *arg, struct tcp_pcb *tpcb,
                              u16_t len)
{
	int socket_id = (int)arg;
	socket_data_t *p;
	SOCKET_LOCK(socket_id);

	p = llist_traversal(&prvlwip.socket[socket_id].tx_head, luat_lwip_next_data_cache, &prvlwip.socket[socket_id]);
	if (p)
	{
		if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, 0))
		{
			llist_del(&p->node);
			llist_add_tail(&p->node, &prvlwip.socket[socket_id].wait_ack_head);
		}
		else
		{
			NET_DBG("tcp buf is full, wait ack and send again");
		}
	}
	SOCKET_UNLOCK(socket_id);
	tcp_output(prvlwip.socket[socket_id].pcb.tcp);
	luat_lwip_callback_to_nw_task(EV_NW_SOCKET_TX_OK, socket_id, len, 0);
	return ERR_OK;
}

static err_t luat_lwip_tcp_err_cb(void *arg, err_t err)
{
	int socket_id = (int)arg;
	prvlwip.socket[socket_id].pcb.ip = NULL;
	luat_lwip_callback_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
}

static err_t luat_lwip_udp_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p,
    const ip_addr_t *addr, u16_t port)
{
	int socket_id = (int)arg;
	if (p)
	{
		SOCKET_LOCK(socket_id);
		SOCKET_UNLOCK(socket_id);
		pbuf_free(p);
	}
	return ERR_OK;
}

static int32_t luat_lwip_dns_check_result(void *data, void *param)
{
	luat_dns_require_t *require = (luat_dns_require_t *)data;
	if (require->result != 0)
	{
		free(require->uri.Data);
		require->uri.Data = NULL;
		if (require->result > 0)
		{
			luat_dns_ip_result *ip_result = zalloc(sizeof(luat_dns_ip_result) * require->result);
			int i;
			for(i = 0; i < require->result; i++)
			{
				ip_result[i] = require->ip_result[i];
			}
			luat_lwip_callback_to_nw_task(EV_NW_DNS_RESULT, require->result, ip_result, require->param);
		}
		else
		{
			luat_lwip_callback_to_nw_task(EV_NW_DNS_RESULT, 0, 0, require->param);
		}

		return LIST_DEL;
	}
	else
	{
		return LIST_PASS;
	}
}

static err_t luat_lwip_dns_recv_cb(void *arg, struct udp_pcb *pcb, struct pbuf *p,
    const ip_addr_t *addr, u16_t port)
{
	Buffer_Struct msg_buf;
	Buffer_Struct tx_msg_buf = {0,0,0};
	struct pbuf *out_p;
	int i;
	if (p)
	{
		msg_buf.Data = p->payload;
		msg_buf.MaxLen = p->len;
		dns_run(&prvlwip.dns_client, &msg_buf, NULL, &i);
		llist_traversal(&prvlwip.dns_client.require_head, luat_lwip_dns_check_result, NULL);
		//if (!prvlwip.socket[SYS_SOCK_ID].tx_wait_size)
		{
			dns_run(&prvlwip.dns_client, NULL, &tx_msg_buf, &i);
			if (tx_msg_buf.Pos)
			{
				out_p = pbuf_alloc(PBUF_RAW, tx_msg_buf.Pos, PBUF_ROM);
				if (out_p)
				{
					out_p->payload = tx_msg_buf.Data;
					udp_sendto(prvlwip.dns_udp, out_p, &prvlwip.dns_client.dns_server[i], DNS_SERVER_PORT);
					pbuf_free(out_p);
				}
				OS_DeInitBuffer(&tx_msg_buf);
				llist_traversal(&prvlwip.dns_client.require_head, luat_lwip_dns_check_result, NULL);
			}
		}
		pbuf_free(p);
	}
	return ERR_OK;
}




static void luat_lwip_dns_tx_next(Buffer_Struct *tx_msg_buf)
{
	int i;
	struct pbuf *p;
	dns_run(&prvlwip.dns_client, NULL, tx_msg_buf, &i);
	if (tx_msg_buf->Pos)
	{
		p = pbuf_alloc(PBUF_RAW, tx_msg_buf->Pos, PBUF_ROM);
		if (p)
		{
			p->payload = tx_msg_buf->Data;
			udp_sendto(prvlwip.dns_udp, p, &prvlwip.dns_client.dns_server[i], DNS_SERVER_PORT);
			pbuf_free(p);
		}
		OS_DeInitBuffer(tx_msg_buf);
		llist_traversal(&prvlwip.dns_client.require_head, luat_lwip_dns_check_result, NULL);
	}
}

uint32_t luat_lwip_rand()
{
	PV_Union uPV;
	luat_crypto_trng(uPV.u8, 4);
	return uPV.u32;
}

void luat_lwip_init(void)
{
	luat_thread_t thread;
	uint8_t i;
	for(i = 0; i < MAX_SOCK_NUM; i++)
	{
		INIT_LLIST_HEAD(&prvlwip.socket[i].wait_ack_head);
		INIT_LLIST_HEAD(&prvlwip.socket[i].tx_head);
		INIT_LLIST_HEAD(&prvlwip.socket[i].rx_head);
	}
	prvlwip.socket_mutex = platform_create_mutex();
	prvlwip.tcp_timer = platform_create_timer(luat_lwip_timer_cb, (void *)EV_LWIP_TCP_TIMER, 0);
	prvlwip.common_timer = platform_create_timer(luat_lwip_timer_cb, (void *)EV_LWIP_COMMON_TIMER, 0);
	prvlwip.fast_timer = platform_create_timer(luat_lwip_timer_cb, (void *)EV_LWIP_FAST_TIMER, 0);
	prvlwip.dhcp_timer = platform_create_timer(luat_lwip_timer_cb, (void *)EV_LWIP_DHCP_TIMER, 0);
	tcp_ticks = luat_mcu_tick64_ms() / TCP_SLOW_INTERVAL;
	prvlwip.last_sleep_ms = luat_mcu_tick64_ms();
	thread.task_fun = luat_lwip_task;
	thread.name = "lwip";
	thread.stack_size = 16 * 1024;
	thread.priority = 60;
	platform_create_task(&thread);
	prvlwip.task_handle = thread.handle;
	lwip_init();
	platform_start_timer(prvlwip.common_timer, 1000, 1);
	for(i = 0; i < MAX_DNS_SERVER; i++)
	{
		if (!prvlwip.dns_client.is_static_dns[i])
		{
			prvlwip.dns_client.dns_server[i].type = 0xff;
		}
	}
}



void tcp_timer_needed(void)
{
  if (!prvlwip.tcpip_tcp_timer_active && (tcp_active_pcbs || tcp_tw_pcbs)) {
	  prvlwip.tcpip_tcp_timer_active = 1;
	  platform_start_timer(prvlwip.tcp_timer, TCP_TMR_INTERVAL, 1);
  }
}


u32_t sys_now(void)
{
	return (u32_t)luat_mcu_tick64_ms();
}

static void luat_lwip_task(void *param)
{
	OS_EVENT event;
	Buffer_Struct tx_msg_buf = {0,0,0};
	HANDLE cur_task = luat_get_current_task();
	struct netif *netif;
	struct dhcp *dhcp;
	socket_data_t *p;
	struct pbuf *out_p;
	int error;
	PV_Union uPV;
	uint8_t active_flag;
	uint8_t socket_id;
	uint8_t netif_id;
	while(1)
	{

		if (luat_wait_event_from_task(cur_task, 0, &event, NULL, 0) != ERROR_NONE)
		{
			continue;
		}
		if (!prvlwip.tcpip_tcp_timer_active)
		{
			if ((luat_mcu_tick64_ms() - prvlwip.last_sleep_ms) >= TCP_SLOW_INTERVAL)
			{
				tcp_ticks += (luat_mcu_tick64_ms() - prvlwip.last_sleep_ms) / TCP_SLOW_INTERVAL;
				prvlwip.last_sleep_ms = luat_mcu_tick64_ms();
				NET_DBG("tcp ticks add to %u", tcp_ticks);
			}
		}
		else
		{
			prvlwip.last_sleep_ms = luat_mcu_tick64_ms();
		}
		netif = (struct netif *)event.Param3;
		socket_id = event.Param1;

		switch(event.ID)
		{
		case EV_LWIP_SOCKET_TX:

			SOCKET_LOCK(socket_id);
			if (prvlwip.socket[socket_id].in_use && prvlwip.socket[socket_id].pcb.ip)
			{
				if (prvlwip.socket[socket_id].is_tcp)
				{
					p = llist_traversal(&prvlwip.socket[socket_id].tx_head, luat_lwip_next_data_cache, &prvlwip.socket[socket_id]);
					if (p)
					{
						if (ERR_OK == tcp_write(prvlwip.socket[socket_id].pcb.tcp, p->data, p->len, 0))
						{
							llist_del(&p->node);
							llist_add_tail(&p->node, &prvlwip.socket[socket_id].wait_ack_head);
						}
						else
						{
							NET_DBG("tcp buf is full, wait ack and send again");
						}
					}
					SOCKET_UNLOCK(socket_id);
					tcp_output(prvlwip.socket[socket_id].pcb.tcp);
				}
				else
				{
					p = llist_traversal(&prvlwip.socket[socket_id].tx_head, luat_lwip_next_data_cache, &prvlwip.socket[socket_id]);
					if (p)
					{
						llist_del(&p->node);
					}
					SOCKET_UNLOCK(socket_id);
					if (p)
					{

						out_p = pbuf_alloc(PBUF_RAW, p->len, PBUF_ROM);
						if (out_p)
						{
							out_p->payload = p->data;
							udp_sendto(prvlwip.dns_udp, out_p, &p->ip, p->port);
							pbuf_free(out_p);
						}
						else
						{
							NET_DBG("mem err send fail");
						}
						free(p->data);
						free(p);
					}
				}
			}
			else
			{
				NET_DBG("socket %d no in use! %x", socket_id, prvlwip.socket[socket_id].pcb.ip);
				SOCKET_UNLOCK(socket_id);
				luat_lwip_callback_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
			}


			break;
		case EV_LWIP_NETIF_INPUT:
			if(netif->input((struct pbuf *)event.Param1, netif) != ERR_OK)
			{
				pbuf_free((struct pbuf *)event.Param1);
			}
			break;
		case EV_LWIP_TCP_TIMER:
			tcp_tmr();
			if (tcp_active_pcbs || tcp_tw_pcbs)
			{

			}
			else
			{
				prvlwip.tcpip_tcp_timer_active = 0;
				platform_stop_timer(prvlwip.tcp_timer);
			}
			break;
		case EV_LWIP_COMMON_TIMER:
#ifdef LUAT_USE_DNS
			luat_lwip_dns_tx_next(&tx_msg_buf);
#endif
#if IP_REASSEMBLY
			ip_reass_tmr();
#endif
#if LWIP_ARP
			etharp_tmr();
#endif
#if LWIP_DNS
			dns_tmr();
#endif
#if LWIP_IPV6
			nd6_tmr();
#endif
#if LWIP_IPV6_REASS
			ip6_reass_tmr();
#endif
#if LWIP_DHCP
			prvlwip.dhcp_check_cnt++;
			if (prvlwip.dhcp_check_cnt >= DHCP_COARSE_TIMER_SECS)
			{
				prvlwip.dhcp_check_cnt = 0;
				dhcp_coarse_tmr();
				if (!prvlwip.dhcp_timer_active)
				{
					prvlwip.dhcp_timer_active = 1;
					platform_start_timer(prvlwip.dhcp_timer, DHCP_FINE_TIMER_MSECS, 1);
				}
			}
#endif
			break;
		case EV_LWIP_SOCKET_CREATE:
			netif_id = event.Param3;
			if (prvlwip.socket[socket_id].is_tcp)
			{
				prvlwip.socket[socket_id].pcb.tcp = tcp_new();
				prvlwip.socket[socket_id].pcb.tcp->netif_idx = netif_get_index(prvlwip.lwip_netif[netif_id]);
				prvlwip.socket[socket_id].pcb.tcp->callback_arg = (void *)socket_id;
				prvlwip.socket[socket_id].pcb.tcp->recv = luat_lwip_tcp_recv_cb;
				prvlwip.socket[socket_id].pcb.tcp->sent = luat_lwip_tcp_sent_cb;
				prvlwip.socket[socket_id].pcb.tcp->errf = luat_lwip_tcp_err_cb;
			}
			else
			{
				prvlwip.socket[socket_id].pcb.udp = udp_new();
				prvlwip.socket[socket_id].pcb.udp->netif_idx = netif_get_index(prvlwip.lwip_netif[netif_id]);
				prvlwip.socket[socket_id].pcb.udp->recv_arg = (void *)socket_id;
				prvlwip.socket[socket_id].pcb.udp->recv = luat_lwip_udp_recv_cb;
			}

			break;
		case EV_LWIP_SOCKET_CONNECT:
			if (!prvlwip.socket[socket_id].in_use || !prvlwip.socket[socket_id].pcb.ip)
			{
				NET_DBG("socket %d no in use! %x", socket_id, prvlwip.socket[socket_id].pcb.ip);
				luat_lwip_callback_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
				break;
			}
			uPV.u32 = event.Param3;
			if (prvlwip.socket[socket_id].is_tcp)
			{

				tcp_bind(prvlwip.socket[socket_id].pcb.tcp, NULL, uPV.u16[0]);
				error = tcp_connect(prvlwip.socket[socket_id].pcb.tcp, (luat_ip_addr_t *)event.Param2, uPV.u16[1], luat_lwip_tcp_connected_cb);
				if (error)
				{
					luat_lwip_callback_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
				}
			}
			else
			{
				udp_bind(prvlwip.socket[socket_id].pcb.udp, NULL, uPV.u16[0]);
				error = udp_connect(prvlwip.socket[socket_id].pcb.udp, (luat_ip_addr_t *)event.Param2, uPV.u16[1]);
				if (error)
				{
					luat_lwip_callback_to_nw_task(EV_NW_SOCKET_ERROR, socket_id, 0, 0);
				}
				else
				{
					luat_lwip_callback_to_nw_task(EV_NW_SOCKET_CONNECT_OK, socket_id, 0, 0);
				}

			}
			break;
		case EV_LWIP_SOCKET_DNS:
			break;
		case EV_LWIP_SOCKET_LISTEN:

			break;
		case EV_LWIP_SOCKET_ACCPET:

			break;
		case EV_LWIP_SOCKET_CLOSE:
			if (!prvlwip.socket[socket_id].in_use)
			{
				NET_DBG("socket %d no in use!,%x", socket_id);
				break;
			}
			if (prvlwip.socket[socket_id].pcb.ip)
			{
				if (prvlwip.socket[socket_id].is_tcp)
				{
					error = tcp_close(prvlwip.socket[socket_id].pcb.tcp);
					if (error)
					{
						NET_DBG("tcp close error %d", error);
					}
				}
				else
				{
					udp_remove(prvlwip.socket[socket_id].pcb.udp);
				}
			}
			SOCKET_LOCK(socket_id);
			OS_LOCK;
			prvlwip.socket[socket_id].state = 0;
			prvlwip.socket[socket_id].in_use = 0;
			prvlwip.socket[socket_id].tag = 0;
			prvlwip.socket[socket_id].param = NULL;
			prvlwip.socket[socket_id].rx_wait_size = 0;
			prvlwip.socket[socket_id].tx_wait_size = 0;
			llist_traversal(&prvlwip.socket[socket_id].wait_ack_head, luat_lwip_del_data_cache, NULL);
			llist_traversal(&prvlwip.socket[socket_id].tx_head, luat_lwip_del_data_cache, NULL);
			llist_traversal(&prvlwip.socket[socket_id].rx_head, luat_lwip_del_data_cache, NULL);
			OS_UNLOCK;
			SOCKET_UNLOCK(socket_id);

			if (event.Param2)
			{
				luat_lwip_callback_to_nw_task(EV_NW_SOCKET_CLOSE_OK, socket_id, 0, 0);
			}

			break;
		case EV_LWIP_DHCP_TIMER:
#if LWIP_DHCP
			dhcp_fine_tmr();
			active_flag = 0;
			NETIF_FOREACH(netif)
			{
				dhcp = netif_dhcp_data(netif);
				/* only act on DHCP configured interfaces */
				if (dhcp && dhcp->request_timeout && (dhcp->state != DHCP_STATE_BOUND))
				{
					active_flag = 1;
					break;
				}
			}
			if (!active_flag)
			{
				NET_DBG("stop dhcp timer!");
				prvlwip.dhcp_timer_active = 0;
				platform_stop_timer(prvlwip.dhcp_timer);
			}
#endif
			break;
		case EV_LWIP_FAST_TIMER:
#if LWIP_AUTOIP
			autoip_tmr();
#endif
#if LWIP_IGMP
			igmp_tmr();
#endif
#if LWIP_IPV6_MLD
			mld6_tmr();
#endif
			active_flag = 0;
			NETIF_FOREACH(netif)
			{

				if (
#if LWIP_IPV6_MLD
						netif_mld6_data(netif)
#endif
#if LWIP_IGMP
						|| netif_igmp_data(netif)
#endif
#if LWIP_AUTOIP
						|| netif_autoip_data(netif)
#endif
					)
				{
					active_flag = 1;
					break;
				}

			}
			if (!active_flag)
			{
				NET_DBG("stop fast timer!");
				prvlwip.fast_timer_active = 0;
				platform_stop_timer(prvlwip.fast_timer);
			}

			break;

		case EV_LWIP_REQUIRE_DHCP:
#if LWIP_DHCP
			dhcp_start(netif);
			if (!prvlwip.dhcp_timer_active)
			{
				prvlwip.dhcp_timer_active = 1;
				platform_start_timer(prvlwip.dhcp_timer, DHCP_FINE_TIMER_MSECS, 1);
			}

#endif
			break;
		case EV_LWIP_NETIF_LINK_STATE:
			break;
		case EV_LWIP_MLD6_ON_OFF:
#if LWIP_IPV6_MLD
			if (event.Param1)
			{
				mld6_joingroup_netif(netif, event.Param2);
				if (!prvlwip.fast_timer_active)
				{
					prvlwip.fast_timer_active = 1;
					platform_start_timer(prvlwip.fast_timer, 100, 1);
				}
			}
			else
			{
				mld6_stop(netif);
			}
#endif
			break;
		}
	}

}



static int luat_lwip_check_socket(void *user_data, int socket_id, uint64_t tag)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (socket_id >= MAX_SOCK_NUM) return -1;
	if (prvlwip.socket[socket_id].tag != tag) return -1;
	if (!prvlwip.socket[socket_id].in_use || prvlwip.socket[socket_id].state) return -1;
	return 0;
}

static int luat_lwip_socket_check(int socket_id, uint64_t tag, void *user_data)
{
	return luat_lwip_check_socket(user_data, socket_id, tag);
}


static uint8_t luat_lwip_check_ready(void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	return (prvlwip.lwip_netif[(uint32_t)user_data]->flags & NETIF_FLAG_LINK_UP);
}

static int luat_lwip_create_soceket(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	int i, socket_id, error;
	socket_id = -1;
	OS_LOCK;
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
		prvlwip.socket_tag++;
		*tag = prvlwip.socket_tag;
		prvlwip.socket[socket_id].in_use = 1;
		prvlwip.socket[socket_id].tag = *tag;
		prvlwip.socket[socket_id].param = param;
		prvlwip.socket[socket_id].is_tcp = is_tcp;
		llist_traversal(&prvlwip.socket[socket_id].wait_ack_head, luat_lwip_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].tx_head, luat_lwip_del_data_cache, NULL);
		llist_traversal(&prvlwip.socket[socket_id].rx_head, luat_lwip_del_data_cache, NULL);
		OS_UNLOCK;
		platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_CREATE, socket_id, 0, user_data);
	}
	else
	{
		OS_UNLOCK;
	}

	return socket_id;
}

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
static int luat_lwip_socket_connect(int socket_id, uint64_t tag,  uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	PV_Union uPV;
	uPV.u16[0] = local_port;
	uPV.u16[1] = remote_port;
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_CONNECT, socket_id, remote_ip, uPV.u32);
	return 0;
}
//作为server绑定一个port，开始监听
static int luat_lwip_socket_listen(int socket_id, uint64_t tag,  uint16_t local_port, void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_LISTEN, socket_id, local_port, user_data);
	return 0;
}
//作为server接受一个client
static int luat_lwip_socket_accept(int socket_id, uint64_t tag,  luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
//	uint8_t temp[16];
//	int result = luat_lwip_check_socket(user_data, socket_id, tag);
//	if (result) return result;
//	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_ACCPET, socket_id, local_port, NULL);
//	remote_ip->is_ipv6 = 0;
//	remote_ip->ipv4 = BytesGetLe32(temp);
//	*remote_port = BytesGetBe16(temp + 4);
//	NET_DBG("client %d.%d.%d.%d, %u", temp[0], temp[1], temp[2], temp[3], *remote_port);
	return 0;
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
static int luat_lwip_socket_disconnect(int socket_id, uint64_t tag,  void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_CLOSE, socket_id, 1, user_data);
	return 0;
}

static int luat_lwip_socket_force_close(int socket_id, void *user_data)
{
	prvlwip.socket[socket_id].state = 1;
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_CLOSE, socket_id, 0, user_data);
	return 0;
}

static int luat_lwip_socket_close(int socket_id, uint64_t tag,  void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	luat_lwip_socket_force_close(socket_id, user_data);
	return 0;

}

static uint32_t luat_lwip_socket_read_data(uint8_t *buf, uint32_t *read_len, uint32_t len, socket_data_t *p)
{
	uint32_t dummy_len;
	dummy_len = ((p->len - p->read_pos) > (len - *read_len))?(len - *read_len):(p->len - p->read_pos);
	memcpy(buf, p->data + p->read_pos, dummy_len);
	p->read_pos += dummy_len;
	if (p->read_pos >= p->len)
	{
		llist_del(&p->node);
		free(p->data);
		free(p);
	}
	*read_len += dummy_len;
	return dummy_len;
}

static int luat_lwip_socket_receive(int socket_id, uint64_t tag,  uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;

	uint32_t read_len = 0;
	if (buf)
	{
		SOCKET_LOCK(socket_id);
		socket_data_t *p = (socket_data_t *)llist_traversal(&prvlwip.socket[socket_id].rx_head, luat_lwip_next_data_cache, &prvlwip.socket[socket_id]);

		if (prvlwip.socket[socket_id].is_tcp)
		{
			while((read_len < len) && p)
			{
				prvlwip.socket[socket_id].rx_wait_size -= luat_lwip_socket_read_data(buf + read_len, &read_len, len, p);
				p = (socket_data_t *)llist_traversal(&prvlwip.socket[socket_id].rx_head, luat_lwip_next_data_cache, &prvlwip.socket[socket_id]);
			}
		}
		else
		{
			prvlwip.socket[socket_id].rx_wait_size -= luat_lwip_socket_read_data(buf + read_len, &read_len, len, p);
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
static int luat_lwip_socket_send(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	SOCKET_LOCK(socket_id);
	socket_data_t *p = luat_lwip_create_data_node(socket_id, buf, len, remote_ip, remote_port);
	llist_add_tail(&p->node, &prvlwip.socket[socket_id].tx_head);
	SOCKET_UNLOCK(socket_id);
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_TX, socket_id, 0, user_data);
	result = len;
	return result;
}

void luat_lwip_socket_clean(int *vaild_socket_list, uint32_t num, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	int socket_list[MAX_SOCK_NUM];
	memset(socket_list, 0, sizeof(socket_list));
	uint32_t i;
	for(i = 0; i < num + 1; i++)
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
			luat_lwip_socket_force_close(i, user_data);
		}
	}
}

static int luat_lwip_getsockopt(int socket_id, uint64_t tag,  int level, int optname, void *optval, uint32_t *optlen, void *user_data)
{
	return -1;
}
static int luat_lwip_setsockopt(int socket_id, uint64_t tag,  int level, int optname, const void *optval, uint32_t optlen, void *user_data)
{
	return -1;
}
static int luat_lwip_get_local_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;

//	if (prvlwip.static_ip)
//	{
//		ip->ipv4 = prvlwip.static_ip;
//		ip->is_ipv6 = 0;
//		submask->ipv4 = prvlwip.static_submask;
//		submask->is_ipv6 = 0;
//		gateway->ipv4 = prvlwip.static_gateway;
//		gateway->is_ipv6 = 0;
//		return 0;
//	}
//	else
//	{
//		if (!prvlwip.ip_ready)
//		{
//			return -1;
//		}
//		ip->ipv4 = prvlwip.dhcp_client.ip;
//		ip->is_ipv6 = 0;
//		submask->ipv4 = prvlwip.dhcp_client.submask;
//		submask->is_ipv6 = 0;
//		gateway->ipv4 = prvlwip.dhcp_client.gateway;
//		gateway->is_ipv6 = 0;
//		return 0;
//	}
	return 0;
}

static int luat_lwip_user_cmd(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data)
{
	return 0;
}

static int luat_lwip_dns(const char *domain_name, uint32_t len, void *param, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	char *prv_domain_name = (char *)malloc(len);
	memcpy(prv_domain_name, domain_name, len);
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_DNS, prv_domain_name, param, user_data);
	return 0;
}

static int luat_lwip_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (server_index >= MAX_DNS_SERVER) return -1;
	prvlwip.dns_client.dns_server[server_index] = *ip;
	prvlwip.dns_client.is_static_dns[server_index] = 1;
	return 0;
}

static int luat_lwip_set_mac(uint8_t *mac, void *user_data)
{
	return -1;
}
static int luat_lwip_set_static_ip(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data)
{
	return -1;
}

static int32_t luat_lwip_dummy_callback(void *pData, void *pParam)
{
	return 0;
}

static void luat_lwip_socket_set_callback(CBFuncEx_t cb_fun, void *param, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return;
	prvlwip.socket_cb = cb_fun?cb_fun:luat_lwip_dummy_callback;
	prvlwip.user_data = param;
}

static network_adapter_info prv_luat_lwip_adapter =
{
		.check_ready = luat_lwip_check_ready,
		.create_soceket = luat_lwip_create_soceket,
		.socket_connect = luat_lwip_socket_connect,
		.socket_listen = luat_lwip_socket_listen,
		.socket_accept = luat_lwip_socket_accept,
		.socket_disconnect = luat_lwip_socket_disconnect,
		.socket_close = luat_lwip_socket_close,
		.socket_force_close = luat_lwip_socket_force_close,
		.socket_receive = luat_lwip_socket_receive,
		.socket_send = luat_lwip_socket_send,
		.socket_check = luat_lwip_socket_check,
		.socket_clean = luat_lwip_socket_clean,
		.getsockopt = luat_lwip_getsockopt,
		.setsockopt = luat_lwip_setsockopt,
		.user_cmd = luat_lwip_user_cmd,
		.dns = luat_lwip_dns,
		.set_dns_server = luat_lwip_set_dns_server,
		.set_mac = luat_lwip_set_mac,
		.set_static_ip = luat_lwip_set_static_ip,
		.get_local_ip_info = luat_lwip_get_local_ip_info,
		.socket_set_callback = luat_lwip_socket_set_callback,
		.name = "lwip",
		.max_socket_num = MAX_SOCK_NUM,
		.no_accept = 0,
		.is_posix = 1,
};


void luat_lwip_register_adapter(uint8_t adapter_index)
{
	network_register_adapter(adapter_index, &prv_luat_lwip_adapter, adapter_index);
}

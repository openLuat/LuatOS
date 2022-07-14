#include "platform_def.h"
#include "luat_base.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_network_adapter.h"
#define MAX_SOCK_NUM MEMP_NUM_TCP_PCB
extern LUAT_WEAK void DBG_Printf(const char* format, ...);

#define NET_DBG(x,y...) DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)
enum
{
	EV_LWIP_EVENT_START = USER_EVENT_ID_START + 0x2000000,
	EV_LWIP_SOCKET_TX,
	EV_LWIP_NETIF_INPUT,
	EV_LWIP_TCP_TIMER,
	EV_LWIP_COMMON_TIMER,
	EV_LWIP_DHCP_TIMER,
	EV_LWIP_FAST_TIMER,
	EV_LWIP_SOCKET_CONNECT,
	EV_LWIP_SOCKET_CLOSE,
	EV_LWIP_REQUIRE_DHCP,
	EV_LWIP_NETIF_LINK_STATE,
	EV_LWIP_MLD6_ON_OFF,
};
extern u32_t tcp_ticks;
extern struct tcp_pcb *tcp_active_pcbs;
extern struct tcp_pcb *tcp_tw_pcbs;

typedef struct
{
	uint64_t last_tx_time;
	struct netif netif;
	void *user_data;
	void *task_handle;
	void *cb_handle;
	uint8_t network_ready;
}lwip_netif_ctrl_t;

typedef struct
{
	lwip_netif_ctrl_t lwip_netif[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	uint64_t last_sleep_ms;
	void *lwip_task_handler;
	HANDLE tcp_timer;//tcp_tmr
	HANDLE common_timer;//ip_reass_tmr,etharp_tmr,dns_tmr,nd6_tmr,ip6_reass_tmr
	HANDLE fast_timer;//igmp_tmr,mld6_tmr,autoip_tmr
	HANDLE dhcp_timer;//dhcp_fine_tmr,dhcp6_tmr
	uint8_t tcpip_tcp_timer_active;
	uint8_t common_timer_active;
	uint8_t dhcp_timer_active;
	uint8_t fast_timer_active;
	uint8_t dhcp_check_cnt;
}luat_lwip_ctrl_struct;

static luat_lwip_ctrl_struct prvlwip;

static void luat_lwip_task(void *param);

static LUAT_RT_RET_TYPE luat_lwip_timer_cb(LUAT_RT_CB_PARAM)
{
	luat_send_event_to_task(prvlwip.lwip_task_handler, (uint32_t)param, 0, 0, 0);
	return LUAT_RT_RET;
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
	prvlwip.tcp_timer = luat_create_rtos_timer(luat_lwip_timer_cb, (void *)EV_LWIP_TCP_TIMER, 0);
	prvlwip.common_timer = luat_create_rtos_timer(luat_lwip_timer_cb, (void *)EV_LWIP_COMMON_TIMER, 0);
	prvlwip.fast_timer = luat_create_rtos_timer(luat_lwip_timer_cb, (void *)EV_LWIP_FAST_TIMER, 0);
	prvlwip.dhcp_timer = luat_create_rtos_timer(luat_lwip_timer_cb, (void *)EV_LWIP_DHCP_TIMER, 0);
	tcp_ticks = luat_mcu_tick64_ms() / TCP_SLOW_INTERVAL;
	prvlwip.last_sleep_ms = luat_mcu_tick64_ms();
	thread.task_fun = luat_lwip_task;
	thread.name = "lwip";
	thread.stack_size = 16 * 1024;
	thread.priority = 60;
	luat_thread_start(&thread);
	prvlwip.lwip_task_handler = thread.handle;
	lwip_init();
	luat_start_rtos_timer(prvlwip.common_timer, 1000, 1);
}

void tcp_timer_needed(void)
{
  if (!prvlwip.tcpip_tcp_timer_active && (tcp_active_pcbs || tcp_tw_pcbs)) {
	  prvlwip.tcpip_tcp_timer_active = 1;
	  luat_start_rtos_timer(prvlwip.tcp_timer, TCP_TMR_INTERVAL, 1);
  }
}


u32_t sys_now(void)
{
	return (u32_t)luat_mcu_tick64_ms();
}

static void luat_lwip_task(void *param)
{
	OS_EVENT event;
	HANDLE cur_task = luat_get_current_task();
	struct netif *netif;
	struct dhcp *dhcp;
	uint8_t active_flag;
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
		switch(event.ID)
		{
		case EV_LWIP_SOCKET_TX:
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
				;
			}
			else
			{
				prvlwip.tcpip_tcp_timer_active = 0;
				luat_stop_rtos_timer(prvlwip.tcp_timer);
			}
			break;
		case EV_LWIP_COMMON_TIMER:
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
					luat_start_rtos_timer(prvlwip.dhcp_timer, DHCP_FINE_TIMER_MSECS, 1);
				}
			}
#endif
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
				luat_stop_rtos_timer(prvlwip.dhcp_timer);
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
				luat_stop_rtos_timer(prvlwip.fast_timer);
			}

			break;
		case EV_LWIP_SOCKET_CONNECT:
			break;
		case EV_LWIP_SOCKET_CLOSE:
			break;
		case EV_LWIP_REQUIRE_DHCP:
#if LWIP_DHCP
			dhcp_start(netif);
			if (!prvlwip.dhcp_timer_active)
			{
				prvlwip.dhcp_timer_active = 1;
				luat_start_rtos_timer(prvlwip.dhcp_timer, DHCP_FINE_TIMER_MSECS, 1);
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
					luat_start_rtos_timer(prvlwip.fast_timer, 100, 1);
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

#if 0

static int lwip_check_socket(lwip_netif_ctrl_t *lwip, int socket_id, uint64_t tag)
{
	if (w5500 != prv_w5500_ctrl) return -1;
	if (socket_id < 1 || socket_id >= MAX_SOCK_NUM) return -1;
	if (w5500->socket[socket_id].tag != tag) return -1;
	if (!w5500->socket[socket_id].in_use) return -1;
	return 0;
}

static int w5500_socket_check(int socket_id, uint64_t tag, void *user_data)
{
	return w5500_check_socket(user_data, socket_id, tag);
}


static uint8_t w5500_check_ready(void *user_data)
{
	return ((lwip_netif_ctrl_t *)user_data)->network_ready;
}

static int w5500_create_soceket(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	int i, socket_id;
	socket_id = -1;
	W5500_LOCK;
	if (!prv_w5500_ctrl->socket[prv_w5500_ctrl->next_socket_index].in_use)
	{
		socket_id = prv_w5500_ctrl->next_socket_index;
		prv_w5500_ctrl->next_socket_index++;
	}
	else
	{
		for (i = 1; i < MAX_SOCK_NUM; i++)
		{
			if (!prv_w5500_ctrl->socket[i].in_use)
			{
				socket_id = i;
				prv_w5500_ctrl->next_socket_index = i + 1;
				break;
			}
		}
	}
	if (prv_w5500_ctrl->next_socket_index >= MAX_SOCK_NUM)
	{
		prv_w5500_ctrl->next_socket_index = 1;
	}
	if (socket_id > 0)
	{
		prv_w5500_ctrl->tag++;
		*tag = prv_w5500_ctrl->tag;

		prv_w5500_ctrl->socket[socket_id].in_use = 1;
		prv_w5500_ctrl->socket[socket_id].tag = *tag;
		prv_w5500_ctrl->socket[socket_id].rx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].tx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].param = param;
		prv_w5500_ctrl->socket[socket_id].is_tcp = is_tcp;
		prv_w5500_ctrl->socket[socket_id].rx_waiting = 0;
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].tx_head, w5500_del_data_cache, NULL);
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_del_data_cache, NULL);
	}
	W5500_UNLOCK;
	return socket_id;
}

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
static int w5500_socket_connect_ex(int socket_id, uint64_t tag,  uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	PV_Union uPV;
	uPV.u16[0] = local_port;
	uPV.u16[1] = remote_port;
	W5500_LOCK;
	llist_traversal(&prv_w5500_ctrl->socket[socket_id].tx_head, w5500_del_data_cache, NULL);
	llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_del_data_cache, NULL);
	W5500_UNLOCK;
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_CONNECT, socket_id, remote_ip->ipv4, uPV.u32);
	uPV.u32 = remote_ip->ipv4;
//	DBG("%u.%u.%u.%u", uPV.u8[0], uPV.u8[1], uPV.u8[2], uPV.u8[3]);
	return 0;
}
//作为server绑定一个port，开始监听
static int w5500_socket_listen(int socket_id, uint64_t tag,  uint16_t local_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_LISTEN, socket_id, local_port, NULL);
	return 0;
}
//作为server接受一个client
static int w5500_socket_accept(int socket_id, uint64_t tag,  luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	uint8_t temp[16];
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	w5500_xfer(user_data, W5500_SOCKET_DEST_IP0, socket_index(socket_id)|socket_reg, temp, 6);
	remote_ip->is_ipv6 = 0;
	remote_ip->ipv4 = BytesGetLe32(temp);
	*remote_port = BytesGetBe16(temp + 4);
	DBG("client %d.%d.%d.%d, %u", temp[0], temp[1], temp[2], temp[3], *remote_port);
	return 0;
}
//主动断开一个tcp连接，需要走完整个tcp流程，用户需要接收到close ok回调才能确认彻底断开
static int w5500_socket_disconnect_ex(int socket_id, uint64_t tag,  void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_CLOSE, socket_id, 0, 0);
	return 0;
}

static int w5500_socket_force_close(int socket_id, void *user_data)
{
	W5500_LOCK;
	w5500_socket_close(prv_w5500_ctrl, socket_id);
	if (prv_w5500_ctrl->socket[socket_id].in_use)
	{
		prv_w5500_ctrl->socket[socket_id].in_use = 0;
		prv_w5500_ctrl->socket[socket_id].tag = 0;
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].tx_head, w5500_del_data_cache, NULL);
		llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_del_data_cache, NULL);
		prv_w5500_ctrl->socket[socket_id].rx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].tx_wait_size = 0;
		prv_w5500_ctrl->socket[socket_id].param = NULL;
	}
	W5500_UNLOCK;
	return 0;
}

static int w5500_socket_close_ex(int socket_id, uint64_t tag,  void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	return w5500_socket_force_close(socket_id, user_data);

}

static uint32_t w5500_socket_read_data(uint8_t *buf, uint32_t *read_len, uint32_t len, socket_data_t *p)
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

static int w5500_socket_receive(int socket_id, uint64_t tag,  uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t *remote_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	W5500_LOCK;
	uint32_t read_len = 0;
	if (buf)
	{
		socket_data_t *p = (socket_data_t *)llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_next_data_cache, &prv_w5500_ctrl->socket[socket_id]);

		if (prv_w5500_ctrl->socket[socket_id].is_tcp)
		{
			while((read_len < len) && p)
			{
				prv_w5500_ctrl->socket[socket_id].rx_wait_size -= w5500_socket_read_data(buf + read_len, &read_len, len, p);
				p = (socket_data_t *)llist_traversal(&prv_w5500_ctrl->socket[socket_id].rx_head, w5500_next_data_cache, &prv_w5500_ctrl->socket[socket_id]);
			}
		}
		else
		{
			prv_w5500_ctrl->socket[socket_id].rx_wait_size -= w5500_socket_read_data(buf + read_len, &read_len, len, p);
		}
		if (llist_empty(&prv_w5500_ctrl->socket[socket_id].rx_head))
		{
			prv_w5500_ctrl->socket[socket_id].rx_wait_size = 0;
		}
	}
	else
	{
		read_len = prv_w5500_ctrl->socket[socket_id].rx_wait_size;
	}
	W5500_UNLOCK;
	if ((prv_w5500_ctrl->socket[socket_id].rx_wait_size < SOCK_BUF_LEN) && prv_w5500_ctrl->socket[socket_id].rx_waiting)
	{
		prv_w5500_ctrl->socket[socket_id].rx_waiting = 0;
		DBG("read waiting data");
		w5500_sys_socket_callback(prv_w5500_ctrl, socket_id, Sn_IR_RECV);
	}
	return read_len;
}
static int w5500_socket_send(int socket_id, uint64_t tag, const uint8_t *buf, uint32_t len, int flags, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	if (prv_w5500_ctrl->socket[socket_id].tx_wait_size >= SOCK_BUF_LEN) return 0;

	socket_data_t *p = w5500_create_data_node(prv_w5500_ctrl, socket_id, buf, len, remote_ip, remote_port);
	if (p)
	{
		W5500_LOCK;
		llist_add_tail(&p->node, &prv_w5500_ctrl->socket[socket_id].tx_head);
		prv_w5500_ctrl->socket[socket_id].tx_wait_size += len;
		W5500_UNLOCK;
		platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_TX, socket_id, 0, 0);
		result = len;
	}
	else
	{
		result = -1;
	}
	return result;
}

void w5500_socket_clean(int *vaild_socket_list, uint32_t num, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return;
	int socket_list[MAX_SOCK_NUM] = {0,0,0,0,0,0,0,0};
	uint32_t i;
	for(i = 1; i < num + 1; i++)
	{
		if ( (vaild_socket_list[i] > 0) && (vaild_socket_list[i] < MAX_SOCK_NUM) )
		{
			socket_list[vaild_socket_list[i]] = 1;
		}
		DBG("%d,%d",i,vaild_socket_list[i]);
	}
	for(i = 1; i < MAX_SOCK_NUM; i++)
	{
		DBG("%d,%d",i,socket_list[i]);
		if ( !socket_list[i] )
		{
			W5500_LOCK;
			prv_w5500_ctrl->socket[i].in_use = 0;
			prv_w5500_ctrl->socket[i].tag = 0;
			llist_traversal(&prv_w5500_ctrl->socket[i].tx_head, w5500_del_data_cache, NULL);
			llist_traversal(&prv_w5500_ctrl->socket[i].rx_head, w5500_del_data_cache, NULL);
			prv_w5500_ctrl->socket[i].rx_wait_size = 0;
			prv_w5500_ctrl->socket[i].tx_wait_size = 0;
			w5500_socket_close(prv_w5500_ctrl, i);
			W5500_UNLOCK;
		}
	}
}

static int w5500_getsockopt(int socket_id, uint64_t tag,  int level, int optname, void *optval, uint32_t *optlen, void *user_data)
{
	return -1;
}
static int w5500_setsockopt(int socket_id, uint64_t tag,  int level, int optname, const void *optval, uint32_t optlen, void *user_data)
{
	return -1;
}
static int w5500_get_local_ip_info(luat_ip_addr_t *ip, luat_ip_addr_t *submask, luat_ip_addr_t *gateway, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;

	if (prv_w5500_ctrl->static_ip)
	{
		ip->ipv4 = prv_w5500_ctrl->static_ip;
		ip->is_ipv6 = 0;
		submask->ipv4 = prv_w5500_ctrl->static_submask;
		submask->is_ipv6 = 0;
		gateway->ipv4 = prv_w5500_ctrl->static_gateway;
		gateway->is_ipv6 = 0;
		return 0;
	}
	else
	{
		if (!prv_w5500_ctrl->ip_ready)
		{
			return -1;
		}
		ip->ipv4 = prv_w5500_ctrl->dhcp_client.ip;
		ip->is_ipv6 = 0;
		submask->ipv4 = prv_w5500_ctrl->dhcp_client.submask;
		submask->is_ipv6 = 0;
		gateway->ipv4 = prv_w5500_ctrl->dhcp_client.gateway;
		gateway->is_ipv6 = 0;
		return 0;
	}
}

static int w5500_user_cmd(int socket_id, uint64_t tag, uint32_t cmd, uint32_t value, void *user_data)
{
	int result = w5500_check_socket(user_data, socket_id, tag);
	if (result) return result;
	switch (cmd)
	{
	case NW_CMD_AUTO_HEART_TIME:
		value = (value + 4) / 5;
		platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_REG_OP, W5500_SOCKET_KEEP_TIME, socket_id, value);
		break;
	default:
		return -1;
	}
	return 0;
}

static int w5500_dns(const char *domain_name, uint32_t len, void *param, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	char *prv_domain_name = (char *)malloc(len);
	memcpy(prv_domain_name, domain_name, len);
	platform_send_event(prv_w5500_ctrl->task_handle, EV_W5500_SOCKET_DNS, prv_domain_name, len, param);
	return 0;
}

static int w5500_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return -1;
	if (server_index >= MAX_DNS_SERVER) return -1;
	prv_w5500_ctrl->dns_client.dns_server[server_index] = *ip;
	prv_w5500_ctrl->dns_client.is_static_dns[server_index] = 1;
	return 0;
}

static void w5500_socket_set_callback(CBFuncEx_t cb_fun, void *param, void *user_data)
{
	if (user_data != prv_w5500_ctrl) return ;
	((lwip_netif_ctrl_t *)user_data)->socket_cb = cb_fun?cb_fun:w5500_dummy_callback;
	((lwip_netif_ctrl_t *)user_data)->user_data = param;
}

static network_adapter_info prv_w5500_adapter =
{
		.check_ready = lwip_check_ready,
		.create_soceket = w5500_create_soceket,
		.socket_connect = w5500_socket_connect_ex,
		.socket_listen = w5500_socket_listen,
		.socket_accept = w5500_socket_accept,
		.socket_disconnect = w5500_socket_disconnect_ex,
		.socket_close = w5500_socket_close_ex,
		.socket_force_close = w5500_socket_force_close,
		.socket_receive = w5500_socket_receive,
		.socket_send = w5500_socket_send,
		.socket_check = w5500_socket_check,
		.socket_clean = w5500_socket_clean,
		.getsockopt = w5500_getsockopt,
		.setsockopt = w5500_setsockopt,
		.user_cmd = w5500_user_cmd,
		.dns = w5500_dns,
		.set_dns_server = w5500_set_dns_server,
		.get_local_ip_info = w5500_get_local_ip_info,
		.socket_set_callback = w5500_socket_set_callback,
		.name = "lwip",
		.max_socket_num = MAX_SOCK_NUM,
		.no_accept = 0,
		.is_posix = 0,
};

#endif

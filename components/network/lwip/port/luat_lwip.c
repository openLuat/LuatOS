#include "platform_def.h"
#include "luat_base.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_network_adapter.h"
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
	EV_LWIP_SOCKET_DNS,
	EV_LWIP_SOCKET_CONNECT,
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

typedef struct
{
	struct netif netif;
	uint8_t network_ready;
}lwip_netif_ctrl_t;

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
	socket_ctrl_t socket[MAX_SOCK_NUM];
	lwip_netif_ctrl_t lwip_netif[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	uint64_t last_sleep_ms;
	uint64_t socket_tag;
	CBFuncEx_t socket_cb;
	void *user_data;
	void *task_handle;
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

static LUAT_RT_RET_TYPE luat_lwip_timer_cb(LUAT_RT_CB_PARAM)
{
	luat_send_event_to_task(prvlwip.task_handle, (uint32_t)param, 0, 0, 0);
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
//			tcp_output(prvlwip.socket[event.Param1].pcb.tcp);
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
		case EV_LWIP_SOCKET_DNS:
			break;
		case EV_LWIP_SOCKET_CONNECT:
			break;
		case EV_LWIP_SOCKET_LISTEN:
			break;
		case EV_LWIP_SOCKET_ACCPET:
			break;
		case EV_LWIP_SOCKET_CLOSE:
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
		DBG("tag error");
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

static int luat_lwip_check_socket(void *user_data, int socket_id, uint64_t tag)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	if (socket_id >= MAX_SOCK_NUM) return -1;
	if (prvlwip.socket[socket_id].tag != tag) return -1;
	if (!prvlwip.socket[socket_id].in_use) return -1;
	return 0;
}

static int luat_lwip_socket_check(int socket_id, uint64_t tag, void *user_data)
{
	return luat_lwip_check_socket(user_data, socket_id, tag);
}


static uint8_t luat_lwip_check_ready(void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return 0;
	return prvlwip.lwip_netif[(uint32_t)user_data].network_ready;
}

static int luat_lwip_create_soceket(uint8_t is_tcp, uint64_t *tag, void *param, uint8_t is_ipv6, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
	int i, socket_id, error;
	socket_id = -1;
	platform_lock_mutex(prvlwip.socket_mutex);
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
		prvlwip.socket_tag++;
		*tag = prvlwip.socket_tag;
		prvlwip.socket[socket_id].in_use = 1;
		prvlwip.socket[socket_id].tag = *tag;
		prvlwip.socket[socket_id].param = param;
		prvlwip.socket[socket_id].is_tcp = is_tcp;
		llist_traversal(&prvlwip.socket[socket_id].rx_head, luat_lwip_del_data_cache, NULL);
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
			prvlwip.socket[socket_id].pcb.ip = NULL;
		}
	}
	platform_unlock_mutex(prvlwip.socket_mutex);
	return socket_id;
}

//作为client绑定一个port，并连接remote_ip和remote_port对应的server
static int luat_lwip_socket_connect_ex(int socket_id, uint64_t tag,  uint16_t local_port, luat_ip_addr_t *remote_ip, uint16_t remote_port, void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	PV_Union uPV;
	uPV.u16[0] = local_port;
	uPV.u16[1] = remote_port;
	//llist_traversal(&prvlwip.socket[socket_id].rx_head, luat_lwip_del_data_cache, NULL);
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_CONNECT, socket_id, remote_ip, uPV.u32);
	return 0;
}
//作为server绑定一个port，开始监听
static int luat_lwip_socket_listen(int socket_id, uint64_t tag,  uint16_t local_port, void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_LISTEN, socket_id, local_port, NULL);
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
static int luat_lwip_socket_disconnect_ex(int socket_id, uint64_t tag,  void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_CLOSE, socket_id, 0, 0);
	return 0;
}

static int luat_lwip_socket_force_close(int socket_id, void *user_data)
{
	int error;
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
		prvlwip.socket[socket_id].pcb.ip = NULL;
	}


	if (prvlwip.socket[socket_id].in_use)
	{
		prvlwip.socket[socket_id].in_use = 0;
		prvlwip.socket[socket_id].tag = 0;
		prvlwip.socket[socket_id].param = NULL;
		llist_traversal(&prvlwip.socket[socket_id].rx_head, luat_lwip_del_data_cache, NULL);
	}
	return 0;
}

static int luat_lwip_socket_close_ex(int socket_id, uint64_t tag,  void *user_data)
{
	int result = luat_lwip_check_socket(user_data, socket_id, tag);
	if (result) return result;
	platform_lock_mutex(prvlwip.socket_mutex);
	luat_lwip_socket_force_close(socket_id, user_data);
	platform_unlock_mutex(prvlwip.socket_mutex);
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
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_TX, socket_id, buf, len);
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
	platform_lock_mutex(prvlwip.socket_mutex);
	for(i = 0; i < MAX_SOCK_NUM; i++)
	{
		NET_DBG("%d,%d",i,socket_list[i]);
		if ( !socket_list[i] )
		{
			luat_lwip_socket_force_close(i, user_data);
		}
	}
	platform_unlock_mutex(prvlwip.socket_mutex);
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
	platform_send_event(prvlwip.task_handle, EV_LWIP_SOCKET_DNS, prv_domain_name, len, param);
	return 0;
}

static int luat_lwip_set_dns_server(uint8_t server_index, luat_ip_addr_t *ip, void *user_data)
{
	if ((uint32_t)user_data >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) return -1;
//	if (server_index >= MAX_DNS_SERVER) return -1;
//	prvlwip.dns_client.dns_server[server_index] = *ip;
//	prvlwip.dns_client.is_static_dns[server_index] = 1;
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
		.socket_connect = luat_lwip_socket_connect_ex,
		.socket_listen = luat_lwip_socket_listen,
		.socket_accept = luat_lwip_socket_accept,
		.socket_disconnect = luat_lwip_socket_disconnect_ex,
		.socket_close = luat_lwip_socket_close_ex,
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



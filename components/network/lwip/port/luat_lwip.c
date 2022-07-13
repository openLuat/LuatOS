#include "platform_def.h"
#include "luat_base.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_network_adapter.h"

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
	thread.priority = 50;
	luat_thread_start(&thread);
	prvlwip.lwip_task_handler = thread.handle;
	lwip_init();
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

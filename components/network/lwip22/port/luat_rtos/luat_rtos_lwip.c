#include "platform_def.h"
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_crypto.h"
#include "dns_def.h"
#include "lwip/tcpip.h"
#include "lwip/init.h"

#include "luat_network_adapter.h"
#include "net_lwip_port.h"
#define LUAT_LOG_TAG "lwip"
#include "luat_log.h"

#define HANDLER(x) x
#define LWIP_SYS_TIMER_CNT	(11)

extern u32_t tcp_ticks;

typedef struct
{
	uint32_t interval_ms;
	lwip_cyclic_timer_handler handler;
}lwip_timer_handler_t;

typedef struct
{
	sys_timeout_handler handler;
	void *args;
	luat_rtos_timer_t timer;
}lwip_timer_t;

static const lwip_timer_handler_t prv_lwip_timer_list[LWIP_SYS_TIMER_CNT] =
{
#if LWIP_TCP
  /* The TCP timer is a special case: it does not have to run always and
     is triggered to start from TCP using tcp_timer_needed() */
  {TCP_TMR_INTERVAL, HANDLER(tcp_tmr)},
#endif
#if LWIP_IPV4
#if IP_REASSEMBLY
  {IP_TMR_INTERVAL, HANDLER(ip_reass_tmr)},
#endif /* IP_REASSEMBLY */
#if LWIP_ARP
  {ARP_TMR_INTERVAL, HANDLER(etharp_tmr)},
#endif /* LWIP_ARP */
#if LWIP_DHCP
  {DHCP_COARSE_TIMER_MSECS, HANDLER(dhcp_coarse_tmr)},
  {DHCP_FINE_TIMER_MSECS, HANDLER(dhcp_fine_tmr)},
#endif /* LWIP_DHCP */
#if LWIP_ACD
  {ACD_TMR_INTERVAL, HANDLER(acd_tmr)},
#endif /* LWIP_ACD */
#if LWIP_IGMP
  {IGMP_TMR_INTERVAL, HANDLER(igmp_tmr)},
#endif /* LWIP_IGMP */
#endif /* LWIP_IPV4 */
#if LWIP_DNS
  {DNS_TMR_INTERVAL, HANDLER(dns_tmr)},
#endif /* LWIP_DNS */
#if LWIP_IPV6
  {ND6_TMR_INTERVAL, HANDLER(nd6_tmr)},
#if LWIP_IPV6_REASS
  {IP6_REASS_TMR_INTERVAL, HANDLER(ip6_reass_tmr)},
#endif /* LWIP_IPV6_REASS */
#if LWIP_IPV6_MLD
  {MLD6_TMR_INTERVAL, HANDLER(mld6_tmr)},
#endif /* LWIP_IPV6_MLD */
#if LWIP_IPV6_DHCP6
  {DHCP6_TIMER_MSECS, HANDLER(dhcp6_tmr)},
#endif /* LWIP_IPV6_DHCP6 */
#endif /* LWIP_IPV6 */
};

typedef struct
{
	uint64_t last_sleep_ms;
	luat_rtos_timer_t sys_cyclic_timer[LWIP_SYS_TIMER_CNT];
	void *task_handle;
	uint8_t tcpip_tcp_timer_active;
}lwip_ctrl_struct;
static lwip_ctrl_struct prvlwip;

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
	EV_LWIP_API_RUN = USER_EVENT_ID_START + 0x3000000,
	EV_LWIP_SYS_TIMEOUT,
	EV_LWIP_TIMEOUT,
};

unsigned int lwip_port_rand(void)
{
	PV_Union uPV;
	luat_crypto_trng((char *)uPV.u8, 4);
	return uPV.u32;
}

uint32_t net_lwip_rand()
{
	PV_Union uPV;
	luat_crypto_trng((char *)uPV.u8, 4);
	return uPV.u32;
}

static LUAT_RT_RET_TYPE luat_lwip_sys_timer_cb(LUAT_RT_CB_PARAM)
{
	luat_send_event_to_task(prvlwip.task_handle, EV_LWIP_SYS_TIMEOUT, (uint32_t)param, 0, 0);
	return LUAT_RT_RET;
}

static LUAT_RT_RET_TYPE luat_lwip_timer_cb(LUAT_RT_CB_PARAM)
{
	luat_send_event_to_task(prvlwip.task_handle, EV_LWIP_TIMEOUT, (uint32_t)param, 0, 0);
	return LUAT_RT_RET;
}

int luat_lwip_event_send(uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	return luat_send_event_to_task(prvlwip.task_handle, id, param1, param2, param3);
}

int luat_lwip_api_run(uint32_t func, uint32_t param)
{
	return luat_send_event_to_task(prvlwip.task_handle, EV_LWIP_API_RUN, func, param, 0);
}

err_t  tcpip_try_callback(tcpip_callback_fn function, void *ctx)
{
	return luat_lwip_api_run((uint32_t)function, (uint32_t)ctx);
}

err_t  tcpip_callback(tcpip_callback_fn function, void *ctx)
{
	return luat_lwip_api_run((uint32_t)function, (uint32_t)ctx);
}

LUAT_WEAK void luat_lwip_event_run(void *p)
{

}
static void luat_lwip_task(void *param)
{
//	luat_network_cb_param_t cb_param;
	TaskFun_t cb;
	lwip_timer_t *user_timer;
	luat_event_t event;
	HANDLE cur_task = luat_get_current_task();
//	struct tcp_pcb *pcb, *dpcb;
	struct netif *netif;
//	ip_addr_t *p_ip, *local_ip;
//	struct pbuf *out_p;
	int error;
//	PV_Union uPV;
//	uint8_t socket_id;
//	uint8_t adapter_index;
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
//				LLOGD("tcp ticks add to %u", tcp_ticks);
			}
		}
		else
		{
			prvlwip.last_sleep_ms = luat_mcu_tick64_ms();
		}
//		socket_id = event.Param1;
//		adapter_index = event.Param3;
		switch(event.id)
		{
		case EV_LWIP_NETIF_INPUT:
			netif = (struct netif *)event.param3;
			error = netif->input((struct pbuf *)event.param1, netif);
			if(error != ERR_OK)
			{
				LLOGD("%d", error);
				pbuf_free((struct pbuf *)event.param1);
			}
			break;
		case EV_LWIP_API_RUN:
			cb = (TaskFun_t)event.param1;
			cb((void *)event.param2);
			break;
		case EV_LWIP_SYS_TIMEOUT:
			//LLOGD("sys timer%d", event.param1);
			prv_lwip_timer_list[event.param1].handler();
			break;
		case EV_LWIP_TIMEOUT:
			user_timer = (lwip_timer_t *)event.param1;
			user_timer->handler(user_timer->args);
			luat_release_rtos_timer(user_timer->timer);
			luat_heap_free(user_timer);
			break;
		default:
			luat_lwip_event_run(&event);
			break;
		}
	}

}

void luat_lwip_init(void)
{
	uint32_t i;
	for(uint32_t i = 0; i < LWIP_SYS_TIMER_CNT; i++)
	{
		prvlwip.sys_cyclic_timer[i] = luat_create_rtos_timer(luat_lwip_sys_timer_cb, (void *)i, NULL);
	}
	tcp_ticks = luat_mcu_tick64_ms() / TCP_SLOW_INTERVAL;
	prvlwip.last_sleep_ms = luat_mcu_tick64_ms();
	luat_rtos_task_create(&prvlwip.task_handle, 16 * 1024, 110, "lwip", luat_lwip_task, NULL, 64);
	lwip_init();
	for(i = 1; i < LWIP_SYS_TIMER_CNT; i++)
	{
		if (prv_lwip_timer_list[i].interval_ms && prv_lwip_timer_list[i].handler)
		{
			luat_start_rtos_timer(prvlwip.sys_cyclic_timer[i], prv_lwip_timer_list[i].interval_ms, 1);
		}
	}
}

void tcp_timer_needed(void)
{
	if (tcp_active_pcbs || tcp_tw_pcbs) {
    /* restart timer */
		if (!prvlwip.tcpip_tcp_timer_active)
		{
			luat_start_rtos_timer(prvlwip.sys_cyclic_timer[0], TCP_TMR_INTERVAL, 1);
			prvlwip.tcpip_tcp_timer_active = 1;
		}
	} else {
		/* disable timer */
		prvlwip.tcpip_tcp_timer_active = 0;
		luat_stop_rtos_timer(prvlwip.sys_cyclic_timer[0]);
	}
}

void sys_timeouts_init(void)
{
	;
}
void sys_timeout(u32_t msecs, sys_timeout_handler handler, void *arg)
{
	lwip_timer_t *user_timer = luat_heap_malloc(sizeof(lwip_timer_t));
	user_timer->timer = luat_create_rtos_timer(luat_lwip_timer_cb, (void *)user_timer, NULL);
	user_timer->handler = handler;
	user_timer->args = arg;
	luat_start_rtos_timer(user_timer->timer, msecs, 0);
}
void sys_untimeout(sys_timeout_handler handler, void *arg)
{
	;
}

u32_t sys_now(void)
{
	return (u32_t)luat_mcu_tick64_ms();
}

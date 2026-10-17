#include "platform_def.h"
#include "luat_base.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_rtos.h"
#include "luat_crypto.h"
#include "dns_def.h"
#include "lwip/tcpip.h"
#include "lwip/init.h"
#include <string.h>		/* memset, sys_timeout 的定时器节点初始化 */

#include "luat_network_adapter.h"
#include "net_lwip_port.h"
#define LUAT_LOG_TAG "lwip"
#include "luat_log.h"

#ifndef __LUAT_C_CODE_IN_ISR__
#define __LUAT_C_CODE_IN_ISR__
#endif
#ifndef __LUAT_C_CODE_IN_RAM__
#define __LUAT_C_CODE_IN_RAM__
#endif

#define HANDLER(x) x
#define LWIP_SYS_TIMER_CNT	(11)

extern u32_t tcp_ticks;

typedef struct
{
	uint32_t interval_ms;
	lwip_cyclic_timer_handler handler;
}lwip_timer_handler_t;

typedef struct lwip_timer
{
	sys_timeout_handler handler;
	void *args;
	luat_rtos_timer_t timer;
	/* 登记表用: 供 sys_untimeout 反查 + 事件按 id 寻址(见 sys_timeout 注释) */
	struct lwip_timer *next;
	uint32_t id;
}lwip_timer_t;

/* sys_timeout 建立的单次定时器登记表。定时器回调与 EV_LWIP_TIMEOUT 事件都只
 * 携带 id(整数)而不携带节点指针, 所以 sys_untimeout 可以安全地把节点摘链并
 * 释放: 即便此前投递的事件/回调随后才被调度, 也只会按 id 查表失败而直接返回,
 * 不会解引用已释放内存。链表操作统一在 luat_rtos_entry_critical 保护下进行。 */
static lwip_timer_t *prv_user_timer_list = NULL;
static uint32_t prv_user_timer_id = 0;

/* 在临界区内调用: 按 id 摘链并返回该节点, 未找到返回 NULL */
static lwip_timer_t* prv_user_timer_unlink_by_id(uint32_t id)
{
	lwip_timer_t *node = prv_user_timer_list;
	lwip_timer_t *prev = NULL;
	while(node)
	{
		if (node->id == id)
		{
			if (prev) prev->next = node->next;
			else prv_user_timer_list = node->next;
			node->next = NULL;
			return node;
		}
		prev = node;
		node = node->next;
	}
	return NULL;
}

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

__LUAT_C_CODE_IN_ISR__ static LUAT_RT_RET_TYPE luat_lwip_sys_timer_cb(LUAT_RT_CB_PARAM)
{
	luat_send_event_to_task(prvlwip.task_handle, EV_LWIP_SYS_TIMEOUT, (uint32_t)param, 0, 0);
	return LUAT_RT_RET;
}

__LUAT_C_CODE_IN_ISR__ static LUAT_RT_RET_TYPE luat_lwip_timer_cb(LUAT_RT_CB_PARAM)
{
	/* param 是定时器 id(不是节点指针), 见 sys_timeout */
	luat_send_event_to_task(prvlwip.task_handle, EV_LWIP_TIMEOUT, (uint32_t)(uintptr_t)param, 0, 0);
	return LUAT_RT_RET;
}

__LUAT_C_CODE_IN_ISR__ int luat_lwip_event_send(uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3)
{
	return luat_send_event_to_task(prvlwip.task_handle, id, param1, param2, param3);
}

__LUAT_C_CODE_IN_ISR__ int luat_lwip_input(struct pbuf *p, struct netif *netif)
{
	return luat_send_event_to_task(prvlwip.task_handle, EV_LWIP_NETIF_INPUT, (uint32_t)p, 0, (uint32_t)netif);
}

__LUAT_C_CODE_IN_ISR__ int luat_lwip_api_run(uint32_t func, uint32_t param)
{
	return luat_send_event_to_task(prvlwip.task_handle, EV_LWIP_API_RUN, func, param, 0);
}

__LUAT_C_CODE_IN_ISR__ err_t  tcpip_try_callback(tcpip_callback_fn function, void *ctx)
{
	return luat_lwip_api_run((uint32_t)function, (uint32_t)ctx);
}

__LUAT_C_CODE_IN_ISR__ err_t  tcpip_callback(tcpip_callback_fn function, void *ctx)
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
			/* 先按 id 摘链(与 sys_untimeout 互斥), 摘不到说明已被取消 */
			{
				uint32_t critical = luat_rtos_entry_critical();
				user_timer = prv_user_timer_unlink_by_id((uint32_t)event.param1);
				luat_rtos_exit_critical(critical);
			}
			if (user_timer)
			{
				user_timer->handler(user_timer->args);
				luat_release_rtos_timer(user_timer->timer);
				luat_heap_free(user_timer);
			}
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
	uint32_t critical;
	lwip_timer_t *user_timer = luat_heap_malloc(sizeof(lwip_timer_t));
	if (user_timer == NULL)
	{
		LLOGE("sys_timeout: no mem for timer");
		return;
	}
	memset(user_timer, 0, sizeof(lwip_timer_t));
	user_timer->handler = handler;
	user_timer->args = arg;

	/* 先登记再启动定时器: 定时器回调只带 id, 必须保证 id 已在表内 */
	critical = luat_rtos_entry_critical();
	prv_user_timer_id++;
	if (prv_user_timer_id == 0) prv_user_timer_id = 1; /* 0 保留 */
	user_timer->id = prv_user_timer_id;
	user_timer->next = prv_user_timer_list;
	prv_user_timer_list = user_timer;
	luat_rtos_exit_critical(critical);

	user_timer->timer = luat_create_rtos_timer(luat_lwip_timer_cb, (void *)(uintptr_t)user_timer->id, NULL);
	if (user_timer->timer == NULL)
	{
		LLOGE("sys_timeout: create timer failed");
		critical = luat_rtos_entry_critical();
		prv_user_timer_unlink_by_id(user_timer->id);
		luat_rtos_exit_critical(critical);
		luat_heap_free(user_timer);
		return;
	}
	luat_start_rtos_timer(user_timer->timer, msecs, 0);
}
void sys_untimeout(sys_timeout_handler handler, void *arg)
{
	uint32_t critical;
	lwip_timer_t *node;
	lwip_timer_t *prev = NULL;

	critical = luat_rtos_entry_critical();
	node = prv_user_timer_list;
	while(node)
	{
		if (node->handler == handler && node->args == arg)
		{
			if (prev) prev->next = node->next;
			else prv_user_timer_list = node->next;
			node->next = NULL;
			break;
		}
		prev = node;
		node = node->next;
	}
	luat_rtos_exit_critical(critical);

	if (node == NULL)
	{
		/* 已经到期并被处理, 或从未登记, 都属于无事可做 */
		return;
	}
	/* 摘链后即使定时器已经触发, 其回调也只会投递一个查不到 id 的事件 */
	luat_stop_rtos_timer(node->timer);
	luat_release_rtos_timer(node->timer);
	luat_heap_free(node);
}

u32_t sys_now(void)
{
	return (u32_t)luat_mcu_tick64_ms();
}

u32_t sys_jiffies(void)
{
	/* LWIP_TIMERS_CUSTOM=1 时 lwip 自带的 core/timeouts.c 不参与编译, sys_jiffies
	 * 归移植层提供。ppp/magic.c 用它做随机数种子, 给毫秒时钟即可。 */
	return (u32_t)luat_mcu_tick64_ms();
}

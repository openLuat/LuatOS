#include "platform_def.h"
#include "luat_base.h"

#include "luat_network_adapter.h"
#define NET_DBG(x,y...) DBG_Printf("%s %d:"x"\r\n", __FUNCTION__,__LINE__,##y)

extern u32_t tcp_ticks;
/* Satisfy the TCP code which calls this function */
static uint8_t prv_tcpip_tcp_timer_active;
static uint64_t prv_last_sleep_ms;
static void luat_lwip_task(void *param);
static void *prv_lwip_task_handler;
void luat_lwip_init(void)
{
	luat_thread_t thread;
	tcp_ticks = luat_mcu_tick64_ms() / TCP_SLOW_INTERVAL;
	prv_last_sleep_ms = luat_mcu_tick64_ms();
	thread.task_fun = luat_lwip_task;
	thread.name = "lwip";
	thread.stack_size = 16 * 1024;
	thread.priority = 50;
	luat_thread_start(&thread);
	prv_lwip_task_handler = thread.handle;
	lwip_init();
}

void tcpip_tcp_timer(void *arg)
{
  LWIP_UNUSED_ARG(arg);
  tcp_tmr();
  if (tcp_active_pcbs || tcp_tw_pcbs) {
      sys_timeout(TCP_TMR_INTERVAL, tcpip_tcp_timer, NULL);
  } else {
	  prv_tcpip_tcp_timer_active = 0;
  }
}
void tcp_timer_needed(void)
{
  if (!prv_tcpip_tcp_timer_active && (tcp_active_pcbs || tcp_tw_pcbs)) {
	  prv_tcpip_tcp_timer_active = 1;
//    sys_timeout(TCP_TMR_INTERVAL, tcpip_tcp_timer, NULL);
  }
}
//void cyclic_timer(void *arg)
//{
//  const struct lwip_cyclic_timer* cyclic = (const struct lwip_cyclic_timer*)arg;
//   if (cyclic->handler())
//         sys_timeout(cyclic->interval_ms, cyclic_timer, arg);
//}
//void sys_timeouts_init(void)
//{
//
//  size_t i;
//  for (i = 1; i < LWIP_ARRAYSIZE(lwip_cyclic_timers); i++) {
//    sys_timeout(lwip_cyclic_timers[i].interval_ms, cyclic_timer, LWIP_CONST_CAST(void*, &lwip_cyclic_timers[i]));
//  }
//}

u32_t sys_now(void)
{
	return (u32_t)luat_mcu_tick64_ms();
}

static void luat_lwip_task(void *param)
{
	OS_EVENT event;
	HANDLE cur_task = luat_get_current_task();
	while(1)
	{
		if (!prv_tcpip_tcp_timer_active)
		{
			if ((luat_mcu_tick64_ms() - prv_last_sleep_ms) >= TCP_SLOW_INTERVAL)
			{
				tcp_ticks += (luat_mcu_tick64_ms() - prv_last_sleep_ms) / TCP_SLOW_INTERVAL;
				prv_last_sleep_ms = luat_mcu_tick64_ms();
				NET_DBG("tcp ticks add to %u", tcp_ticks);
			}
		}
		else
		{
			prv_last_sleep_ms = luat_mcu_tick64_ms();
		}
		if (luat_wait_event_from_task(cur_task, 0, &event, NULL, 0) != ERROR_NONE)
		{
			continue;
		}

	}

}

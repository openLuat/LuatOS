#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"

#include "rtthread.h"
#include "rthw.h"

#define DBG_TAG           "rtt.timer"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

static char timer_name[32];

static void rt_timer_callback(void *param) {
    rtos_msg_t msg;
    luat_timer_t *timer = (luat_timer_t*)param;
    msg.handler = timer->func;
    msg.ptr = param;
    luat_msgbus_put(&msg, 1);
}

int luat_timer_start(luat_timer_t* timer) {
    rt_sprintf(timer_name, "t%06X", timer->id);
    LOG_D("rtt timer name=%s", timer_name);
    rt_tick_t tick = rt_tick_from_millisecond(timer->timeout);
    rt_uint8_t flag = timer->repeat ? RT_TIMER_FLAG_PERIODIC : RT_TIMER_FLAG_ONE_SHOT ;
    rt_timer_t r_timer = rt_timer_create(timer_name, rt_timer_callback, timer, tick, flag|RT_TIMER_FLAG_SOFT_TIMER);
    if (r_timer == RT_NULL) {
        LOG_E("rt_timer_create FAIL!!!");
        return 1;
    }
    if (rt_timer_start(r_timer) != RT_EOK) {
        LOG_E("rt_timer_start FAIL!!!");
        rt_timer_delete(r_timer);
        return 1;
    };
    timer->os_timer = r_timer;
    LOG_D("rt_timer_start complete");
    return 0;
}

int luat_timer_stop(luat_timer_t* timer) {
    if (!timer)
        return 0;
    if (!timer->os_timer)
        return 0;
    rt_timer_stop((rt_timer_t)timer->os_timer);
    rt_timer_delete((rt_timer_t)timer->os_timer);
    return 0;
}

luat_timer_t* luat_timer_get(size_t timer_id) {
    rt_sprintf(timer_name, "t%06X", timer_id);
    rt_object_t obj = rt_object_find(timer_name, RT_Object_Class_Timer);
    if (obj != RT_NULL) {
        return (luat_timer_t*)((rt_timer_t)obj)->parameter;
    }
    return RT_NULL;
}


int luat_timer_mdelay(size_t ms) {
    if (ms > 0)
        rt_thread_mdelay(ms);
    return 0;
}

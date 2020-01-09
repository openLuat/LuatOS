#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"

#include "rtthread.h"

static int32_t timer_id = 0;
static char timer_name[32];

static void rt_timer_callback(void *param) {
    rt_kprintf("rt_timer_callback begin!!\n");
    struct rtos_msg msg;
    struct luat_timer_t *t = (struct luat_timer_t*)param;
    msg.handler = t->func;
    msg.ptr = param;
    luat_msgbus_put(&msg, 1);
    rt_kprintf("rt_timer_callback end!!\n");
}

int luat_timer_start(struct luat_timer_t* timer) {
    sprintf(timer_name, "luat_%ld", timer_id++);
    rt_tick_t time = timer->timeout;
    rt_uint8_t flag = timer->repeat ? RT_TIMER_FLAG_PERIODIC : RT_TIMER_FLAG_ONE_SHOT;
    rt_timer_t r_timer = rt_timer_create(timer_name, rt_timer_callback, timer, time, flag);
    if (r_timer == NULL) {
        rt_kprintf("rt_timer_create FAIL\n");
        return 1;
    }
    if (rt_timer_start(r_timer) != RT_EOK) {
        rt_kprintf("rt_timer_start FAIL\n");
        rt_timer_delete(r_timer);
        return 1;
    };
    timer->os_timer = r_timer;
    rt_kprintf("rt_timer_start complete!!\n");
    return 0;
}

int luat_timer_stop(struct luat_timer_t* timer) {
    if (!timer)
        return 0;
    if (!timer->os_timer)
        return 0;
    rt_timer_stop((rt_timer_t)timer->os_timer);
    rt_timer_delete((rt_timer_t)timer->os_timer);
    return 0;
}


int luat_timer_mdelay(size_t ms) {
    if (ms > 0)
        rt_thread_mdelay(ms);
    return 0;
}

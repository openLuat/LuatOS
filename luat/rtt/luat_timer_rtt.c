#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"
#include "luat_timer.h"

#include "rtthread.h"

static uint32_t timer_id = 0;
static char timer_name[32];

static void rt_timer_callback(void *param) {

}

int luat_timer_start(struct luat_timer_ec616_t* timer) {
    sprintf(&timer_name[0], "luat_%d", timer_id++);
    
    rt_timer_t r_timer = rt_timer_create(timer_name, rt_timer_callback, timer, timer->timeout * (1000/RT_TICK_PER_SECOND), timer->_repeat ? RT_TIMER_FLAG_PERIODIC : RT_TIMER_FLAG_ONE_SHOT);
    if (r_timer == NULL) {
        return 1;
    }
    if (rt_timer_start(r_timer) != RT_EOK) {
        rt_timer_delete(r_timer);
        return 1;
    };
    timer->os_timer = r_timer;
    return 0;
}

int luat_timer_stop(struct luat_timer_ec616_t* timer) {
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

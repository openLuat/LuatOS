#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "rtos"
#include "luat_log.h"

#define RTOS_LUA_DEBUG 0
#if RTOS_LUA_DEBUG == 0
#undef LLOGD
#define LLOGD(...)
#endif

/*timer*/

#define LUA_TIMER_COUNT 32
static luat_timer_t* timers[LUA_TIMER_COUNT] = {0};;

static void luat_timer_callback(LUAT_RT_CB_PARAM) {
    rtos_msg_t msg;
    luat_timer_t *timer = luat_timer_get((int)param);
    LLOGD("timer callback param:%d timer:%p",param,timer);
    if (timer == NULL)
        return;
    msg.handler = timer->func;
    msg.ptr = timer;
    msg.arg1 = (int)param;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
}

static int nextTimerSlot() {
    for (size_t i = 0; i < LUA_TIMER_COUNT; i++){
        if (timers[i] == NULL) {
            return i;
        }
    }
    return -1;
}

LUAT_WEAK int luat_timer_start(luat_timer_t* timer) {
    int timerIndex;
    LLOGD(">>luat_timer_start timeout=%ld", timer->timeout);
    timerIndex = nextTimerSlot();
    if (timerIndex < 0) {
        LLOGE("too many timers");
        return 1; // too many timer!!
    }
    luat_rtos_timer_create((luat_rtos_timer_t *)&timer->os_timer);
    LLOGD("timer id=%ld, timer=%p, os_timer=%p", timerIndex, timer,timer->os_timer);
    if (!timer->os_timer) {
        LLOGE("xTimerCreate FAIL");
        return -1;
    }
    timer->id=timerIndex;
    timers[timerIndex] = timer;
    int re = luat_rtos_timer_start(timer->os_timer, timer->timeout, timer->repeat, luat_timer_callback, (void*)timerIndex);
    LLOGD("timer id=%ld timeout=%ld start=%ld", timerIndex, timer->timeout, re);
    if (re) {
        LLOGE("xTimerStart FAIL");
        luat_rtos_timer_delete(timer->os_timer);
        timers[timerIndex] = NULL;
    }
    return 0;
}

LUAT_WEAK int luat_timer_stop(luat_timer_t* timer) {
    if (timer == NULL || timer->os_timer == NULL)
        return 1;
    for (int i = 0; i < LUA_TIMER_COUNT; i++)
    {
        if (timers[i] == timer) {
            timers[i] = NULL;
            break;
        }
    }
    luat_rtos_timer_stop(timer->os_timer);
    luat_rtos_timer_delete(timer->os_timer);
    timer->os_timer = NULL;
    return 0;
};

LUAT_WEAK luat_timer_t* luat_timer_get(size_t timer_id) {
    for (int i = 0; i < LUA_TIMER_COUNT; i++){
        // LLOGD("luat_timer_get timers[%d]:%p,timers[%d]->id:%d", i,timers[i],i,timers[i]->id);
        if (timers[i] && timers[i]->id == timer_id) {
            return timers[i];
        }
    }
    return NULL;
}


LUAT_WEAK int luat_timer_mdelay(size_t ms) {
    if (ms > 0) {
        luat_rtos_task_sleep(ms);
    }
    return 0;
}


/*msgbus*/
#ifndef LUA_QUEUE_COUNT
#define LUA_QUEUE_COUNT     256
#endif
static luat_rtos_queue_t lua_queue_handle;
LUAT_WEAK void luat_msgbus_init(void) {
    luat_rtos_queue_create(&lua_queue_handle, LUA_QUEUE_COUNT,  sizeof(rtos_msg_t));
}

LUAT_WEAK uint32_t luat_msgbus_put(rtos_msg_t* msg, size_t timeout) {
    return luat_rtos_queue_send(lua_queue_handle, msg, 0, timeout);
}

LUAT_WEAK uint32_t luat_msgbus_get(rtos_msg_t* msg, size_t timeout) {
    return luat_rtos_queue_recv(lua_queue_handle, msg, 0, timeout);
}

LUAT_WEAK uint32_t luat_msgbus_freesize(void) {
    uint32_t item_cnt;
    luat_rtos_queue_get_cnt(lua_queue_handle, &item_cnt);
    return LUA_QUEUE_COUNT - item_cnt;
}

LUAT_WEAK uint8_t luat_msgbus_is_empty(void) {
    uint32_t item_cnt;
    luat_rtos_queue_get_cnt(lua_queue_handle, &item_cnt);
    return !item_cnt;
}


#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_msgbus.h"
#include "cmsis_os2.h"
#include "FreeRTOS.h"
#include "task.h"

#define LUAT_LOG_TAG "timer"
#include "luat_log.h"

#define FREERTOS_TIMER_COUNT 32
static luat_timer_t* timers[FREERTOS_TIMER_COUNT] = {0};

static void luat_timer_callback(void* param) {
    //LLOGD("timer callback");
    rtos_msg_t msg;
    luat_timer_t *timer = (luat_timer_t*)param;
    msg.handler = timer->func;
    msg.ptr = param;
    msg.arg1 = 0;
    msg.arg2 = 0;
    int re = luat_msgbus_put(&msg, 1);
    //LLOGD("timer msgbus re=%ld", re);
}

static int nextTimerSlot() {
    for (size_t i = 0; i < FREERTOS_TIMER_COUNT; i++)
    {
        if (timers[i] == NULL) {
            return i;
        }
    }
    return -1;
}

int luat_timer_start(luat_timer_t* timer) {
    osTimerId_t os_timer;
    int timerIndex;
    //LLOGD(">>luat_timer_start timeout=%ld", timer->timeout);
    timerIndex = nextTimerSlot();
    //LLOGD("timer id=%ld", timerIndex);
    if (timerIndex < 0) {
        return 1; // too many timer!!
    }
    os_timer = osTimerNew(luat_timer_callback, timer->repeat ? osTimerPeriodic : osTimerOnce, timer, NULL);
    //LLOGD("timer id=%ld, osTimerNew=%08X", timerIndex, (int)timer);
    if (!os_timer) {
        return NULL;
    }
    timers[timerIndex] = timer;
    
    timer->os_timer = os_timer;
    int re = osTimerStart(os_timer, timer->timeout);
    //LLOGD("timer id=%ld timeout=%ld start=%ld", timerIndex, timer->timeout, re);
    if (re != 0) {
        osTimerDelete(os_timer);
        timers[timerIndex] = 0;
    }
    return re;
}

int luat_timer_stop(luat_timer_t* timer) {
    if (!timer)
        return 1;
    for (size_t i = 0; i < FREERTOS_TIMER_COUNT; i++)
    {
        if (timers[i] == timer) {
            timers[i] = NULL;
            break;
        }
    }
    osTimerStop(timer->os_timer);
    osTimerDelete(timer->os_timer);
    return 0;
};

luat_timer_t* luat_timer_get(size_t timer_id) {
    for (size_t i = 0; i < FREERTOS_TIMER_COUNT; i++)
    {
        if (timers[i] && timers[i]->id == timer_id) {
            return timers[i];
        }
    }
    return NULL;
}


int luat_timer_mdelay(size_t ms) {
    if (ms > 0) {
        vTaskDelay(ms);
    }
    return 0;
}


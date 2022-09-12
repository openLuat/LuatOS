
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_msgbus.h"


#define LUAT_LOG_TAG "timer"
#include "luat_log.h"

#include <time.h>
#include <math.h>
#include <unistd.h>

#define TIMER_COUNT 32
typedef struct sysp_timer {
    luat_timer_t* timer;
    uint32_t starttime;
    uint32_t nexttime;
} sysp_timer_t;
static sysp_timer_t timers[TIMER_COUNT] = {0};

// 获取当前时间
uint32_t get_timestamp(void) {
    struct timespec _t;
    clock_gettime(CLOCK_REALTIME, &_t);
    uint32_t timenow = _t.tv_sec*1000 + lround(_t.tv_nsec/1e6);
    //printf("time now > %u\n", timenow);
    return timenow;
}

void luat_timer_check(void) {
    //LLOGD("timer callback");
    uint32_t timenow = get_timestamp();
    rtos_msg_t msg;
    for (size_t i = 0; i < TIMER_COUNT; i++)
    {
        if (timers[i].timer == NULL) continue;
        //LLOGD("%d %d\n", timers[i].nexttime, timenow);
        if (timers[i].nexttime < timenow) {
            luat_timer_t *timer = timers[i].timer;
            msg.handler = timer->func;
            msg.ptr = NULL;
            msg.arg1 = timer->id;
            msg.arg2 = 0;
            luat_msgbus_put(&msg, 0);
            if (timer->repeat) {
                timers[i].nexttime += timer->timeout;
            }
            else {
                timers[i].nexttime = 0;
            }
        }
    }
    //LLOGD("end of luat_timer_check\n");
}

static int nextTimerSlot() {
    for (size_t i = 0; i < TIMER_COUNT; i++)
    {
        if (timers[i].timer == NULL) {
            return i;
        }
    }
    return -1;
}

int luat_timer_start(luat_timer_t* timer) {
    int os_timer;
    int timerIndex;
    //LLOGD(">>luat_timer_start timeout=%ld", timer->timeout);
    timerIndex = nextTimerSlot();
    //LLOGD("timer id=%ld", timerIndex);
    if (timerIndex < 0) {
        return 1; // too many timer!!
    }
    os_timer = timerIndex;
    //LLOGD("timer id=%ld, osTimerNew=%p", timerIndex, os_timer);
    timers[timerIndex].timer = timer;
    timers[timerIndex].starttime = get_timestamp();
    timers[timerIndex].nexttime = timers[timerIndex].starttime + timer->timeout;
    
    //timer->os_timer = os_timer;
    return 0;
}

int luat_timer_stop(luat_timer_t* timer) {
    if (!timer)
        return 1;
    for (size_t i = 0; i < TIMER_COUNT; i++)
    {
        if (timers[i].timer == timer) {
            timers[i].timer = NULL;
            break;
        }
    }
    return 0;
};

luat_timer_t* luat_timer_get(size_t timer_id) {
    for (size_t i = 0; i < TIMER_COUNT; i++)
    {
        if (timers[i].timer && timers[i].timer->id == timer_id) {
            return timers[i].timer;
        }
    }
    return NULL;
}


int luat_timer_mdelay(size_t ms) {
    if (ms > 0)
        usleep(ms*1000);
    return 0;
}



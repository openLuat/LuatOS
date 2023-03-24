/**
 * @file luat_timer_emulator.c
 * @author wendal (wendal1985@gamil.com)
 * @brief 基于win32的timer实现
 * @version 0.1
 * @date 2022-03-27
 * 
 * @copyright Copyright (c) 2022 OpenLuat & AirM2M
 * 
 */
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_msgbus.h"

#include "windows.h"
#include <io.h>

#define LUAT_LOG_TAG "timer"
#include "luat_log.h"

#define WIN32_TIMER_COUNT 64

static luat_timer_t* timers[WIN32_TIMER_COUNT] = {0};

void CALLBACK TimeProc( 
    HWND hwnd,       
    UINT message,     
    UINT idTimer,     
    DWORD dwTime) {
    rtos_msg_t msg;
    msg.arg1 = 0;
    msg.arg2 = 0;

    // LLOGD("timer callback");

    for (size_t i = 0; i < WIN32_TIMER_COUNT; i++)
    {
        if (timers[i] && (UINT_PTR)(timers[i]->os_timer) == idTimer) {
            msg.handler = timers[i]->func;
            msg.ptr = timers[i];
            msg.arg1 = timers[i]->id;
            luat_msgbus_put(&msg, 0);
            // LLOGD("timer msgbus index=%ld", i);
        }
    }
    
}

static int nextTimerSlot() {
    for (size_t i = 0; i < WIN32_TIMER_COUNT; i++)
    {
        if (timers[i] == NULL) {
            return i;
        }
    }
    return -1;
}

int luat_timer_start(luat_timer_t* timer) {
    int timerIndex;
    //LLOGD(">>luat_timer_start timeout=%ld", timer->timeout);
    timerIndex = nextTimerSlot();
    if (timerIndex < 0) {
        LLOGE("too many timers");
        return 1; // too many timer!!
    }
    UINT_PTR timer_id = SetTimer(NULL, 0, timer->timeout,TimeProc);
    timer->os_timer = (void*)timer_id;
    timers[timerIndex] = timer;
    return 0;
}

int luat_timer_stop(luat_timer_t* timer) {
    for (size_t i = 0; i < WIN32_TIMER_COUNT; i++)
    {
        if (timers[i] && timers[i] == timer) {
            timers[i] = NULL;
            KillTimer(NULL, (UINT_PTR)timer->os_timer);
        }
    }
    
    return 0;
};

luat_timer_t* luat_timer_get(size_t timer_id) {
    for (size_t i = 0; i < WIN32_TIMER_COUNT; i++)
    {
        if (timers[i] && timers[i]->id == timer_id) {
            return timers[i];
        }
    }
    return NULL;
}


int luat_timer_mdelay(size_t ms) {
    if (ms > 0) {
        Sleep(1000);
    }
    return 0;
}

static void usleep(unsigned long usec)
{
    HANDLE timer;
    LARGE_INTEGER interval;
    interval.QuadPart = -(10 * usec);

    timer = CreateWaitableTimer(NULL, TRUE, NULL);
    SetWaitableTimer(timer, &interval, 0, NULL, NULL, 0);
    WaitForSingleObject(timer, INFINITE);
    CloseHandle(timer);
}

void luat_timer_us_delay(size_t us) {
    if (us)
        usleep(us);
}

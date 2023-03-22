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

#include "SDL.h"

#define LUAT_LOG_TAG "timer"
#include "luat_log.h"

#define WIN32_TIMER_COUNT 64

static luat_timer_t* timers[WIN32_TIMER_COUNT] = {0};


static uint32_t luat_timer_callback(uint32_t interval, void *param) {
    // LLOGD("timer callback");
    rtos_msg_t msg;
    int timerIndex = (int)param;
    // size_t timer_id = (size_t)pvTimerGetTimerID(xTimer);
    // luat_timer_t *timer = luat_timer_get(timer_id);
    luat_timer_t *timer = timers[timerIndex];
    // LLOGD("timer 2 id:%d repeat:%d os_timer:%d interval:%d\n",timer->id,timer->repeat,timer->os_timer,interval);
    if (timer == NULL)
        return -1;
    msg.handler = timer->func;
    msg.ptr = timer;
    msg.arg1 = timer->id;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
    // if (timer->repeat == 0){
    //     LLOGD("------------------------");
    //     SDL_RemoveTimer((SDL_TimerID)timer->os_timer);
    //     // luat_timer_stop(timer);
    // }
    SDL_RemoveTimer((SDL_TimerID)timer->os_timer);
    if (timer->repeat != 0){
        SDL_TimerID timer_id = SDL_AddTimer(timer->timeout,luat_timer_callback,(void *)timerIndex);
        timer->os_timer = (void*)timer_id;
    }
    
    // int re = luat_msgbus_put(&msg, 0);
    //LLOGD("timer msgbus re=%ld", re);
    return 0;
}

// void CALLBACK TimeProc( 
//     HWND hwnd,       
//     UINT message,     
//     UINT idTimer,     
//     DWORD dwTime) {
//     rtos_msg_t msg;
//     msg.arg1 = 0;
//     msg.arg2 = 0;
//     // LLOGD("timer callback");
//     for (size_t i = 0; i < WIN32_TIMER_COUNT; i++)
//     {
//         if (timers[i] && (UINT_PTR)(timers[i]->os_timer) == idTimer) {
//             msg.handler = timers[i]->func;
//             msg.ptr = timers[i];
//             msg.arg1 = timers[i]->id;
//             luat_msgbus_put(&msg, 0);
//             // LLOGD("timer msgbus index=%ld", i);
//         }
//     }
// }

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
    // LLOGD(">>luat_timer_start timeout=%ld", timer->timeout);
    timerIndex = nextTimerSlot();
    if (timerIndex < 0) {
        LLOGE("too many timers");
        return -1; // too many timer!!
    }

    SDL_TimerID timer_id = SDL_AddTimer(timer->timeout,luat_timer_callback,(void *)timerIndex);
    timer->os_timer = (void*)timer_id;
    // LLOGD("timer 1 id:%d repeat:%d os_timer:%d \n",timer->id,timer->repeat,timer->os_timer);
    timers[timerIndex] = timer;
    return 0;
}

int luat_timer_stop(luat_timer_t* timer) {
    for (size_t i = 0; i < WIN32_TIMER_COUNT; i++){
        if (timers[i] && timers[i] == timer) {
            timers[i] = NULL;
            LLOGD("luat_timer_stop os_timer:%d \n",timer->os_timer);
            // SDL_RemoveTimer((SDL_TimerID) timer->os_timer);
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
    SDL_Delay(ms);
    // if (ms > 0) {
    //     Sleep(1000);
    // }
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

#include <time.h>
#include <math.h>

// 获取当前时间
uint32_t get_timestamp(void) {
    // struct timespec _t;
    // clock_gettime(CLOCK_REALTIME, &_t);
    // uint32_t timenow = _t.tv_sec*1000 + lround(_t.tv_nsec/1e6);
    // //printf("time now > %u\n", timenow);
    LARGE_INTEGER ticks;
    QueryPerformanceCounter(&ticks);
    return ticks.QuadPart;
}


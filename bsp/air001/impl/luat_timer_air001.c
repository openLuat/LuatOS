
#include "luat_base.h"
#include "luat_timer.h"

#define LUAT_LOG_TAG "luat.timer"
#include "luat_log.h"

#include <pthread.h>
#include <errno.h>
#include <unistd.h>
#include <sys/time.h>

#define TIMER_COUNT 1024
typedef struct luat_timer_ext
{
    luat_timer_t timer;
    struct timeval tv;
}luat_timer_ext_t;

static luat_timer_ext_t     timers[TIMER_COUNT] = {0};

static pthread_cond_t       timer_cnd;
static pthread_mutex_t      timer_mutex;
static pthread_t            timer_pid;

void* timer_pthread(void* params) {
    LLOGD("timer thread by pthread");
    struct timeval tv;
    while (1) {
        pthread_mutex_lock(&timer_mutex);
        gettimeofday(&tv,NULL);
        long long tnow = tv.tv_sec * 1000LL + tv.tv_usec / 1000;
        long long minsleep = 60*1000;
        for (size_t i = 0; i < TIMER_COUNT; i++)
        {
            if (timers[i].tv.tv_sec != 0) {
                long long ctime = timers[i].tv.tv_sec * 1000LL + timers[i].tv.tv_usec / 1000;
                if (timers[i].timer.repeat > 0) {
                    timers[i].timer.repeat --;
                }
                long long diff = tnow - ctime;
                if (diff < timers[i].timer.timeout) {
                    // 触发timer事件

                    if (timers[i].timer.repeat == 0) {
                        timers[i].tv.tv_sec = 0; // 已经完成使命,将其删除
                    }
                    else {
                        memcpy(&(timers[i].tv), &tv, sizeof(tv));
                    }
                }
                else if (diff < minsleep) {
                    minsleep = diff;
                }
            }
        }
        pthread_mutex_unlock(&timer_mutex);
        struct timespec ts;
        ts.tv_sec = tv.tv_sec + minsleep/1000;
        ts.tv_nsec = tv.tv_usec += (minsleep % 1000) * 1000;
        pthread_cond_timedwait(&timer_cnd, &timer_mutex, &ts);
    }

    return NULL;
}

int luat_timer_init(void) {
    pthread_mutex_init(&timer_mutex, NULL);
    pthread_cond_init(&timer_cnd, NULL);

    // 启动 timer线程

    pthread_create(&timer_pid, NULL, timer_pthread, NULL);
}

int luat_timer_start(luat_timer_t* timer) {
    pthread_mutex_lock(&timer_mutex);
    int flag = 1;
    for (size_t i = 0; i < TIMER_COUNT; i++)
    {
        if (timers[i].tv.tv_sec == 0) {
            memcpy(&(timers[i].timer), timer, sizeof(luat_timer_t));
            gettimeofday(&(timers[i].tv),NULL);
            flag = 0;
        }
    }
    pthread_mutex_unlock(&timer_mutex);

    if (flag) {
        LLOGE("too many timer!!!");
        return 1;
    }

    // 通知timer线程, 重新计算休眠时间
    pthread_cond_broadcast(&timer_cnd);

    return 0;
}

int luat_timer_stop(luat_timer_t* timer) {
    pthread_mutex_lock(&timer_mutex);
    for (size_t i = 0; i < TIMER_COUNT; i++)
    {
        if (timers[i].timer.id == timer->id && timers[i].tv.tv_sec) {
            timers[i].tv.tv_sec = 0;
            break;
        }
    }

    pthread_mutex_unlock(&timer_mutex);

    // 通知timer线程, 重新计算休眠时间
    pthread_cond_broadcast(&timer_cnd);

    return 0;
}

luat_timer_t* luat_timer_get(size_t timer_id) {

    pthread_mutex_lock(&timer_mutex);
    for (size_t i = 0; i < TIMER_COUNT; i++)
    {
        if (timers[i].timer.id == timer_id && timers[i].tv.tv_sec) {
            return &(timers[i].timer);
        }
    }

    pthread_mutex_unlock(&timer_mutex);
    
    return NULL;
}


int luat_timer_mdelay(size_t ms) {
    while (ms > 0) {
        if (ms >= 1000) {
            ms -= 1000;
            sleep(1);
        }
        else if (ms > 100) {
            ms -= 100;
            usleep(100*1000);
        }
        else {
            usleep(ms * 1000);
            break;
        }
    }
    return 0;
}
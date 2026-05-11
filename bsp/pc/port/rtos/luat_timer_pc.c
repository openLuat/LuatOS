
#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_timer.h"
#include "luat_pcconf.h"

#include "luat_posix_compat.h"
#include "luat_timer_engine.h"

#define LUAT_LOG_TAG "timer"
#include "luat_log.h"

#define TIMER_ID_MAX (1024)

typedef struct {
    luat_timer_handle_t  handle;
    luat_timer_t        *timer;
} pc_timer_slot_t;

static pc_timer_slot_t timers[TIMER_ID_MAX];
static pthread_mutex_t timer_lock = PTHREAD_MUTEX_INITIALIZER;

static int get_free_slot(void) {
    for (int i = 0; i < TIMER_ID_MAX; i++) {
        if (timers[i].handle == NULL)
            return i;
    }
    return -1;
}

static pc_timer_slot_t *get_slot_by_timer_id(size_t id) {
    for (int i = 0; i < TIMER_ID_MAX; i++) {
        if (timers[i].timer != NULL && timers[i].timer->id == id)
            return &timers[i];
    }
    return NULL;
}

int luat_timer_mdelay(size_t ms) {
    if (ms) luat_sleep_ms((uint32_t)ms);
    return 0;
}

static void timer_cb(void *p) {
    luat_timer_t *timer = (luat_timer_t *)p;

    pthread_mutex_lock(&timer_lock);
    pc_timer_slot_t *slot = get_slot_by_timer_id(timer->id);
    if (slot == NULL) {
        pthread_mutex_unlock(&timer_lock);
        LLOGE("no such timer %zu", timer->id);
        return;
    }

    if (timer->repeat > 0) {
        timer->repeat--;
        luat_timer_engine_start(slot->handle, (uint32_t)timer->timeout, 0);
    } else if (timer->repeat == -1) {
        luat_timer_engine_start(slot->handle, (uint32_t)timer->timeout, 0);
    }
    pthread_mutex_unlock(&timer_lock);

    rtos_msg_t msg;
    msg.handler = timer->func;
    msg.ptr  = NULL;
    msg.arg1 = timer->id;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
}

int luat_timer_start(luat_timer_t *timer) {
    pthread_mutex_lock(&timer_lock);
    int slot_id = get_free_slot();
    if (slot_id < 0) {
        LLOGE("too many timers created");
        pthread_mutex_unlock(&timer_lock);
        return -1;
    }

    luat_timer_handle_t h = luat_timer_engine_create(timer_cb, timer);
    if (h == NULL) {
        pthread_mutex_unlock(&timer_lock);
        return -1;
    }

    timers[slot_id].handle = h;
    timers[slot_id].timer  = timer;
    timer->os_timer = (void *)(intptr_t)slot_id;

    int ret = luat_timer_engine_start(h, (uint32_t)timer->timeout, 0);
    if (ret) LLOGE("timer_engine_start failed %d", ret);
    pthread_mutex_unlock(&timer_lock);
    return ret;
}

int luat_timer_stop(luat_timer_t *timer) {
    pthread_mutex_lock(&timer_lock);
    int slot_id = (int)(intptr_t)timer->os_timer;
    if (slot_id < 0 || slot_id >= TIMER_ID_MAX || timers[slot_id].handle == NULL) {
        /* Try linear search as fallback */
        pc_timer_slot_t *slot = get_slot_by_timer_id(timer->id);
        if (slot == NULL) {
            pthread_mutex_unlock(&timer_lock);
            return -1;
        }
        slot_id = (int)(slot - timers);
    }
    luat_timer_engine_delete(timers[slot_id].handle);
    timers[slot_id].handle = NULL;
    timers[slot_id].timer  = NULL;
    pthread_mutex_unlock(&timer_lock);
    return 0;
}

luat_timer_t *luat_timer_get(size_t timer_id) {
    pthread_mutex_lock(&timer_lock);
    pc_timer_slot_t *slot = get_slot_by_timer_id(timer_id);
    luat_timer_t *t = slot ? slot->timer : NULL;
    pthread_mutex_unlock(&timer_lock);
    return t;
}

void luat_timer_us_delay(size_t us) {
    (void)us;
}

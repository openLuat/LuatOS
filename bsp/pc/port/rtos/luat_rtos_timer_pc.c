#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_pcconf.h"

#include "luat_posix_compat.h"
#include "luat_timer_engine.h"

#define LUAT_LOG_TAG "rtos.timer"
#include "luat_log.h"

typedef struct timer_data {
    void       *cb;
    void       *param;
    void       *task_handle;
    int         is_repeat;
    uint32_t    timeout_ms;
    luat_timer_handle_t handle;
} timer_data_t;

typedef void (*tcb)(void*);

static void timer_engine_cb(void *p) {
    timer_data_t *data = (timer_data_t *)p;
    if (data->cb)
        ((tcb)data->cb)(data->param);
    if (data->is_repeat) {
        luat_timer_engine_start(data->handle, data->timeout_ms, 0);
    }
}

void *luat_create_rtos_timer(void *cb, void *param, void *task_handle) {
    timer_data_t *data = luat_heap_malloc(sizeof(timer_data_t));
    if (data == NULL) return NULL;
    memset(data, 0, sizeof(timer_data_t));
    data->cb           = cb;
    data->param        = param;
    data->task_handle  = task_handle;
    luat_timer_handle_t h = luat_timer_engine_create(timer_engine_cb, data);
    if (h == NULL) {
        luat_heap_free(data);
        return NULL;
    }
    data->handle = h;
    return data;
}

int luat_start_rtos_timer(void *timer, uint32_t ms, uint8_t is_repeat) {
    if (timer == NULL) return -1;
    timer_data_t *data = (timer_data_t *)timer;
    data->is_repeat   = is_repeat;
    data->timeout_ms  = ms;
    return luat_timer_engine_start(data->handle, ms, 0);
}

void luat_stop_rtos_timer(void *timer) {
    if (timer == NULL) return;
    timer_data_t *data = (timer_data_t *)timer;
    luat_timer_engine_stop(data->handle);
}

void luat_release_rtos_timer(void *timer) {
    if (timer == NULL) return;
    timer_data_t *data = (timer_data_t *)timer;
    luat_timer_engine_delete(data->handle);
    luat_heap_free(data);
}

void luat_task_suspend_all(void) {}
void luat_task_resume_all(void) {}

int luat_rtos_timer_create(luat_rtos_timer_t *timer_handle) {
    if (!timer_handle) return -1;
    *timer_handle = luat_create_rtos_timer(NULL, NULL, NULL);
    return (*timer_handle) ? 0 : -1;
}

int luat_rtos_timer_delete(luat_rtos_timer_t timer_handle) {
    if (!timer_handle) return -1;
    luat_release_rtos_timer(timer_handle);
    return 0;
}

int luat_rtos_timer_start(luat_rtos_timer_t timer_handle, uint32_t timeout, uint8_t repeat, luat_rtos_timer_callback_t callback_fun, void *user_param) {
    if (!timer_handle) return -1;
    timer_data_t *data = (timer_data_t *)timer_handle;
    data->is_repeat   = repeat;
    data->timeout_ms  = timeout;
    data->cb          = callback_fun;
    data->param       = user_param;
    return luat_timer_engine_start(data->handle, timeout, 0);
}

int luat_rtos_timer_stop(luat_rtos_timer_t timer_handle) {
    if (!timer_handle) return -1;
    luat_stop_rtos_timer(timer_handle);
    return 0;
}

void luat_rtos_task_sleep(uint32_t ms) {
    if (ms > 0) luat_sleep_ms(ms);
}

int luat_rtos_timer_is_active(luat_rtos_timer_t timer_handle) {
    if (!timer_handle) return -1;
    timer_data_t *data = (timer_data_t *)timer_handle;
    return luat_timer_engine_is_active(data->handle);
}

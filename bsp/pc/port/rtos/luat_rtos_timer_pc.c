#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"
#include "luat_pcconf.h"

#include "uv.h"

#define LUAT_LOG_TAG "rtos.timer"
#include "luat_log.h"


typedef struct timer_data
{
    void *cb;
    void *param;
    void *task_handle;
    int is_repeat;
    size_t timeout;
}timer_data_t;

typedef void (*tcb)(void*);

extern uv_loop_t *main_loop;
extern uv_mutex_t timer_lock;

static void timer_cb(uv_timer_t *handle) {
    timer_data_t* data = (timer_data_t*)handle->data;
    if (data->cb)
        ((tcb)data->cb)(data->param);
    if (data->is_repeat) {
        uv_timer_start(handle, timer_cb, data->timeout, 0);
    }
}

// Timer类
void *luat_create_rtos_timer(void *cb, void *param, void *task_handle) {
    uv_mutex_lock(&timer_lock);
    uv_timer_t *t = luat_heap_malloc(sizeof(uv_timer_t));
    if (t == NULL) {
        uv_mutex_unlock(&timer_lock);
        return NULL;
    }
    memset(t, 0, sizeof(uv_timer_t));
    uv_timer_init(main_loop, t);
    timer_data_t *data = luat_heap_malloc(sizeof(timer_data_t));
    if (data == NULL) {
        uv_mutex_unlock(&timer_lock);
        luat_heap_free(t);
        return NULL;
    }
    memset(data, 0, sizeof(timer_data_t));
    t->data = data;
    data->cb = cb;
    data->param = param;
    data->task_handle = task_handle;
    // LLOGD("创建rtos timer %p", t);
    uv_mutex_unlock(&timer_lock);
    return t;
}

int luat_start_rtos_timer(void *timer, uint32_t ms, uint8_t is_repeat) {
    int ret = 0;
    uv_mutex_lock(&timer_lock);
    uv_timer_t *t = (uv_timer_t *)timer;
    // LLOGD("启动rtos timer %p", t, ms, is_repeat);
    ((timer_data_t*)t->data)->is_repeat = is_repeat;
    ((timer_data_t*)t->data)->timeout = ms;
    ret = uv_timer_start(t, timer_cb, ms, 0);
    uv_mutex_unlock(&timer_lock);
    return ret;
}

void luat_stop_rtos_timer(void *timer) {
    uv_mutex_lock(&timer_lock);
    uv_timer_t *t = (uv_timer_t *)timer;
    uv_timer_stop(t);
    uv_mutex_unlock(&timer_lock);
}

void luat_release_rtos_timer(void *timer) {
    uv_mutex_lock(&timer_lock);
    uv_timer_t *t = (uv_timer_t *)timer;
    uv_timer_stop(t);
    luat_heap_free(t->data);
    free_uv_handle(t);
    uv_mutex_unlock(&timer_lock);
}


void luat_task_suspend_all(void) {
    // nop
}

void luat_task_resume_all(void) {
    // nop
}

int luat_rtos_timer_create(luat_rtos_timer_t *timer_handle)
{
	if (!timer_handle) return -1;
	*timer_handle = luat_create_rtos_timer(NULL, NULL, NULL);
	return (*timer_handle)?0:-1;
}

int luat_rtos_timer_delete(luat_rtos_timer_t timer_handle)
{
	if (!timer_handle) return -1;
	luat_release_rtos_timer(timer_handle);
	return 0;
}

int luat_rtos_timer_start(luat_rtos_timer_t timer_handle, uint32_t timeout, uint8_t repeat, luat_rtos_timer_callback_t callback_fun, void *user_param)
{
    int ret = 0;
	if (!timer_handle) {
        return -1;
    }
    uv_mutex_lock(&timer_lock);
	uv_timer_t *t = (uv_timer_t *)timer_handle;
    ((timer_data_t*)t->data)->is_repeat = repeat;
    ((timer_data_t*)t->data)->timeout = timeout;
    ((timer_data_t*)t->data)->cb = callback_fun;
    ((timer_data_t*)t->data)->param = user_param;
    ret = uv_timer_start(t, timer_cb, timeout, 0);
    uv_mutex_unlock(&timer_lock);
    return ret;
}

int luat_rtos_timer_stop(luat_rtos_timer_t timer_handle)
{
	if (!timer_handle) return -1;
	luat_stop_rtos_timer(timer_handle);
	return 0;
}



void luat_rtos_task_sleep(uint32_t ms) {
    if (ms > 0) {
        uv_sleep(ms);
    }
}

int luat_rtos_timer_is_active(luat_rtos_timer_t timer_handle) {

    int ret = 0;
	if (!timer_handle) {
        return -1;
    }
	uv_timer_t *t = (uv_timer_t *)timer_handle;
    if (uv_timer_get_due_in(t) > 0) {
        return 1;
    }
    return 0;
}

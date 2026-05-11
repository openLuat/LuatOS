#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"

#include "luat_posix_compat.h"
#include "c_common.h"

#define LUAT_LOG_TAG "rtos.task"
#include "luat_log.h"
#include "luat_queue_pc.h"

typedef struct utask
{
    pthread_t          t;
    uv_queue_item_t    q;
    pthread_mutex_t    m;
    pthread_cond_t     cv;
    luat_rtos_task_entry task_fun;
    void*              user_data;
    uint16_t           event_cout;
} utask_t;

#ifdef _MSC_VER
  static __declspec(thread) utask_t* g_current_task = NULL;
#else
  static __thread utask_t* g_current_task = NULL;
#endif



LUAT_RET luat_send_event_to_task(void *task_handle, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3) {
    return luat_rtos_event_send(task_handle, id, param1, param2, param3, 0);
}

LUAT_RET luat_wait_event_from_task(void *task_handle, uint32_t wait_event_id, luat_event_t *out_event, void *call_back, uint32_t ms) {
    return luat_rtos_event_recv(task_handle, wait_event_id, out_event, call_back, ms);
}

void *luat_get_current_task(void) {
    return g_current_task;
}

luat_rtos_task_handle luat_rtos_get_current_handle(void) {
    return luat_get_current_task();
}

static void *rtos_task(void* args) {
    utask_t* task = (utask_t*)args;
    g_current_task = task;
    task->task_fun(task->user_data);
    g_current_task = NULL;
    return NULL;
}

int luat_rtos_task_create(luat_rtos_task_handle *task_handle, uint32_t stack_size, uint8_t priority, const char *task_name, luat_rtos_task_entry task_fun, void* user_data, uint16_t event_cout) {
    (void)stack_size; (void)priority; (void)task_name;
    utask_t* task = luat_heap_malloc(sizeof(utask_t));
    if (task == NULL) {
        return -1;
    }
    memset(task, 0, sizeof(utask_t));
    task->event_cout = event_cout;
    task->user_data  = user_data;
    task->task_fun   = task_fun;
    pthread_mutex_init(&task->m, NULL);
    pthread_cond_init(&task->cv, NULL);
    int ret = pthread_create(&task->t, NULL, rtos_task, task);
    if (ret) {
        LLOGE("pthread_create failed %d", ret);
        pthread_mutex_destroy(&task->m);
        pthread_cond_destroy(&task->cv);
        luat_heap_free(task);
        return ret;
    }
    pthread_detach(task->t);
    *task_handle = task;
    return 0;
}

int luat_rtos_task_delete(luat_rtos_task_handle task_handle) {
    utask_t* task = (utask_t*)task_handle;
    if (task == NULL) return -1;
    pthread_mutex_destroy(&task->m);
    pthread_cond_destroy(&task->cv);
    luat_heap_free(task);
    return 0;
}

int luat_rtos_event_send(luat_rtos_task_handle task_handle, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3, uint32_t timeout) {
    (void)timeout;
    if (task_handle == NULL) {
        LLOGE("task_handle is NULL");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;
    luat_event_t e = {0};
    e.id     = id;
    e.param1 = param1;
    e.param2 = param2;
    e.param3 = param3;
    uv_queue_item_t* item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(luat_event_t));
    if (item == NULL) return -1;
    memset(item, 0, sizeof(uv_queue_item_t));
    memcpy(item->msg, &e, sizeof(luat_event_t));
    item->size = sizeof(luat_event_t);
    pthread_mutex_lock(&task->m);
    int ret = luat_queue_push(&task->q, item);
    pthread_cond_signal(&task->cv);
    pthread_mutex_unlock(&task->m);
    return ret;
}

int luat_rtos_event_recv(luat_rtos_task_handle task_handle, uint32_t wait_event_id, luat_event_t *out_event, luat_rtos_event_wait_callback_t *callback_fun, uint32_t timeout) {
    if (task_handle == NULL) {
        LLOGE("task_handle is NULL");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;
    uv_queue_item_t* item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(luat_event_t));
    if (item == NULL) return -1;
    int ret = 0;

    pthread_mutex_lock(&task->m);
    while (1) {
        ret = luat_queue_pop(&task->q, item);
        if (ret == 0) {
            memcpy(out_event, item->msg, sizeof(luat_event_t));
            if ((wait_event_id == CORE_EVENT_ID_ANY) || (out_event->id == wait_event_id)) {
                pthread_mutex_unlock(&task->m);
                luat_heap_free(item);
                return 0;
            }
            if (callback_fun) {
                LLOGE("暂不支持callback_fun %p", callback_fun);
            }
            /* Not the event we want; continue waiting */
            continue;
        }

        if (timeout == 0) {
            pthread_mutex_unlock(&task->m);
            luat_heap_free(item);
            return 1;
        }

        if (timeout != (size_t)(-1)) {
            /* Timed wait: 1 ms at a time */
            struct timespec abs;
            luat_calc_abs_timeout(&abs, 1);
            int wret = pthread_cond_timedwait(&task->cv, &task->m, &abs);
            if (wret == ETIMEDOUT) {
                timeout = (timeout > 0) ? timeout - 1 : 0;
                if (timeout == 0) {
                    pthread_mutex_unlock(&task->m);
                    luat_heap_free(item);
                    return 1;
                }
            }
        } else {
            pthread_cond_wait(&task->cv, &task->m);
        }
    }
    pthread_mutex_unlock(&task->m);
    luat_heap_free(item);
    return -1;
}

typedef struct luat_message_item
{
    uint32_t id;
    void*    msg;
} luat_message_item_t;

int luat_rtos_message_send(luat_rtos_task_handle task_handle, uint32_t message_id, void *p_message) {
    if (task_handle == NULL) {
        LLOGE("task_handle is NULL");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;
    luat_message_item_t payload = {0};
    payload.id  = message_id;
    payload.msg = p_message;
    uv_queue_item_t* item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(luat_message_item_t));
    if (item == NULL) {
        LLOGE("out of memory when malloc message item");
        return -1;
    }
    memset(item, 0, sizeof(uv_queue_item_t));
    memcpy(item->msg, &payload, sizeof(luat_message_item_t));
    item->size = sizeof(luat_message_item_t);
    pthread_mutex_lock(&task->m);
    int ret = luat_queue_push(&task->q, item);
    pthread_cond_signal(&task->cv);
    pthread_mutex_unlock(&task->m);
    return ret;
}

int luat_rtos_message_recv(luat_rtos_task_handle task_handle, uint32_t *message_id, void **p_p_message, uint32_t timeout) {
    if (task_handle == NULL || message_id == NULL || p_p_message == NULL) {
        LLOGE("invalid args for message_recv");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;
    uv_queue_item_t* item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(luat_message_item_t));
    if (item == NULL) return -1;
    int ret = 0;

    pthread_mutex_lock(&task->m);
    while (1) {
        ret = luat_queue_pop(&task->q, item);
        if (ret == 0) {
            luat_message_item_t payload = {0};
            memcpy(&payload, item->msg, sizeof(luat_message_item_t));
            *message_id   = payload.id;
            *p_p_message  = payload.msg;
            pthread_mutex_unlock(&task->m);
            luat_heap_free(item);
            return 0;
        }
        if (timeout == 0) {
            pthread_mutex_unlock(&task->m);
            luat_heap_free(item);
            return 1;
        }
        if (timeout != (size_t)(-1)) {
            struct timespec abs;
            luat_calc_abs_timeout(&abs, 1);
            int wret = pthread_cond_timedwait(&task->cv, &task->m, &abs);
            if (wret == ETIMEDOUT) {
                timeout = (timeout > 0) ? timeout - 1 : 0;
                if (timeout == 0) {
                    pthread_mutex_unlock(&task->m);
                    luat_heap_free(item);
                    return 1;
                }
            }
        } else {
            pthread_cond_wait(&task->cv, &task->m);
        }
    }
    pthread_mutex_unlock(&task->m);
    luat_heap_free(item);
    return -1;
}

void luat_os_entry_cri(void) {}
void luat_os_exit_cri(void) {}

uint32_t luat_rtos_entry_critical(void) {
    return 0;
}

void luat_rtos_exit_critical(uint32_t critical) {
    (void)critical;
}

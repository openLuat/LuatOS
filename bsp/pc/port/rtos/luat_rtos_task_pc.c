#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_malloc.h"

#include "luat_posix_compat.h"
#include "c_common.h"

#define LUAT_LOG_TAG "rtos.task"
#include "luat_log.h"
#include "luat_queue_pc.h"

#include <stddef.h>   /* offsetof */

/* Forward declarations for the Windows crash-handler task registry */
#if defined(_WIN32) || defined(_WIN64)
extern void win32_task_register(const char* name);
extern void win32_task_unregister(void);
#else
static inline void win32_task_register(const char* n) { (void)n; }
static inline void win32_task_unregister(void) {}
#endif

/* 内部事件/消息载体: 自包含的单向链表节点 + 紧随其后的 payload.
 * 不再共用 uv_queue_item_t / sizeof+魔数 那一套, 避免跨平台 padding 风险. */
typedef struct utask_node {
    struct utask_node* next;
    uint32_t           payload_size;
    /* payload 紧跟在结构体之后 */
} utask_node_t;

#define UTASK_NODE_PAYLOAD(n) ((char*)(n) + sizeof(utask_node_t))

typedef struct utask
{
    pthread_t            t;
    int                  joinable;       /* 1 = pthread_create 成功且未 join */
    int                  exit_flag;      /* 1 = 请求线程退出 */
    utask_node_t*        q_head;
    utask_node_t*        q_tail;
    uint32_t             q_count;
    uint32_t             q_limit;        /* 0 = 不限制 */
    pthread_mutex_t      m;
    pthread_cond_t       cv;
    luat_rtos_task_entry task_fun;
    void*                user_data;
    uint16_t             event_cout;
    char                 task_name[64];
} utask_t;

#ifdef _MSC_VER
  static __declspec(thread) utask_t* g_current_task = NULL;
#else
  static __thread utask_t* g_current_task = NULL;
#endif

typedef struct luat_message_item
{
    uint32_t id;
    void*    msg;
} luat_message_item_t;

/* ---------------------- 内部队列辅助 (持锁调用) ---------------------- */
static void utask_q_push_locked(utask_t* task, utask_node_t* node) {
    node->next = NULL;
    if (task->q_tail) {
        task->q_tail->next = node;
        task->q_tail = node;
    } else {
        task->q_head = task->q_tail = node;
    }
    task->q_count++;
}

static utask_node_t* utask_q_pop_locked(utask_t* task) {
    utask_node_t* n = task->q_head;
    if (n == NULL) return NULL;
    task->q_head = n->next;
    if (task->q_head == NULL) task->q_tail = NULL;
    task->q_count--;
    return n;
}

static void utask_q_drain_locked(utask_t* task) {
    utask_node_t* n = task->q_head;
    while (n) {
        utask_node_t* nx = n->next;
        luat_heap_free(n);
        n = nx;
    }
    task->q_head = task->q_tail = NULL;
    task->q_count = 0;
}

/* ---------------------- legacy API ---------------------- */
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

/* ---------------------- 线程入口 ---------------------- */
static void *rtos_task(void* args) {
    utask_t* task = (utask_t*)args;
    g_current_task = task;
    win32_task_register(task->task_name);
    if (task->task_fun) task->task_fun(task->user_data);
    win32_task_unregister();
    /* 线程自己退出前清空残留事件队列, 避免 task_delete 已先发生时的内存泄漏.
     * 必须持锁: task_delete 可能并发设置 exit_flag. */
    pthread_mutex_lock(&task->m);
    utask_q_drain_locked(task);
    pthread_mutex_unlock(&task->m);
    g_current_task = NULL;
    return NULL;
}

/* ---------------------- 创建 ---------------------- */
int luat_rtos_task_create(luat_rtos_task_handle *task_handle, uint32_t stack_size, uint8_t priority,
                          const char *task_name, luat_rtos_task_entry task_fun, void* user_data, uint16_t event_cout) {
    (void)stack_size; (void)priority;
    if (task_handle == NULL) return -1;
    utask_t* task = luat_heap_malloc(sizeof(utask_t));
    if (task == NULL) {
        return -1;
    }
    memset(task, 0, sizeof(utask_t));
    task->event_cout = event_cout;
    task->q_limit    = event_cout; /* 0 = 不限 */
    task->user_data  = user_data;
    task->task_fun   = task_fun;
    strncpy(task->task_name, task_name ? task_name : "unnamed", sizeof(task->task_name) - 1);
    pthread_mutex_init(&task->m, NULL);
    pthread_cond_init(&task->cv, NULL);

    /* joinable 线程, task_delete 时可以 join 等待结束 */
    int ret = pthread_create(&task->t, NULL, rtos_task, task);
    if (ret) {
        LLOGE("pthread_create failed %d", ret);
        pthread_mutex_destroy(&task->m);
        pthread_cond_destroy(&task->cv);
        luat_heap_free(task);
        return ret;
    }
    task->joinable = 1;
    *task_handle = task;
    return 0;
}

/* ---------------------- 删除 ---------------------- */
int luat_rtos_task_delete(luat_rtos_task_handle task_handle) {
    utask_t* task = (utask_t*)task_handle;
    if (task == NULL) return -1;

    /* 标记退出 + 广播唤醒所有 recv */
    pthread_mutex_lock(&task->m);
    task->exit_flag = 1;
    pthread_cond_broadcast(&task->cv);
    if (task->joinable) {
        if (g_current_task != task) {
            pthread_detach(task->t);
        }
        task->joinable = 0;
    }
    pthread_mutex_unlock(&task->m);

    /* 不 destroy/free 任何资源: detach 的线程可能仍在跑, 访问 task->m / task->cv
     * 是未定义行为. 令 struct 泄露以避免 use-after-free.
     * PC 模拟器中任务极少被删除, 少量泄漏可接受. */
    return 0;
}

/* ---------------------- 发送事件 ---------------------- */
int luat_rtos_event_send(luat_rtos_task_handle task_handle, uint32_t id, uint32_t param1, uint32_t param2, uint32_t param3, uint32_t timeout) {
    (void)timeout;
    if (task_handle == NULL) {
        LLOGE("task_handle is NULL");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;

    utask_node_t* node = luat_heap_malloc(sizeof(utask_node_t) + sizeof(luat_event_t));
    if (node == NULL) return -1;
    node->next = NULL;
    node->payload_size = sizeof(luat_event_t);
    luat_event_t* ev = (luat_event_t*)UTASK_NODE_PAYLOAD(node);
    ev->id = id; ev->param1 = param1; ev->param2 = param2; ev->param3 = param3;

    pthread_mutex_lock(&task->m);
    if (task->exit_flag) {
        pthread_mutex_unlock(&task->m);
        luat_heap_free(node);
        return -1;
    }
    if (task->q_limit && task->q_count >= task->q_limit) {
        pthread_mutex_unlock(&task->m);
        luat_heap_free(node);
        LLOGE("task event queue full (limit=%u)", task->q_limit);
        return -1;
    }
    utask_q_push_locked(task, node);
    pthread_cond_signal(&task->cv);
    pthread_mutex_unlock(&task->m);
    return 0;
}

/* ---------------------- 接收事件 (一次性 absolute timeout) ---------------------- */
int luat_rtos_event_recv(luat_rtos_task_handle task_handle, uint32_t wait_event_id, luat_event_t *out_event, luat_rtos_event_wait_callback_t *callback_fun, uint32_t timeout) {
    if (task_handle == NULL || out_event == NULL) {
        LLOGE("invalid args for event_recv");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;

    const int forever = (timeout == LUAT_WAIT_FOREVER || timeout == (uint32_t)(-1));
    struct timespec abs;
    if (!forever && timeout > 0) {
        luat_calc_abs_timeout(&abs, timeout);
    }

    pthread_mutex_lock(&task->m);
    while (1) {
        if (task->exit_flag) {
            pthread_mutex_unlock(&task->m);
            return -1;
        }
        utask_node_t* node = utask_q_pop_locked(task);
        if (node) {
            luat_event_t ev = *(luat_event_t*)UTASK_NODE_PAYLOAD(node);
            luat_heap_free(node);
            if (wait_event_id == CORE_EVENT_ID_ANY || ev.id == wait_event_id) {
                *out_event = ev;
                pthread_mutex_unlock(&task->m);
                return 0;
            }
            if (callback_fun) {
                /* 让回调在锁外执行, 避免回调里再调 event API 产生递归.
                 * 与 FreeRTOS 实现保持一致: callback 实际签名是
                 * CBFuncEx_t = int32_t(*)(void *pData, void *pParam),
                 * 第一个参数传 event 指针, 第二个参数传 task_handle.
                 * 头文件签名 luat_rtos_event_wait_callback_t* 是历史遗留, 实际
                 * 调用约定按 CBFuncEx_t 走. */
                typedef int32_t (*cb_ex_t)(void *pData, void *pParam);
                cb_ex_t cb = (cb_ex_t)(void*)callback_fun;
                pthread_mutex_unlock(&task->m);
                cb(&ev, task);
                pthread_mutex_lock(&task->m);
            }
            continue; /* 不是我们等的 event, 继续尝试下一条 */
        }
        if (timeout == 0) {
            pthread_mutex_unlock(&task->m);
            return 1;
        }
        if (forever) {
            pthread_cond_wait(&task->cv, &task->m);
        } else {
            int wret = pthread_cond_timedwait(&task->cv, &task->m, &abs);
            if (wret == ETIMEDOUT) {
                pthread_mutex_unlock(&task->m);
                return 1;
            }
        }
    }
}

/* ---------------------- 发送消息 ---------------------- */
int luat_rtos_message_send(luat_rtos_task_handle task_handle, uint32_t message_id, void *p_message) {
    if (task_handle == NULL) {
        LLOGE("task_handle is NULL");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;

    utask_node_t* node = luat_heap_malloc(sizeof(utask_node_t) + sizeof(luat_message_item_t));
    if (node == NULL) {
        LLOGE("out of memory for message item");
        return -1;
    }
    node->next = NULL;
    node->payload_size = sizeof(luat_message_item_t);
    luat_message_item_t* it = (luat_message_item_t*)UTASK_NODE_PAYLOAD(node);
    it->id = message_id;
    it->msg = p_message;

    pthread_mutex_lock(&task->m);
    if (task->exit_flag) {
        pthread_mutex_unlock(&task->m);
        luat_heap_free(node);
        return -1;
    }
    if (task->q_limit && task->q_count >= task->q_limit) {
        pthread_mutex_unlock(&task->m);
        luat_heap_free(node);
        LLOGE("task msg queue full (limit=%u)", task->q_limit);
        return -1;
    }
    utask_q_push_locked(task, node);
    pthread_cond_signal(&task->cv);
    pthread_mutex_unlock(&task->m);
    return 0;
}

/* ---------------------- 接收消息 ---------------------- */
int luat_rtos_message_recv(luat_rtos_task_handle task_handle, uint32_t *message_id, void **p_p_message, uint32_t timeout) {
    if (task_handle == NULL || message_id == NULL || p_p_message == NULL) {
        LLOGE("invalid args for message_recv");
        return -1;
    }
    utask_t* task = (utask_t*)task_handle;

    const int forever = (timeout == LUAT_WAIT_FOREVER || timeout == (uint32_t)(-1));
    struct timespec abs;
    if (!forever && timeout > 0) {
        luat_calc_abs_timeout(&abs, timeout);
    }

    pthread_mutex_lock(&task->m);
    while (1) {
        if (task->exit_flag) {
            pthread_mutex_unlock(&task->m);
            return -1;
        }
        utask_node_t* node = utask_q_pop_locked(task);
        if (node) {
            luat_message_item_t it = *(luat_message_item_t*)UTASK_NODE_PAYLOAD(node);
            luat_heap_free(node);
            *message_id   = it.id;
            *p_p_message  = it.msg;
            pthread_mutex_unlock(&task->m);
            return 0;
        }
        if (timeout == 0) {
            pthread_mutex_unlock(&task->m);
            return 1;
        }
        if (forever) {
            pthread_cond_wait(&task->cv, &task->m);
        } else {
            int wret = pthread_cond_timedwait(&task->cv, &task->m, &abs);
            if (wret == ETIMEDOUT) {
                pthread_mutex_unlock(&task->m);
                return 1;
            }
        }
    }
}

/* ---------------------- 临界区 (PC 无意义) ---------------------- */
void luat_os_entry_cri(void) {}
void luat_os_exit_cri(void) {}

uint32_t luat_rtos_entry_critical(void) {
    return 0;
}

void luat_rtos_exit_critical(uint32_t critical) {
    (void)critical;
}

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_queue_pc.h"

#include "luat_posix_compat.h"

#define LUAT_LOG_TAG "msgbus"
#include "luat_log.h"

#include <stddef.h>   /* offsetof */

static uv_queue_item_t head;
static pthread_mutex_t m;
static pthread_cond_t  cv;

void luat_msgbus_init(void)
{
    pthread_mutex_init(&m, NULL);
    pthread_cond_init(&cv, NULL);
}

uint32_t luat_msgbus_put(rtos_msg_t *msg, size_t timeout)
{
    (void)timeout;
    if (msg == NULL) return 1;
    /* 分配 = header(next, size, msg[]起始) + payload 实际字节数;
     * offsetof 而不是 sizeof 避免重复计入 msg[4] 占位与 padding. */
    uv_queue_item_t *item = luat_heap_malloc(offsetof(uv_queue_item_t, msg) + sizeof(rtos_msg_t));
    if (item == NULL)
    {
        LLOGE("out of memory when malloc uv_queue_item_t");
        return 1;
    }
    item->next = NULL;
    item->size = sizeof(rtos_msg_t);
    memcpy(item->msg, msg, sizeof(rtos_msg_t));

    pthread_mutex_lock(&m);
    int ret = luat_queue_push(&head, item);
    pthread_cond_signal(&cv);
    pthread_mutex_unlock(&m);
    return ret;
}

uint32_t luat_msgbus_get(rtos_msg_t *msg, size_t timeout)
{
    if (msg == NULL) return 1;
    uv_queue_item_t *item = luat_heap_malloc(offsetof(uv_queue_item_t, msg) + sizeof(rtos_msg_t));
    if (item == NULL)
    {
        LLOGE("out of memory when malloc uv_queue_item_t");
        return 1;
    }

    const int forever = (timeout == (size_t)(-1));
    struct timespec abs;
    if (!forever && timeout > 0) {
        luat_calc_abs_timeout(&abs, (uint32_t)timeout);
    }

    int ret = 1;
    pthread_mutex_lock(&m);
    while (1)
    {
        if (luat_queue_pop(&head, item) == 0)
        {
            pthread_mutex_unlock(&m);
            memcpy(msg, item->msg, sizeof(rtos_msg_t));
            luat_heap_free(item);
            return 0;
        }
        if (timeout == 0) {
            ret = 1;
            break;
        }
        if (forever) {
            pthread_cond_wait(&cv, &m);
        } else {
            int wret = pthread_cond_timedwait(&cv, &m, &abs);
            if (wret == ETIMEDOUT) {
                ret = 1;
                break;
            }
        }
    }
    pthread_mutex_unlock(&m);
    luat_heap_free(item);
    return ret;
}

uint32_t luat_msgbus_freesize(void)
{
    return 1;
}

uint8_t luat_msgbus_is_empty(void)
{
    return head.next == NULL ? 1 : 0;
}

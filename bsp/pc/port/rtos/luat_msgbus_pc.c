#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_queue_pc.h"

#include "luat_posix_compat.h"

#define LUAT_LOG_TAG "msgbus"
#include "luat_log.h"

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
    uv_queue_item_t *item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(rtos_msg_t));
    if (item == NULL)
    {
        LLOGE("out of memory when malloc uv_queue_item_t");
        return 1;
    }
    memset(item, 0, sizeof(uv_queue_item_t));
    memcpy(item->msg, msg, sizeof(rtos_msg_t));
    item->size = sizeof(rtos_msg_t);
    pthread_mutex_lock(&m);
    int ret = luat_queue_push(&head, item);
    pthread_cond_signal(&cv);
    pthread_mutex_unlock(&m);
    return ret;
}

uint32_t luat_msgbus_get(rtos_msg_t *msg, size_t timeout)
{
    (void)timeout;
    uv_queue_item_t *item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(rtos_msg_t));
    if (item == NULL)
    {
        LLOGE("out of memory when malloc uv_queue_item_t");
        return 1;
    }
    int ret = 0;
    pthread_mutex_lock(&m);
    while (1)
    {
        ret = luat_queue_pop(&head, item);
        if (ret == 0)
        {
            pthread_mutex_unlock(&m);
            memcpy(msg, item->msg, sizeof(rtos_msg_t));
            luat_heap_free(item);
            return 0;
        }
        /* Queue empty – block until luat_msgbus_put signals */
        pthread_cond_wait(&cv, &m);
    }
    pthread_mutex_unlock(&m);
    luat_heap_free(item);
    return 1;
}

uint32_t luat_msgbus_freesize(void)
{
    return 1;
}

uint8_t luat_msgbus_is_empty(void)
{
    return head.next == NULL ? 1 : 0;
}

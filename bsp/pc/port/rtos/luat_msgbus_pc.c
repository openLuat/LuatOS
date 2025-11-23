#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_queue_pc.h"

#include "uv.h"

#define LUAT_LOG_TAG "msgbus"
#include "luat_log.h"

static uv_queue_item_t head;

static uv_mutex_t m;
extern uv_loop_t *main_loop;

void luat_msgbus_init(void)
{
    // head.is_head = 1;
    uv_mutex_init(&m);
}
uint32_t luat_msgbus_put(rtos_msg_t *msg, size_t timeout)
{
    (void)timeout;
    // LLOGD("luat_msgbus_put %p %d", msg, timeout);
    uv_queue_item_t *item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(rtos_msg_t));
    if (item == NULL)
    {
        LLOGE("out of memory when malloc uv_queue_item_t");
        return 1;
    }
    memset(item, 0, sizeof(uv_queue_item_t));
    memcpy(item->msg, msg, sizeof(rtos_msg_t));
    item->size = sizeof(rtos_msg_t);
    uv_mutex_lock(&m);
    int ret = luat_queue_push(&head, item);
    uv_mutex_unlock(&m);
    return ret;
}
uint32_t luat_msgbus_get(rtos_msg_t *msg, size_t timeout)
{
    // LLOGD("luat_msgbus_get %d", timeout);
    (void)timeout;
    uv_queue_item_t *item = luat_heap_malloc(sizeof(uv_queue_item_t) + sizeof(rtos_msg_t));
    int ret = 0;
    int ret2 = 0;
    while (1)
    {
        
        uv_mutex_lock(&m);
        ret = luat_queue_pop(&head, item);
        uv_mutex_unlock(&m);
        if (ret == 0)
        {
            memcpy(msg, item->msg, sizeof(rtos_msg_t));
            luat_heap_free(item);
            return 0;
        }
        ret2 = uv_run(main_loop, UV_RUN_ONCE);
    }
    return 1;
}
uint32_t luat_msgbus_freesize(void)
{
    return 1;
}

uint8_t luat_msgbus_is_empty(void)
{
    return head.next == NULL ? 1 : 0;
    // return 0;
}

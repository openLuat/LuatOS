#include "luat_base.h"
#include "luat_rtos.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"

LUAT_RET luat_queue_create(luat_rtos_queue_t* queue, size_t msgcount, size_t msgsize) {
    queue = xQueueCreate(msgcount, msgsize);
    if (queue == NULL) {
        return -1;
    }
    return LUAT_ERR_OK;
}

LUAT_RET luat_queue_send(luat_rtos_queue_t*   queue, void* msg,  size_t msg_size, size_t timeout) {
    if (queue == NULL)
        return LUAT_ERR_FAIL;
    if (xQueueSend((QueueHandle_t)queue, msg, timeout) == pdTRUE) {
        return LUAT_ERR_OK;
    }
    return LUAT_ERR_FAIL;
}
LUAT_RET luat_queue_recv(luat_rtos_queue_t*   queue, void* msg, size_t msg_size, size_t timeout) {
    if (queue == NULL)
        return LUAT_ERR_FAIL;
    if (xQueueReceive((QueueHandle_t)queue, msg, timeout) == pdTRUE) {
        return LUAT_ERR_OK;
    }
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_queue_reset(luat_rtos_queue_t*   queue) {
    if (queue == NULL)
        return LUAT_ERR_FAIL;
    if (pdTRUE == xQueueReset((QueueHandle_t)queue)) {
        return LUAT_ERR_OK;
    }
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_queue_delete(luat_rtos_queue_t*   queue) {
    if (queue) {
        vQueueDelete((QueueHandle_t)queue);
    }
    return LUAT_ERR_OK;
}

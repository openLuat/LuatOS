#include "luat_base.h"
#include "luat_rtos.h"

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semaphore.h"

LUAT_RET luat_queue_create(luat_rtos_queue_t* queue, size_t msgcount, size_t msgsize) {
    QueueHandle_t q = xQueueCreate(msgcount, msgsize);
    if (q == NULL) {
        return -1;
    }
    queue->userdata = q;
    return LUAT_ERR_OK;
}

LUAT_RET luat_queue_send(luat_rtos_queue_t*   queue, void* msg,  size_t msg_size, size_t timeout) {
    if (queue->userdata == NULL)
        return LUAT_ERR_FAIL;
    if (xQueueSend(queue->userdata, msg, timeout) == pdTRUE) {
        return LUAT_ERR_OK;
    }
    return LUAT_ERR_FAIL;
}
LUAT_RET luat_queue_recv(luat_rtos_queue_t*   queue, void* msg, size_t msg_size, size_t timeout) {
    if (queue->userdata == NULL)
        return LUAT_ERR_FAIL;
    if (xQueueReceive(queue->userdata, msg, timeout) == pdTRUE) {
        return LUAT_ERR_OK;
    }
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_queue_reset(luat_rtos_queue_t*   queue) {
    if (queue->userdata == NULL)
        return LUAT_ERR_FAIL;
    if (pdTRUE == xQueueReset((QueueHandle_t)queue->userdata)) {
        return LUAT_ERR_OK;
    }
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_queue_delete(luat_rtos_queue_t*   queue) {
    if (queue->userdata) {
        vQueueDelete((QueueHandle_t)queue->userdata);
    }
    queue->userdata = NULL;
    return LUAT_ERR_OK;
}

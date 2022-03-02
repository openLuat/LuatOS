#include "luat_base.h"
#include "luat_rtos.h"

#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "semaphore.h"

#define LUAT_LOG_TAG "thread"
#include "luat_log.h"

static void task_proxy(void* params) {
    luat_thread_t* thread = (luat_thread_t*)params;
    thread->thread(thread->userdata);
    xTaskDelete(NULL); // 代理删除自身
    
    LLOGD("impossible %s %d", __FILE__, __LINE__);
    // 不可能到这里
    while (1);
}

LUAT_RET luat_thread_start(luat_thread_t* thread) {
    int ret = xTaskCreate(task_proxy, thread->name, thread->stack_size, thread, thread->priority, NULL);
    if (ret == pdPASS) {
        return LUAT_ERR_OK;
    }
    LLOGD("thread start fail %d", ret);
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_thread_stop(luat_thread_t* thread) {
    return LUAT_ERR_FAIL;
}

LUAT_RET luat_thread_delete(luat_thread_t* thread) {
    return LUAT_ERR_FAIL;
}

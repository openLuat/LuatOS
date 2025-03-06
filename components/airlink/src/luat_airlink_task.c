#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_rtos.h"
#include "luat_crypto.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

static luat_rtos_task_handle airlink_task_handle;

void luat_airlink_on_data_recv(uint8_t *data, size_t len) {
    void* ptr = luat_heap_opt_malloc(LUAT_HEAP_PSRAM, len);
    if (ptr == NULL) {
        LLOGE("airlink分配内存失败!!! %d", len);
        return;
    }
    memcpy(ptr, data, len);
    luat_rtos_event_send(airlink_task_handle, 1, (uint32_t)ptr, len, 0, 0);
}

static int luat_airlink_task(void *param) {
    LLOGD("处理线程启动");
    luat_event_t event;
    void* ptr = NULL;
    size_t len = 0;
    while (1) {
        luat_rtos_event_recv(airlink_task_handle, 0, &event, NULL, LUAT_WAIT_FOREVER);
        if (event.id == 1) { // 收到数据了, 马上处理
            // 处理数据
            ptr = (void*)event.param1;
            len = event.param2;
            // TODO 真正的处理逻辑
            LLOGD("收到指令/回复 ptr %p len %d", ptr, len);

            // 处理完成, 释放内存
            luat_heap_opt_free(LUAT_HEAP_PSRAM, ptr);
        }
    }
    return 0;
}

void luat_airlink_task_start(void) {
    if (airlink_task_handle == NULL) {
        luat_rtos_task_create(&airlink_task_handle, 8 * 1024, 20, "airlink", luat_airlink_task, NULL, 1024);
    }
    else {
        LLOGD("airlink task 已经启动过了");
    }
}

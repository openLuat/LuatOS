#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"

#include "luat_drv_ble.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"

#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "drv.bt"
#include "luat_log.h"

static luat_rtos_queue_t evt_queue;
static luat_rtos_task_handle g_task_handle;

static void drv_ble_cb(luat_ble_t* luat_ble, luat_ble_event_t ble_event, luat_ble_param_t* ble_param) {
    // 注意, 这里要代理不同的事件, 转发到airlink
}

static void drv_bt_task(void *param) {
    luat_drv_ble_msg_t *msg = NULL;
    LLOGD("bt task start ...");
    int ret = 0;
    while (1) {
        msg = NULL;
        // 接收消息, 然后执行
        ret = luat_rtos_queue_recv(evt_queue, &msg, 0, LUAT_WAIT_FOREVER);
        LLOGD("bt task recv msg %d %p", ret, msg);
        if (msg) {
            // 执行指令
            switch (msg->cmd_id)
            {
            case LUAT_DRV_BT_CMD_BT_INIT:
                LLOGD("执行luat_bluetooth_init");
                ret = luat_bluetooth_init(NULL);
                LLOGD("bt init %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BT_DEINIT:
                ret = luat_bluetooth_deinit(NULL);
                LLOGD("bt deinit %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_INIT:
                ret = luat_ble_init(NULL, drv_ble_cb); // 不能通过airlink传递函数指针, 这里要用本地的
                LLOGD("ble init %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_DEINIT:
                ret = luat_ble_deinit(NULL);
                LLOGD("ble deinit %d", ret);
                break;
            default:
                LLOGD("unknow bt cmd %d", msg->cmd_id);
                break;
            }
            luat_heap_free(msg);
        }
        luat_rtos_task_sleep(5); // TODO 删掉
    }
}

int luat_drv_bt_msg_send(luat_drv_ble_msg_t *msg) {
    if (evt_queue == NULL) {
        LLOGE("evt queue is NULL");
        return -1;
    }
    luat_rtos_queue_send(evt_queue, &msg, 0, 0);
    return 0;
}

int luat_drv_bt_task_start(void) {
    int ret = 0;
    if (evt_queue == NULL) {
        ret = luat_rtos_queue_create(&evt_queue, 1024, sizeof(void*));
        if (ret) {
            LLOGE("evt queue create failed %d", ret);
            return -1;
        }
    }
    if (g_task_handle == NULL) {
        ret = luat_rtos_task_create(&g_task_handle, 8*1024, 20, "drv_bt", drv_bt_task, NULL, 0);
        if (ret) {
            LLOGE("drv_bt task create failed %d", ret);
            return -1;
        }
    }
    return 0;
}

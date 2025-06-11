#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_bt.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_netdrv.h"
#include "luat_mem.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "airlink.bt"
#include "luat_log.h"

#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH

#include "luat_drv_ble.h"

int luat_airlink_cmd_exec_bt_request(luat_airlink_cmd_t *cmd, void *userdata)
{
    luat_drv_ble_msg_t *msg = luat_heap_malloc(sizeof(luat_drv_ble_msg_t) + cmd->len);
    if (msg == NULL) {
        LLOGE("out of memory when malloc luat_drv_ble_msg_t");
        return -1;
    }
    memcpy(&msg->id, cmd->data, 8);
    msg->cmd_id = cmd->data[8];
    memcpy(&msg->data, cmd->data + 9, cmd->len - 9);
    msg->len = cmd->len - 9;
    if (msg->cmd_id == 0) {
        luat_drv_bt_task_start();
    }
    luat_drv_bt_msg_send(msg);
    return 0;
}

#endif
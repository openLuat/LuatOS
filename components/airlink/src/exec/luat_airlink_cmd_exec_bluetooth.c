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
    // LLOGD("收到bt request len=%d", cmd->len);
    if (cmd->len < sizeof(luat_drv_ble_msg_t)) {
        return -100;
    }
    luat_drv_ble_msg_t *msg = luat_heap_malloc(cmd->len);
    if (msg == NULL) {
        LLOGE("out of memory when malloc luat_drv_ble_msg_t");
        return -1;
    }
    memcpy(msg, cmd->data, cmd->len);
    msg->len = cmd->len - sizeof(luat_drv_ble_msg_t);
    LLOGD("bt request cmd_id=%d len %d", msg->cmd_id, msg->len);
    // luat_airlink_print_buff("bt req HEX", cmd->data, cmd->len);
    if (msg->cmd_id == 0) {
        luat_drv_bt_task_start();
    }
    luat_drv_bt_msg_send(msg);
    return 0;
}

#endif


#include "luat_drv_ble.h"

extern luat_ble_cb_t g_drv_ble_cb;

int luat_airlink_cmd_exec_bt_resp_cb(luat_airlink_cmd_t *cmd, void *userdata) {
    if (cmd->len < 10) {
        return -100;
    }
    if (g_drv_ble_cb == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t* msg = (luat_drv_ble_msg_t *)(cmd->data);
    if (msg->cmd_id == LUAT_DRV_BT_CMD_BLE_EVENT_CB) {
        uint32_t tmp = 0;
        memcpy(&tmp, msg->data, 4);
        luat_ble_event_t event = (luat_ble_event_t)tmp;
        luat_ble_param_t param = {0};
        memcpy(&param, msg->data + 4, sizeof(luat_ble_param_t));
        // 以下数据暂时填0, 还没想好怎么传
        param.adv_req.data_len = 0;
        param.adv_req.data = NULL;
        param.read_req.len = 0;
        param.read_req.value = NULL;
        param.write_req.len = 0;
        param.write_req.value = NULL;
        LLOGD("收到bt event %d %d", event, cmd->len - sizeof(luat_drv_ble_msg_t));
        g_drv_ble_cb(NULL, event, &param);
        return 0;
    }
    return 0;
}

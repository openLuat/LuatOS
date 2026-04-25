#include "luat_base.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_netdrv.h"
#include "luat_mem.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "airlink.bt"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

#if defined(LUAT_USE_AIRLINK_EXEC_BLUETOOTH) || defined(LUAT_USE_AIRLINK_EXEC_BLUETOOTH_RESP)
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_bt.h"
#include "luat_drv_ble.h"
#endif

#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH

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

#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH_RESP



extern luat_ble_cb_t g_drv_ble_cb;
static luat_ble_gatt_service_t* s_gatts[16];

int luat_airlink_cmd_exec_bt_resp_cb(luat_airlink_cmd_t *cmd, void *userdata) {
    if (cmd->len < 10) {
        return -100;
    }
    if (g_drv_ble_cb == NULL) {
        return -101;
    }
    uint32_t tmp = 0;
    size_t offset = 4 + sizeof(luat_ble_param_t);
    size_t tmplen = 0;
    luat_ble_gatt_service_t* gatt;
    luat_ble_gatt_chara_t* gatt_chara;
    luat_ble_gatt_descriptor_t* gatt_chara_desc;
    luat_drv_ble_msg_t* msg = (luat_drv_ble_msg_t *)(cmd->data);
    if (msg->cmd_id == LUAT_DRV_BT_CMD_BLE_EVENT_CB) {
        memcpy(&tmp, msg->data, 4);
        luat_ble_event_t event = (luat_ble_event_t)tmp;
        luat_ble_param_t* param = (luat_ble_param_t*)(msg->data + 4);
        // memcpy(param, msg->data + 4, sizeof(luat_ble_param_t));
        LLOGD("收到bt event %d %d", event, cmd->len - sizeof(luat_drv_ble_msg_t));
        // param->write_req.value = NULL;
        // param->adv_req.data = NULL;
        // param->read_req.value = NULL;

        // 把能处理的先尝试处理一下
        if (event == LUAT_BLE_EVENT_WRITE && param->write_req.value_len) {
            param->write_req.value = (uint8_t*)(msg->data + offset);
        }
        // else if (event == LUAT_BLE_EVENT_READ && param.read_req.len) {
        //     param.read_req.value = luat_heap_malloc(param.read_req.len);
        //     memcpy(param.read_req.value, msg->data + offset, param.read_req.len);
        // }
        else if (event == LUAT_BLE_EVENT_SCAN_REPORT && param->adv_req.data_len) {
            param->adv_req.data = (uint8_t*)(msg->data + offset);
        }
        else if (event == LUAT_BLE_EVENT_READ_VALUE && param->read_req.value_len) {
            param->read_req.value = (uint8_t*)(msg->data + offset);
        }
        else if (event == LUAT_BLE_EVENT_GATT_ITEM) {
            tmp = param->gatt_item_ind.gatt_service_index;
            if (tmp >= 16) {
                LLOGE("gatt item index %d out of range", tmp);
                return -1;
            }
            if (s_gatts[tmp] == NULL) {
                s_gatts[tmp] = luat_heap_malloc(sizeof(luat_ble_gatt_service_t));
                if (s_gatts[tmp] == NULL) {
                    LLOGE("out of memory when malloc gatt service");
                    return -1;
                }
            }
            else {
                gatt = s_gatts[tmp];
                for (size_t ch_i = 0; ch_i < gatt->characteristics_num; ch_i++)
                {
                    if (gatt->characteristics[ch_i].descriptor != NULL) {
                        luat_heap_free(gatt->characteristics[ch_i].descriptor);
                        gatt->characteristics[ch_i].descriptor = NULL;
                    } 
                }
                luat_heap_free(gatt->characteristics);
                gatt->characteristics = NULL;
                gatt->characteristics_num = 0;
            }
            luat_ble_gatt_unpack(s_gatts[tmp], msg->data + offset, &tmplen);
            if (tmplen == 0) {
                LLOGE("gatt item unpack failed, gatt %p len=0!!!", s_gatts[tmp]);
                return -1;
            }
            param->gatt_item_ind.gatt_service = s_gatts[tmp];
        }
        else if (event == LUAT_BLE_EVENT_GATT_DONE) {
            LLOGI("gatt done, gatt total %d", param->gatt_done_ind.gatt_service_num);
        }
        g_drv_ble_cb(NULL, event, param);
        return 0;
    }
    return 0;
}

int luat_airlink_cmd_exec_bt_resp_result_cb(luat_airlink_cmd_t *cmd, void *userdata) {
    if (cmd->len < 10) {
        return -100;
    }
    luat_drv_ble_msg_t* msg = (luat_drv_ble_msg_t *)(cmd->data);
    luat_drv_ble_result_t *resp_result = (luat_drv_ble_result_t *)(msg->data);
    LLOGD("执行结果 result: %d", resp_result->result);
    return 0;
}

#endif



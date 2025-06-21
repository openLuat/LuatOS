#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"

#if defined(LUAT_USE_AIRLINK_EXEC_BLUETOOTH) || defined(LUAT_USE_AIRLINK_EXEC_BLUETOOTH_RESP)
#include "luat_drv_ble.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#endif

#include "luat_mem.h"
#include "luat_mcu.h"
#include "luat_fs.h"

#define LUAT_LOG_TAG "drv.bt"
#include "luat_log.h"

#ifdef LUAT_USE_AIRLINK_EXEC_BLUETOOTH

static luat_rtos_queue_t evt_queue;
static luat_rtos_task_handle g_task_handle;

static void drv_ble_cb(luat_ble_t* luat_ble, luat_ble_event_t event, luat_ble_param_t* param) {
    // 注意, 这里要代理不同的事件, 转发到airlink
    LLOGD("drv_ble event %d", event);
    uint64_t seq = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len =  sizeof(luat_airlink_cmd_t) + sizeof(luat_drv_ble_msg_t) + 1024
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x510, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        LLOGW("out of memory when alloc ble event");
        return;
    }
    luat_drv_ble_msg_t *msg = (luat_drv_ble_msg_t *)cmd->data;
    void* ptr = cmd->data + sizeof(luat_drv_ble_msg_t);
    msg->id = seq;
    msg->cmd_id = LUAT_DRV_BT_CMD_BLE_EVENT_CB;

    uint32_t tmp = event;
    memcpy(ptr, &tmp, 4);
    if (param) {
        LLOGD("param %p", param);
        if (LUAT_BLE_EVENT_SCAN_REPORT == event && param->adv_req.data && param->adv_req.data_len > 0) {
            memcpy(ptr + 4 + sizeof(luat_ble_param_t), param->adv_req.data, param->adv_req.data_len);
        }
        else if (LUAT_BLE_EVENT_READ == event) {
            // 请求读, 这个事件仅能通知lua, .value的数据是要被写入的, 不是被读
        }
        else if (LUAT_BLE_EVENT_WRITE == event && param->write_req.value_len && param->write_req.value_len > 0) {
            LLOGD("write req value %d %p", param->write_req.value_len, param->write_req.value);
            memcpy(ptr + 4 + sizeof(luat_ble_param_t), param->write_req.value, param->write_req.value_len);
        }
        memcpy(ptr + 4, param, sizeof(luat_ble_param_t));
    }

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
}

static int drv_gatt_create(luat_drv_ble_msg_t *msg) {
    // 从数据中解析出参数, 重新组装
    luat_ble_gatt_service_t* gatt = luat_heap_malloc(sizeof(luat_ble_gatt_service_t));
    if (gatt == NULL) {
        LLOGE("out of memory when malloc gatt");
        return -1;
    }
    size_t offset = 0;
    uint16_t sizeof_gatt = 0;
    uint16_t sizeof_gatt_chara = 0;
    uint16_t num_of_gatt_srv = 0;
    uint16_t sizeof_gatt_desc = 0;
    memcpy(&sizeof_gatt, msg->data, 2);
    memcpy(&sizeof_gatt_chara, msg->data + 2, 2);
    memcpy(&num_of_gatt_srv, msg->data + 4, 2);
    memcpy(&sizeof_gatt_desc, msg->data + 6, 2);
    // LLOGD("sizeof(luat_ble_gatt_service_t) = %d act %d", sizeof(luat_ble_gatt_service_t), sizeof_gatt);
    // LLOGD("sizeof(luat_ble_gatt_service_t) = %d act %d", sizeof(luat_ble_gatt_chara_t), sizeof_gatt_chara);
    offset = 8;
    
    memcpy(gatt, msg->data + offset, sizeof(luat_ble_gatt_service_t));
    offset += sizeof(luat_ble_gatt_service_t);

    LLOGD("Gatt characteristics_num %d", gatt->characteristics_num);
    gatt->characteristics = luat_heap_malloc(sizeof(luat_ble_gatt_chara_t) * gatt->characteristics_num);
    for (size_t i = 0; i < gatt->characteristics_num; i++)
    {
        memcpy(&gatt->characteristics[i], msg->data + 8 + sizeof(luat_ble_gatt_service_t) + sizeof_gatt_chara * i, sizeof(luat_ble_gatt_chara_t));
        if (gatt->characteristics[i].descriptors_num) {
            LLOGD("gatt->characteristics[%d].descriptors_num %d", i, gatt->characteristics[i].descriptors_num);
            gatt->characteristics[i].descriptor = luat_heap_malloc(gatt->characteristics[i].descriptors_num * sizeof(luat_ble_gatt_descriptor_t));
        }
        offset += sizeof(luat_ble_gatt_chara_t);
    }
    for (size_t i = 0; i < gatt->characteristics_num; i++)
    {
        if (gatt->characteristics[i].descriptors_num) {
            memcpy(gatt->characteristics[i].descriptor, msg->data + offset, gatt->characteristics[i].descriptors_num * sizeof(luat_ble_gatt_descriptor_t));
        }
        offset += gatt->characteristics[i].descriptors_num * sizeof(luat_ble_gatt_descriptor_t);
    }

    return luat_ble_create_gatt(NULL, gatt);
}

static int drv_adv_create(luat_drv_ble_msg_t *msg) {
    // 从数据中解析出参数, 重新组装
    luat_ble_adv_cfg_t adv = {0};
    uint16_t sizeof_adv = 0;
    memcpy(&sizeof_adv, msg->data, 2);
    memcpy(&adv, msg->data + 2, sizeof(luat_ble_adv_cfg_t));
    return luat_ble_create_advertising(NULL, &adv);
}

static int drv_adv_set_data(luat_drv_ble_msg_t *msg) {
    // 从数据中解析出参数, 重新组装
    uint16_t datalen = 0;
    memcpy(&datalen, msg->data, 2);
    LLOGD("adv set data len %d", datalen);
    return luat_ble_set_adv_data(NULL, msg->data + 2, datalen);
}

static int drv_adv_set_scan_rsp_data(luat_drv_ble_msg_t *msg) {
    // 从数据中解析出参数, 重新组装
    uint16_t datalen = 0;
    memcpy(&datalen, msg->data, 2);
    LLOGD("adv set scan rsp data len %d", datalen);
    return luat_ble_set_scan_rsp_data(NULL, msg->data + 2, datalen);
}

static int drv_adv_create_scanning(luat_drv_ble_msg_t *msg) {
    // 从数据中解析出参数, 重新组装
    luat_ble_scan_cfg_t scan = {0};
    uint16_t sizeof_scan = 0;
    memcpy(&sizeof_scan, msg->data, 2);
    memcpy(&scan, msg->data + 2, sizeof(luat_ble_scan_cfg_t));
    return luat_ble_create_scanning(NULL, &scan);
}

static int drv_ble_write_notify(luat_drv_ble_msg_t *msg) {
    // 从数据中解析出参数, 重新组装
    luat_ble_rw_req_t write = {0};
    uint16_t sizeof_write = 0;
    memcpy(&sizeof_write, msg->data, 2);
    memcpy(&write, msg->data + 2, sizeof(luat_ble_rw_req_t));
    LLOGD("ble write notify len %d", write.len);
    // LLOGD("ble write notify %.*s", write.len, msg->data + 2 + sizeof_write);
    if (write.descriptor.uuid_type) {
        return luat_ble_write_notify_value(&write.service, &write.characteristic, &write.descriptor, msg->data + 2 + sizeof_write, write.len);
    }
    else {
        return luat_ble_write_notify_value(&write.service, &write.characteristic, NULL, msg->data + 2 + sizeof_write, write.len);
    }
    
}

static int drv_ble_write_indication(luat_drv_ble_msg_t *msg) {
    // 从数据中解析出参数, 重新组装
    luat_ble_rw_req_t write = {0};
    uint16_t sizeof_write = 0;
    memcpy(&sizeof_write, msg->data, 2);
    memcpy(&write, msg->data + 2, sizeof(luat_ble_rw_req_t));
    LLOGD("ble write indication len %d", write.len);
    // LLOGD("ble write notify %.*s", write.len, msg->data + 2 + sizeof_write);
    if (write.descriptor.uuid_type) {
        return luat_ble_write_indicate_value(&write.service, &write.characteristic, &write.descriptor, msg->data + 2 + sizeof_write, write.len);
    }
    else {
        return luat_ble_write_indicate_value(&write.service, &write.characteristic, NULL, msg->data + 2 + sizeof_write, write.len);
    }
    
}

// static int drv_ble_send_read_resp(luat_drv_ble_msg_t *msg) {
//     // 从数据中解析出参数, 重新组装
//     luat_ble_rw_req_t write = {0};
//     uint16_t sizeof_write = 0;
//     memcpy(&sizeof_write, msg->data, 2);
//     memcpy(&write, msg->data + 2, sizeof(luat_ble_rw_req_t));
//     LLOGD("ble send read resp len %d", write.len);
//     return luat_ble_read_response_value(NULL, write.handle, msg->data + 2 + sizeof_write, write.len);
// }

static void drv_bt_task(void *param) {
    luat_drv_ble_msg_t *msg = NULL;
    LLOGD("bt task start ...");
    int ret = 0;
    char buff[128] = {0};
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
            case LUAT_DRV_BT_CMD_BLE_GATT_CREATE:
                ret = drv_gatt_create(msg);
                LLOGD("ble gatt create %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_SET_NAME:
                memcpy(buff, msg->data + 1, msg->data[0]);
                buff[msg->data[0]] = 0;
                ret = luat_ble_set_name(NULL, buff, msg->data[0]);
                LLOGD("ble set name %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_ADV_CREATE:
                ret = drv_adv_create(msg);
                LLOGD("ble adv start %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_ADV_START:
                ret = luat_ble_start_advertising(NULL);
                LLOGD("ble adv start %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_ADV_STOP:
                ret = luat_ble_stop_advertising(NULL);
                LLOGD("ble adv stop %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_ADV_DELETE:
                ret = luat_ble_delete_advertising(NULL);
                LLOGD("ble adv delete %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_ADV_SET_DATA:
                ret = drv_adv_set_data(msg);
                LLOGD("ble adv set data %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_ADV_SET_SCAN_RSP_DATA:
                ret = drv_adv_set_scan_rsp_data(msg);
                LLOGD("ble adv set resp data %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_SCAN_CREATE:
                ret = drv_adv_create_scanning(msg);
                LLOGD("ble adv create scanning %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_SCAN_START:
                ret = luat_ble_start_scanning(NULL);
                LLOGD("ble adv start scanning %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_SCAN_STOP:
                ret = luat_ble_stop_scanning(NULL);
                LLOGD("ble adv stop scanning %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_SCAN_DELETE:
                ret = luat_ble_delete_scanning(NULL);
                LLOGD("ble adv delete scaning %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_WRITE_NOTIFY:
                ret = drv_ble_write_notify(msg);
                LLOGD("ble wrtite notify %d", ret);
                break;
            case LUAT_DRV_BT_CMD_BLE_WRITE_INDICATION:
                ret = drv_ble_write_indication(msg);
                LLOGD("ble wrtite indication %d", ret);
                break;
                
            // case LUAT_DRV_BT_CMD_BLE_SEND_READ_RESP:
            //     ret = drv_ble_send_read_resp(msg);
            //     LLOGD("ble send read resp %d", ret);
            //     break;
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

#endif

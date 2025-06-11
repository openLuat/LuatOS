#include "luat_base.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_bt.h"
#include "luat_mem.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

int luat_airlink_drv_bluetooth_init(luat_bluetooth_t* luat_bluetooth) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_bluetooth_t) + sizeof(luat_ble_t) + sizeof(luat_bt_t)+ sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_bluetooth, sizeof(luat_bluetooth_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_uuid_swap(uint8_t* uuid_data, luat_ble_uuid_type uuid_type)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    uint8_t uuid_len = 0;
    if(uuid_type == LUAT_BLE_UUID_TYPE_16){
        uuid_len = 2;
    }else if(uuid_type == LUAT_BLE_UUID_TYPE_32){
        uuid_len = 4;
    }else if(uuid_type == LUAT_BLE_UUID_TYPE_128){
        uuid_len = 16;
    }else{
        return -101;
    }

    airlink_queue_item_t item = {
        .len = uuid_len + 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x510, item.len);
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    // memcpy(cmd->data + 8, &uuid_data, uuid_len);
    // memcpy(cmd->data + uuid_len+ 8, &uuid_len, 1·);
    uint8_t* data = cmd->data + 8;
    data[0] = *uuid_data;
    data[1] = uuid_type;
    // memcpy(cmd->data + uuid_len + 8, &uuid_type, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

// struct luat_ble{
//     luat_ble_actv_state state;
//     luat_ble_cb_t cb;
//     int lua_cb;
//     int ble_ref;
//     void* userdata;
// };
int luat_airlink_drv_ble_init(luat_ble_t* luat_ble, luat_ble_cb_t luat_ble_cb) {;
    LLOGE("luat_airlink_drv_ble_init luat_ble_cb %d", luat_ble_cb);
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(void *) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x511, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    cmd->func[0] = luat_ble_cb;
    item.cmd = cmd;

    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
};

int luat_airlink_drv_ble_deinit(luat_ble_t* luat_ble)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x512, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_set_name(luat_ble_t* luat_ble, char* name, uint8_t len)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + len + 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x513, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + 8, &name, len);
    memcpy(cmd->data + sizeof(luat_ble_t) + len + 8, &len, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_set_max_mtu(luat_ble_t* luat_ble, uint16_t max_mtu)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x514, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + 8, &max_mtu, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

// advertise
int luat_airlink_drv_ble_create_advertising(luat_ble_t* luat_ble, luat_ble_adv_cfg_t* adv_cfg)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t)  + sizeof(luat_ble_adv_cfg_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x515, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + 8, adv_cfg, sizeof(luat_ble_adv_cfg_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_set_adv_data(luat_ble_t* luat_ble, uint8_t* adv_buff, uint8_t adv_len)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + adv_len + 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x516, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + 8, &adv_buff, adv_len);
    memcpy(cmd->data + sizeof(luat_ble_t) + adv_len + 8, &adv_len, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_set_scan_rsp_data(luat_ble_t* luat_ble, uint8_t* rsp_data, uint8_t rsp_len)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + rsp_len + 1 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x517, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + 8, &rsp_data, rsp_len);
    memcpy(cmd->data + sizeof(luat_ble_t) + rsp_len + 8, &rsp_len, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_start_advertising(luat_ble_t* luat_ble)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x518, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_stop_advertising(luat_ble_t* luat_ble)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x519, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_delete_advertising(luat_ble_t* luat_ble)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x51a, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

// struct luat_ble_gatt_chara{
//     uint16_t handle;
//     uint8_t uuid[16];
//     luat_ble_uuid_type uuid_type;
//     uint16_t perm;
//     uint16_t max_size;
// };

// typedef struct {
//     uint8_t uuid[16];
//     luat_ble_uuid_type uuid_type;
//     luat_ble_gatt_chara_t* characteristics; // characteristics
//     uint8_t characteristics_num;            // number of characteristics
// }luat_ble_gatt_service_t;

// gatt
int luat_airlink_drv_ble_create_gatt(luat_ble_t* luat_ble, luat_ble_gatt_service_t* luat_ble_gatt_service)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_ble_gatt_chara_t) * luat_ble_gatt_service->characteristics_num + sizeof(luat_ble_gatt_chara_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x51b, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + 8, luat_ble_gatt_service, sizeof(luat_ble_gatt_service_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + sizeof(luat_ble_gatt_service_t) + 8, luat_ble_gatt_service->characteristics, sizeof(luat_ble_gatt_chara_t) * luat_ble_gatt_service->characteristics_num);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

// slaver
int luat_airlink_drv_ble_read_response_value(luat_ble_t* luat_ble, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint32_t len)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x51c, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    uint8_t* p = cmd->data + sizeof(luat_ble_t) + 8;
    p[0] = conn_idx;
    p[1] = service_id;
    p[2] = att_handle;
    p[3] = *data;
    p[4] = len;
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_write_notify_value(luat_ble_t* luat_ble, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint16_t len)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x51d, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    uint8_t* p = cmd->data + sizeof(luat_ble_t) + 8;
    p[0] = conn_idx;
    p[1] = service_id;
    p[2] = att_handle;
    p[3] = *data;
    p[4] = len;
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

// scanning
int luat_airlink_drv_ble_create_scanning(luat_ble_t* luat_ble, luat_ble_scan_cfg_t* scan_cfg)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_ble_scan_cfg_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x51e, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    memcpy(cmd->data + sizeof(luat_ble_t) + 8, scan_cfg, sizeof(luat_ble_scan_cfg_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_start_scanning(luat_ble_t* luat_ble)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x51f, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_stop_scanning(luat_ble_t* luat_ble)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x520, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_ble_delete_scanning(luat_ble_t* luat_ble)
{
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_ble_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x521, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, luat_ble, sizeof(luat_ble_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}
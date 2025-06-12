/*
这个文件是用来实现蓝牙的, 需要代理全部参数给airlink

1. 要把全部函数都实现, 如果不支持的就返回错误
2. 一律打包luat_drv_ble_msg_t

数据传输的数据结构如下:
uint16_t cmd_id; // 蓝牙cmd的id
uint16_t version; // 主机协议版本号, 目前都是0
uint32_t reserved; // 保留字段, 目前都是0
// 然后是命令自身的数据
*/
#include "luat_base.h"
#include "luat_drv_ble.h"
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"

#define LUAT_LOG_TAG "drv.ble"
#include "luat_log.h"

int luat_ble_init(void* args, luat_ble_cb_t luat_ble_cb) {
    LLOGD("执行luat_ble_init");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, 8 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_INIT;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_ble_deinit(void* args) {
    LLOGD("执行luat_ble_deinit");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, 8 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_DEINIT;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_name(void* args, char* name, uint8_t len) {
    LLOGD("执行luat_ble_set_name");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + len + sizeof(uint16_t)
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_SET_NAME;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);
    // 然后是名字长度, 1字节
    memcpy(cmd->data + 8 + 8, &len, 1);
    // 然后是名字
    memcpy(cmd->data + 8 + 8 + 1, name, len);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_max_mtu(void* args, uint16_t max_mtu) {
    LLOGE("not support yet");
    return -1;
}

// advertise
int luat_ble_create_advertising(void* args, luat_ble_adv_cfg_t* adv_cfg) {
    LLOGD("执行luat_ble_create_advertising");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(uint16_t) + sizeof(luat_ble_adv_cfg_t)
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_ADV_CREATE;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);
    // 然后是结构体大小
    uint16_t sizeof_adv = sizeof(luat_ble_adv_cfg_t);
    memcpy(cmd->data + 8 + 8, &sizeof_adv, 2);
    // 然后是数据
    memcpy(cmd->data + 8 + 8 + 2, adv_cfg, sizeof_adv);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_adv_data(void* args, uint8_t* adv_buff, uint8_t adv_len) {
    LLOGD("执行luat_ble_set_adv_data %p %d", adv_buff, adv_len);
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(uint16_t) + adv_len
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_ADV_SET_DATA;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);
    // 然后是结构体大小
    uint16_t datalen = adv_len;
    memcpy(cmd->data + 8 + 8, &datalen, 2);
    // 然后是名字
    memcpy(cmd->data + 8 + 8 + 2, adv_buff, datalen);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_set_scan_rsp_data(void* args, uint8_t* rsp_data, uint8_t rsp_len) {
    LLOGD("执行luat_ble_set_scan_rsp_data %p %d", rsp_data, rsp_len);
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8 + sizeof(uint16_t) + rsp_len
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_ADV_SET_SCAN_RSP_DATA;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);
    // 然后是结构体大小
    uint16_t datalen = rsp_len;
    memcpy(cmd->data + 8 + 8, &datalen, 2);
    // 然后是名字
    memcpy(cmd->data + 8 + 8 + 2, rsp_data, datalen);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_start_advertising(void* args) {
    LLOGD("执行luat_ble_start_advertising");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_ADV_START;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_stop_advertising(void* args) {
    LLOGD("执行luat_ble_start_advertising");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_ADV_STOP;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


int luat_ble_delete_advertising(void* args) {
        LLOGD("执行luat_ble_start_advertising");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_ADV_START;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}


// gatt
int luat_ble_create_gatt(void* args, luat_ble_gatt_service_t* gatt) {
    LLOGD("执行luat_ble_create_gatt");
    uint16_t tmp = 0;
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) 
               + 8 + sizeof(luat_ble_gatt_service_t) 
               + gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t)
               + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8] = {0};
     // 前2个字节是蓝牙cmd id
    uint16_t id = LUAT_DRV_BT_CMD_BLE_GATT_CREATE;
    memcpy(data, &id, 2);
    // 然后2个字节的主机协议版本号, 当前全是0
    // 剩余4个字节做预留

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);
    
    // 数据部分
    // 首先是luat_ble_gatt_service_t结构的大小
    tmp = sizeof(luat_ble_gatt_service_t);
    memcpy(cmd->data + 8 + 8, &tmp, 2);
    // 然后是luat_ble_gatt_chara_t的大小
    tmp = sizeof(luat_ble_gatt_chara_t);
    memcpy(cmd->data + 8 + 8 + 2, &tmp, 2);
    // 然后是服务id的数量
    tmp = gatt->characteristics_num;
    memcpy(cmd->data + 8 + 8 + 2 + 2, &tmp, 2);

    // 头部拷贝完成, 拷贝数据
    memcpy(cmd->data + 8 + 8 + 2 + 2 + 2, gatt, sizeof(luat_ble_gatt_service_t));
    // 然后是服务id
    memcpy(cmd->data + 8 + 8 + 2 + 2 + 2 + sizeof(luat_ble_gatt_service_t), 
        gatt->characteristics, gatt->characteristics_num * sizeof(luat_ble_gatt_chara_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

// slaver
int luat_ble_read_response_value(void* args, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint32_t len) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_write_notify_value(void* args, uint8_t conn_idx, uint16_t service_id, uint16_t att_handle, uint8_t *data, uint16_t len) {
    LLOGE("not support yet");
    return -1;
}


// scanning
int luat_ble_create_scanning(void* args, luat_ble_scan_cfg_t* scan_cfg) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_start_scanning(void* args) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_stop_scanning(void* args) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_delete_scanning(void* args) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_connect(void* args, uint8_t* adv_addr,uint8_t adv_addr_type) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_disconnect(void* args, uint8_t conn_idx) {
    LLOGE("not support yet");
    return -1;
}

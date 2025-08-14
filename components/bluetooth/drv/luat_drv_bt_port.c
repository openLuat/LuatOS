/*
这个文件是用来实现蓝牙的, 需要代理全部参数给airlink

1. 要把全部函数都实现, 如果不支持的就返回错误
2. 一律打包luat_drv_ble_msg_t
*/
#include "luat_base.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"
#include "luat_drv_ble.h"
#include "luat_airlink.h"

#define LUAT_LOG_TAG "drv.bt"
#include "luat_log.h"

extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

int luat_bluetooth_init(void* args) {
    LLOGD("执行luat_bluetooth_init");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + sizeof(luat_drv_ble_msg_t)
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = luat_airlink_next_cmd_id};
    msg.cmd_id = LUAT_DRV_BT_CMD_BT_INIT;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_bluetooth_deinit(void* args) {
    LLOGD("执行luat_bluetooth_deinit");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + sizeof(luat_drv_ble_msg_t)
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, item.len - sizeof(luat_airlink_cmd_t));
    if (cmd == NULL) {
        return -101;
    }
    luat_drv_ble_msg_t msg = { .id = luat_airlink_next_cmd_id};
    msg.cmd_id = LUAT_DRV_BT_CMD_BT_DEINIT;
    memcpy(cmd->data, &msg, sizeof(luat_drv_ble_msg_t));

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_bluetooth_get_mac(void* args, uint8_t *addr) {
    memcpy(addr, g_airlink_ext_dev_info.wifi.bt_mac, 6);
    // 注意, 因为bt_mac是大端存储的, 需要转换成小端
    // 而按照luat_bluetooth_get_mac的定义, 返回的是小端格式
    luat_bluetooth_mac_swap(addr);
    return 0;
}

int luat_bluetooth_set_mac(void* args, uint8_t *addr, uint8_t len) {
    LLOGE("not support yet");
    return -1;
}



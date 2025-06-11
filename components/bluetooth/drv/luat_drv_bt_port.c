/*
这个文件是用来实现蓝牙的, 需要代理全部参数给airlink

1. 要把全部函数都实现, 如果不支持的就返回错误
2. 一律打包luat_drv_ble_msg_t
*/
#include "luat_base.h"
#include "luat_drv_ble.h"
#include "luat_airlink.h"

#define LUAT_LOG_TAG "drv.bt"
#include "luat_log.h"

extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

int luat_bluetooth_init(void* args) {
    LLOGD("执行luat_bluetooth_init");
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 8 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x500, sizeof(uint8_t) + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t data[8];
    // 前2个字节是蓝牙cmd id
    data[0] = 0;
    data[1] = 0;
    // 然后2个字节的主机协议版本号, 当前全是0

    // 这个指令当没有参数, 加4个字节备用吧

    // 全部拷贝过去
    memcpy(cmd->data + 8, data, 8);

    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_bluetooth_deinit(void* args) {
    LLOGE("not support yet");
    return -1;
}

int luat_bluetooth_get_mac(void* args, uint8_t *addr) {
    memcpy(addr, g_airlink_ext_dev_info.wifi.bt_mac, 6);
    return 0;
}

int luat_bluetooth_set_mac(void* args, uint8_t *addr, uint8_t len) {
    LLOGE("not support yet");
    return -1;
}



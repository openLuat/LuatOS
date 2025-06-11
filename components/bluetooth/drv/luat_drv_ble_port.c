/*
这个文件是用来实现蓝牙的, 需要代理全部参数给airlink

1. 要把全部函数都实现, 如果不支持的就返回错误
2. 一律打包luat_drv_ble_msg_t
*/
#include "luat_base.h"
#include "luat_drv_ble.h"
#include "luat_airlink.h"
#include "luat_bluetooth.h"
#include "luat_ble.h"

#define LUAT_LOG_TAG "drv.ble"
#include "luat_log.h"

int luat_ble_init(void* args, luat_ble_cb_t luat_ble_cb) {
    LLOGE("not support yet");
    return -1;
}

int luat_ble_deinit(void* args) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_set_name(void* args, char* name, uint8_t len) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_set_max_mtu(void* args, uint16_t max_mtu) {
    LLOGE("not support yet");
    return -1;
}

// advertise
int luat_ble_create_advertising(void* args, luat_ble_adv_cfg_t* adv_cfg) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_set_adv_data(void* args, uint8_t* adv_buff, uint8_t adv_len) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_set_scan_rsp_data(void* args, uint8_t* rsp_data, uint8_t rsp_len) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_start_advertising(void* args) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_stop_advertising(void* args) {
    LLOGE("not support yet");
    return -1;
}


int luat_ble_delete_advertising(void* args) {
    LLOGE("not support yet");
    return -1;
}


// gatt
int luat_ble_create_gatt(void* args, luat_ble_gatt_service_t* luat_ble_gatt_service) {
    LLOGE("not support yet");
    return -1;
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

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"


#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_wlan.h"

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

int luat_airlink_drv_wlan_init(luat_wlan_config_t* args) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x200, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_wlan_ap_start(luat_wlan_apinfo_t* info) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_wlan_apinfo_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x203, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, info, sizeof(luat_wlan_apinfo_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
};


int luat_airlink_drv_wlan_ap_stop(void) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x204, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_wlan_init(luat_wlan_config_t *conf);

int luat_airlink_drv_wlan_mode(luat_wlan_config_t *conf);

int luat_airlink_drv_wlan_ready(void);

int luat_airlink_drv_wlan_connect(luat_wlan_conninfo_t* info) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_wlan_conninfo_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x201, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, info, sizeof(luat_wlan_conninfo_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_wlan_disconnect(void) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x202, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_wlan_scan(void) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x205, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

uint8_t drv_scan_result_size = 0;
uint8_t *drv_scan_result;
int luat_airlink_drv_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit) {
    if (drv_scan_result == NULL || drv_scan_result_size == 0) {
        return 0;
    }
    if (ap_limit > drv_scan_result_size) {
        ap_limit = drv_scan_result_size;
    }
    memcpy(results, drv_scan_result, ap_limit * sizeof(luat_wlan_scan_result_t));
    return ap_limit;
}

int luat_airlink_drv_wlan_set_station_ip(luat_wlan_station_info_t *info);

int luat_airlink_drv_wlan_smartconfig_start(int tp);

int luat_airlink_drv_wlan_smartconfig_stop(void);

// 数据类
int luat_airlink_drv_wlan_get_mac(int id, char* mac);

int luat_airlink_drv_wlan_set_mac(int id, const char* mac)
{
    uint8_t c_id = id;
    
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8 + 6
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x207, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    // LLOGE("未传递之前 id = %d, mac = %02X%02X%02X%02X%02X%02X", c_id, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &c_id, 1);
    memcpy(cmd->data + 9, mac, 6);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_wlan_get_ip(int type, char* data);

const char* luat_airlink_drv_wlan_get_hostname(int id);

int luat_airlink_drv_wlan_set_hostname(int id, const char* hostname);

// 设置和获取省电模式
int luat_airlink_drv_wlan_set_ps(int mode)
{
    uint8_t c_mode = mode;

    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8 + 1
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x208, item.len) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &c_mode, 1);
    
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_wlan_get_ps(void);

int luat_airlink_drv_wlan_get_ap_bssid(char* buff);

int luat_airlink_drv_wlan_get_ap_rssi(void);

int luat_airlink_drv_wlan_get_ap_gateway(char* buff);


int luat_airlink_drv_wlan_scan_result_cb(void) {
    #define MAX_SCAN_RESULT_SIZE 33
    #define MAX_SCAN_RESULT_BUFF_SIZE (sizeof(luat_wlan_scan_result_t) * MAX_SCAN_RESULT_SIZE)
    size_t fulllen = sizeof(luat_airlink_cmd_t) + 1 + MAX_SCAN_RESULT_BUFF_SIZE;
    uint8_t* ptr = luat_heap_opt_zalloc(AIRLINK_MEM_TYPE, fulllen);
    if (ptr == NULL) {
        LLOGD("内存不足, 无法发送扫描结果");
        return -1;
    }
    luat_wlan_scan_result_t *scan_result = ptr + sizeof(luat_airlink_cmd_t) + 1;

    luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = fulllen,
        .cmd = ptr
    };
    item.cmd->cmd = 0x206;
    item.cmd->len = 1 + MAX_SCAN_RESULT_BUFF_SIZE;
    item.cmd->data[0] = (uint8_t)luat_wlan_scan_get_result(scan_result, MAX_SCAN_RESULT_SIZE);;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);

    return 0;
}
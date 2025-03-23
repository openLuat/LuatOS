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

int luat_airlink_drv_wlan_connect(luat_wlan_conninfo_t* info);

int luat_airlink_drv_wlan_disconnect(void);

int luat_airlink_drv_wlan_scan(void);

int luat_airlink_drv_wlan_scan_get_result(luat_wlan_scan_result_t *results, size_t ap_limit);

int luat_airlink_drv_wlan_set_station_ip(luat_wlan_station_info_t *info);

int luat_airlink_drv_wlan_smartconfig_start(int tp);

int luat_airlink_drv_wlan_smartconfig_stop(void);

// 数据类
int luat_airlink_drv_wlan_get_mac(int id, char* mac);
int luat_airlink_drv_wlan_set_mac(int id, const char* mac);

int luat_airlink_drv_wlan_get_ip(int type, char* data);

const char* luat_airlink_drv_wlan_get_hostname(int id);

int luat_airlink_drv_wlan_set_hostname(int id, const char* hostname);

// 设置和获取省电模式
int luat_airlink_drv_wlan_set_ps(int mode);

int luat_airlink_drv_wlan_get_ps(void);

int luat_airlink_drv_wlan_get_ap_bssid(char* buff);

int luat_airlink_drv_wlan_get_ap_rssi(void);

int luat_airlink_drv_wlan_get_ap_gateway(char* buff);



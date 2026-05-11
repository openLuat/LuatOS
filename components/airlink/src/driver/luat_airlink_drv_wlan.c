#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_wlan.h"
#include <string.h>

#ifdef LUAT_USE_AIRLINK_RPC
#include "luat_airlink_rpc.h"
#include "drv_wlan.pb.h"
#endif

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

luat_airlink_wlan_evt_cb g_airlink_wlan_evt_cb;
extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

int luat_airlink_drv_wlan_init(luat_wlan_config_t* args) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x200, 8) ;
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
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x203, sizeof(luat_wlan_apinfo_t) + 8) ;
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
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x204, 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_wlan_connect(luat_wlan_conninfo_t* info) {
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_wlan_conninfo_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x201, sizeof(luat_wlan_conninfo_t) + 8) ;
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
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x202, 8) ;
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
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x205, 8) ;
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
        .len = sizeof(luat_airlink_cmd_t) + 8 + 1 + 6
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x207, 8 + 1 + 6) ;
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
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x208, 8 + 1) ;
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

#ifdef LUAT_USE_AIRLINK_RPC
    /* 优先尝试 RPC NOTIFY 发送扫描结果 */
    {
        int mode = luat_airlink_current_mode_get();
        if (mode >= 0) {
            uint8_t* scan_buf = (uint8_t*)luat_heap_opt_malloc(AIRLINK_MEM_TYPE, MAX_SCAN_RESULT_BUFF_SIZE);
            if (scan_buf != NULL) {
                drv_wlan_WlanScanResultNotify notify = drv_wlan_WlanScanResultNotify_init_zero;
                notify.count = (uint32_t)luat_wlan_scan_get_result(
                    (luat_wlan_scan_result_t*)scan_buf, MAX_SCAN_RESULT_SIZE);
                if (notify.count > 0) {
                    notify.data.size = (pb_size_t)(notify.count * sizeof(luat_wlan_scan_result_t));
                    memcpy(notify.data.bytes, scan_buf, notify.data.size);
                }
                luat_heap_opt_free(AIRLINK_MEM_TYPE, scan_buf);

                int rc = luat_airlink_rpc_nb_notify((uint8_t)mode, 0x0301,
                                                     drv_wlan_WlanScanResultNotify_fields, &notify);
                if (rc == 0) {
                    LLOGD("扫描结果通过 RPC NOTIFY 发送 count=%d", (int)notify.count);
                    return 0;
                }
                LLOGD("RPC NOTIFY 失败 rc=%d, 回退到 raw cmd", rc);
            }
        }
    }
#endif

    /* 原始 raw cmd 0x206 回退 */
    {
        size_t fulllen = sizeof(luat_airlink_cmd_t) + 1 + MAX_SCAN_RESULT_BUFF_SIZE;
        uint8_t* ptr = luat_heap_opt_zalloc(AIRLINK_MEM_TYPE, fulllen);
        if (ptr == NULL) {
            LLOGD("内存不足, 无法发送扫描结果");
            return -1;
        }
        luat_wlan_scan_result_t *scan_result = (luat_wlan_scan_result_t*)(ptr + sizeof(luat_airlink_cmd_t) + 1);

        luat_airlink_get_next_cmd_id();
        airlink_queue_item_t item = {
            .len = fulllen,
            .cmd = (luat_airlink_cmd_t*)ptr
        };
        item.cmd->cmd = 0x206;
        item.cmd->len = 1 + MAX_SCAN_RESULT_BUFF_SIZE;
        item.cmd->data[0] = (uint8_t)luat_wlan_scan_get_result(scan_result, MAX_SCAN_RESULT_SIZE);
        luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    }

    return 0;
}

#ifdef LUAT_USE_AIRLINK_RPC
void luat_airlink_drv_wlan_sta_connected_cb(const char* ssid, const uint8_t* bssid) {
    int mode = luat_airlink_current_mode_get();
    if (mode < 0) return;
    drv_wlan_WlanStaIncNotify notify = drv_wlan_WlanStaIncNotify_init_zero;
    strncpy(notify.event, "CONNECTED", sizeof(notify.event) - 1);
    if (ssid) {
        notify.has_ssid = true;
        strncpy(notify.ssid, ssid, sizeof(notify.ssid) - 1);
    }
    if (bssid) {
        notify.has_bssid = true;
        notify.bssid.size = 6;
        memcpy(notify.bssid.bytes, bssid, 6);
    }
    luat_airlink_rpc_nb_notify((uint8_t)mode, 0x0302,
                                drv_wlan_WlanStaIncNotify_fields, &notify);
}

void luat_airlink_drv_wlan_sta_disconnected_cb(uint32_t reason) {
    int mode = luat_airlink_current_mode_get();
    if (mode < 0) return;
    drv_wlan_WlanStaIncNotify notify = drv_wlan_WlanStaIncNotify_init_zero;
    strncpy(notify.event, "DISCONNECTED", sizeof(notify.event) - 1);
    notify.has_reason = true;
    notify.reason = reason;
    luat_airlink_rpc_nb_notify((uint8_t)mode, 0x0302,
                                drv_wlan_WlanStaIncNotify_fields, &notify);
}

void luat_airlink_drv_wlan_ip_ready_cb(const char* ip, uint32_t adapter) {
    int mode = luat_airlink_current_mode_get();
    if (mode < 0) return;
    drv_wlan_WlanIpReadyNotify notify = drv_wlan_WlanIpReadyNotify_init_zero;
    if (ip) {
        notify.has_ip = true;
        strncpy(notify.ip, ip, sizeof(notify.ip) - 1);
    }
    notify.has_adapter = true;
    notify.adapter = adapter;
    luat_airlink_rpc_nb_notify((uint8_t)mode, 0x0303,
                                drv_wlan_WlanIpReadyNotify_fields, &notify);
}

void luat_airlink_drv_wlan_ap_connected_cb(const uint8_t* mac) {
    int mode = luat_airlink_current_mode_get();
    if (mode < 0) return;
    drv_wlan_WlanApIncNotify notify = drv_wlan_WlanApIncNotify_init_zero;
    strncpy(notify.event, "CONNECTED", sizeof(notify.event) - 1);
    if (mac) {
        notify.has_mac = true;
        notify.mac.size = 6;
        memcpy(notify.mac.bytes, mac, 6);
    }
    luat_airlink_rpc_nb_notify((uint8_t)mode, 0x0304,
                                drv_wlan_WlanApIncNotify_fields, &notify);
}

void luat_airlink_drv_wlan_ap_disconnected_cb(const uint8_t* mac) {
    int mode = luat_airlink_current_mode_get();
    if (mode < 0) return;
    drv_wlan_WlanApIncNotify notify = drv_wlan_WlanApIncNotify_init_zero;
    strncpy(notify.event, "DISCONNECTED", sizeof(notify.event) - 1);
    if (mac) {
        notify.has_mac = true;
        notify.mac.size = 6;
        memcpy(notify.mac.bytes, mac, 6);
    }
    luat_airlink_rpc_nb_notify((uint8_t)mode, 0x0304,
                                drv_wlan_WlanApIncNotify_fields, &notify);
}
#endif

extern void luat_airlink_devinfo_init(AIRLINK_DEV_INFO_UPDATE_CB cb);
int luat_airlink_drv_devinfo_init(AIRLINK_DEV_INFO_UPDATE_CB cb) {
    luat_airlink_devinfo_init(cb);
    return 0;
}

int luat_airlink_wlan_event_callback(void *arg, luat_event_module_t event_module, int event_id, void *event_data) {
	if (g_airlink_wlan_evt_cb) {
		g_airlink_wlan_evt_cb(arg, event_module, event_id, event_data);
	}
    return 0;
}

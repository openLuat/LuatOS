#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_wlan.h"
#include "drv_wlan.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

#define AIRLINK_DRV_RPC_ID_WLAN  0x0300

luat_airlink_wlan_evt_cb g_airlink_wlan_evt_cb;
extern luat_airlink_dev_info_t g_airlink_ext_dev_info;

// 检查 WLAN RPC 响应中的 result 字段，返回 0=OK，负值=失败
static int wlan_result_check(bool has_code, drv_wlan_WlanResultCode code, int32_t os_errno) {
    if (!has_code) return 0;
    if (code == drv_wlan_WlanResultCode_WLAN_RES_OK) return 0;
    return os_errno != 0 ? os_errno : (int)code;
}

int luat_airlink_drv_wlan_init(luat_wlan_config_t* args) {
    #ifdef LUAT_USE_AIRLINK_RPC_WLAN
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_init_tag;
        if (args) {
            req.payload.init.has_mode = true;
            req.payload.init.mode     = args->mode;
        }
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_WLAN,
                                          drv_wlan_WlanRpcRequest_fields,  &req,
                                          drv_wlan_WlanRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_wlan_WlanRpcResponse_init_tag) return -10;
        return wlan_result_check(resp.payload.init.result.has_code,
                                 resp.payload.init.result.code,
                                 resp.payload.init.result.os_errno);
    }
    #endif
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
    #ifdef LUAT_USE_AIRLINK_RPC_WLAN
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_ap_start_tag;
        strncpy(req.payload.ap_start.ssid, info->ssid, sizeof(req.payload.ap_start.ssid) - 1);
        if (info->password[0] != '\0') {
            req.payload.ap_start.has_password = true;
            strncpy(req.payload.ap_start.password, info->password,
                    sizeof(req.payload.ap_start.password) - 1);
        }
        req.payload.ap_start.has_channel  = true;
        req.payload.ap_start.channel      = info->channel;
        req.payload.ap_start.has_encrypt  = true;
        req.payload.ap_start.encrypt      = info->encrypt;
        req.payload.ap_start.has_hidden   = true;
        req.payload.ap_start.hidden       = (info->hidden != 0);
        req.payload.ap_start.has_max_conn = true;
        req.payload.ap_start.max_conn     = info->max_conn;
        req.payload.ap_start.has_gateway  = true;
        req.payload.ap_start.gateway.size = 4;
        memcpy(req.payload.ap_start.gateway.bytes, info->gateway, 4);
        req.payload.ap_start.has_netmask  = true;
        req.payload.ap_start.netmask.size = 4;
        memcpy(req.payload.ap_start.netmask.bytes, info->netmask, 4);
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_WLAN,
                                          drv_wlan_WlanRpcRequest_fields,  &req,
                                          drv_wlan_WlanRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_wlan_WlanRpcResponse_ap_start_tag) return -10;
        return wlan_result_check(resp.payload.ap_start.result.has_code,
                                 resp.payload.ap_start.result.code,
                                 resp.payload.ap_start.result.os_errno);
    }
    #endif
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
    #ifdef LUAT_USE_AIRLINK_RPC_WLAN
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_ap_stop_tag;
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_WLAN,
                                          drv_wlan_WlanRpcRequest_fields,  &req,
                                          drv_wlan_WlanRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_wlan_WlanRpcResponse_ap_stop_tag) return -10;
        return wlan_result_check(resp.payload.ap_stop.result.has_code,
                                 resp.payload.ap_stop.result.code,
                                 resp.payload.ap_stop.result.os_errno);
    }
    #endif
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
    #ifdef LUAT_USE_AIRLINK_RPC_WLAN
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_connect_tag;
        strncpy(req.payload.connect.ssid, info->ssid, sizeof(req.payload.connect.ssid) - 1);
        if (info->password[0] != '\0') {
            req.payload.connect.has_password = true;
            strncpy(req.payload.connect.password, info->password,
                    sizeof(req.payload.connect.password) - 1);
        }
        // bssid: proto max_size=6 (MAC), copy 6 bytes from conninfo bssid[8]
        bool bssid_nonzero = false;
        for (int i = 0; i < 6; i++) {
            if (info->bssid[i]) { bssid_nonzero = true; break; }
        }
        if (bssid_nonzero) {
            req.payload.connect.has_bssid    = true;
            req.payload.connect.bssid.size   = 6;
            memcpy(req.payload.connect.bssid.bytes, info->bssid, 6);
        }
        req.payload.connect.has_authmode = true;
        req.payload.connect.authmode     = info->authmode;
        req.payload.connect.has_auto_reconnection = true;
        req.payload.connect.auto_reconnection     = (info->auto_reconnection != 0);
        req.payload.connect.has_auto_reconnection_delay_sec = true;
        req.payload.connect.auto_reconnection_delay_sec     = info->auto_reconnection_delay_sec;
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_WLAN,
                                          drv_wlan_WlanRpcRequest_fields,  &req,
                                          drv_wlan_WlanRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_wlan_WlanRpcResponse_connect_tag) return -10;
        return wlan_result_check(resp.payload.connect.result.has_code,
                                 resp.payload.connect.result.code,
                                 resp.payload.connect.result.os_errno);
    }
    #endif
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
    #ifdef LUAT_USE_AIRLINK_RPC_WLAN
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_disconnect_tag;
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_WLAN,
                                          drv_wlan_WlanRpcRequest_fields,  &req,
                                          drv_wlan_WlanRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_wlan_WlanRpcResponse_disconnect_tag) return -10;
        return wlan_result_check(resp.payload.disconnect.result.has_code,
                                 resp.payload.disconnect.result.code,
                                 resp.payload.disconnect.result.os_errno);
    }
    #endif
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
    #ifdef LUAT_USE_AIRLINK_RPC_WLAN
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
        drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
        req.which_payload = drv_wlan_WlanRpcRequest_scan_tag;
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_WLAN,
                                          drv_wlan_WlanRpcRequest_fields,  &req,
                                          drv_wlan_WlanRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_wlan_WlanRpcResponse_scan_tag) return -10;
        return wlan_result_check(resp.payload.scan.result.has_code,
                                 resp.payload.scan.result.code,
                                 resp.payload.scan.result.os_errno);
    }
    #endif
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

#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && defined(LUAT_USE_DRV_WLAN)

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_wlan.h"
#include "luat_mem.h"
#include "drv_wlan.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

#define AIRLINK_DRV_RPC_ID_WLAN  0x0300

static int wlan_result_check(bool has_code, drv_wlan_WlanResultCode code, int32_t os_errno) {
    if (!has_code) return 0;
    if (code == drv_wlan_WlanResultCode_WLAN_RES_OK) return 0;
    return os_errno != 0 ? os_errno : (int)code;
}

int luat_airlink_drv_rpc_wlan_init(luat_wlan_config_t* args) {
    int mode = luat_airlink_current_mode_get();
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

int luat_airlink_drv_rpc_wlan_ap_start(luat_wlan_apinfo_t* info) {
    int mode = luat_airlink_current_mode_get();
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

int luat_airlink_drv_rpc_wlan_ap_stop(void) {
    int mode = luat_airlink_current_mode_get();
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

int luat_airlink_drv_rpc_wlan_connect(luat_wlan_conninfo_t* info) {
    int mode = luat_airlink_current_mode_get();
    drv_wlan_WlanRpcRequest  req  = drv_wlan_WlanRpcRequest_init_zero;
    drv_wlan_WlanRpcResponse resp = drv_wlan_WlanRpcResponse_init_zero;
    req.which_payload = drv_wlan_WlanRpcRequest_connect_tag;
    strncpy(req.payload.connect.ssid, info->ssid, sizeof(req.payload.connect.ssid) - 1);
    if (info->password[0] != '\0') {
        req.payload.connect.has_password = true;
        strncpy(req.payload.connect.password, info->password,
                sizeof(req.payload.connect.password) - 1);
    }
    bool bssid_nonzero = false;
    for (int i = 0; i < 6; i++) {
        if (info->bssid[i]) { bssid_nonzero = true; break; }
    }
    if (bssid_nonzero) {
        req.payload.connect.has_bssid  = true;
        req.payload.connect.bssid.size = 6;
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

int luat_airlink_drv_rpc_wlan_disconnect(void) {
    int mode = luat_airlink_current_mode_get();
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

int luat_airlink_drv_rpc_wlan_scan(void) {
    int mode = luat_airlink_current_mode_get();
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

#endif /* LUAT_USE_AIRLINK_RPC_WLAN */

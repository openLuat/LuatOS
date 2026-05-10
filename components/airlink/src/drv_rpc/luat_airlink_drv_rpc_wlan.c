#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && defined(LUAT_USE_DRV_WLAN)

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_wlan.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include "drv_wlan.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...)

#define AIRLINK_DRV_RPC_ID_WLAN       0x0300
#define AIRLINK_DRV_RPC_ID_WLAN_EVENT 0x0301
#define AIRLINK_DRV_RPC_ID_WLAN_STA_EVENT 0x0302
#define AIRLINK_DRV_RPC_ID_WLAN_IP_EVENT  0x0303
#define AIRLINK_DRV_RPC_ID_WLAN_AP_EVENT  0x0304

/* 扫描结果缓存 (供 luat_airlink_drv_wlan_scan_get_result 读取) */
extern uint8_t  drv_scan_result_size;
extern uint8_t *drv_scan_result;

/* 声明 exec_rpc 文件中的 setter */
typedef void (*wlan_event_notify_fn_t)(uint16_t rpc_id, const void* msg, void* userdata);
extern void luat_airlink_rpc_wlan_set_event_notify_fn(wlan_event_notify_fn_t fn);

/* 懒注册：确保 NOTIFY 回调只注册一次，不依赖 init 是否被调用 */
static bool s_wlan_notify_registered = false;
static void wlan_rpc_notify_dispatch(uint16_t rpc_id, const void* msg_raw, void* userdata);
static void wlan_notify_ensure_registered(void) {
    if (!s_wlan_notify_registered) {
        s_wlan_notify_registered = true;
        luat_airlink_rpc_wlan_set_event_notify_fn(wlan_rpc_notify_dispatch);
    }
}

/* msgbus 扫描完成通知 (与 exec/luat_airlink_cmd_exec_wlan.c 中的 scan_result_handler 一致) */
static int wlan_scan_result_handler(lua_State* L, void* ptr) {
    (void)ptr;
    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "WLAN_SCAN_DONE");
    lua_call(L, 1, 0);
    return 0;
}

/* msgbus STA 事件通知 (WLAN_STA_INC) */
struct wlan_sta_inc_ctx {
    char event[16];
    char ssid[36];
    uint8_t bssid[6];
    bool has_bssid;
    uint32_t reason;
    bool has_reason;
};

static int wlan_sta_inc_handler(lua_State* L, void* ptr) {
    struct wlan_sta_inc_ctx* ctx = (struct wlan_sta_inc_ctx*)ptr;
    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "WLAN_STA_INC");
    lua_pushstring(L, ctx->event);
    if (strcmp(ctx->event, "CONNECTED") == 0) {
        lua_pushstring(L, ctx->ssid);
        if (ctx->has_bssid) {
            lua_pushlstring(L, (const char*)ctx->bssid, 6);
        } else {
            lua_pushstring(L, "");
        }
        lua_call(L, 4, 0);
    } else {
        lua_pushinteger(L, (lua_Integer)ctx->reason);
        lua_call(L, 3, 0);
    }
    luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx);
    return 0;
}

/* msgbus IP 就绪通知 (IP_READY) */
struct wlan_ip_ready_ctx {
    char ip[16];
    uint32_t adapter;
};

static int wlan_ip_ready_handler(lua_State* L, void* ptr) {
    struct wlan_ip_ready_ctx* ctx = (struct wlan_ip_ready_ctx*)ptr;
    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "IP_READY");
    lua_pushstring(L, ctx->ip);
    lua_pushinteger(L, (lua_Integer)ctx->adapter);
    lua_call(L, 3, 0);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx);
    return 0;
}

/* msgbus AP 热点事件通知 (WLAN_AP_INC) */
struct wlan_ap_inc_ctx {
    char event[16];
    uint8_t mac[6];
    bool has_mac;
};

static int wlan_ap_inc_handler(lua_State* L, void* ptr) {
    struct wlan_ap_inc_ctx* ctx = (struct wlan_ap_inc_ctx*)ptr;
    lua_getglobal(L, "sys_pub");
    lua_pushstring(L, "WLAN_AP_INC");
    lua_pushstring(L, ctx->event);
    if (ctx->has_mac) {
        lua_pushlstring(L, (const char*)ctx->mac, 6);
    } else {
        lua_pushstring(L, "");
    }
    lua_call(L, 3, 0);
    luat_heap_opt_free(AIRLINK_MEM_TYPE, ctx);
    return 0;
}

/* 统一 WLAN NOTIFY 接收处理器 (由 nb_dispatch 在收到 0x0301/0x0302/0x0303/0x0304 NOTIFY 时调用) */
static void wlan_rpc_notify_dispatch(uint16_t rpc_id, const void* msg_raw, void* userdata) {
    (void)userdata;

    switch (rpc_id) {
    case AIRLINK_DRV_RPC_ID_WLAN_EVENT: {
        const drv_wlan_WlanScanResultNotify* notify = (const drv_wlan_WlanScanResultNotify*)msg_raw;

        if (drv_scan_result) {
            luat_heap_opt_free(AIRLINK_MEM_TYPE, drv_scan_result);
            drv_scan_result = NULL;
            drv_scan_result_size = 0;
        }

        if (notify->count > 0 && notify->data.size > 0) {
            size_t sz = notify->count * sizeof(luat_wlan_scan_result_t);
            if (sz > notify->data.size) sz = notify->data.size;
            drv_scan_result = (uint8_t*)luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sz);
            if (drv_scan_result) {
                memcpy(drv_scan_result, notify->data.bytes, sz);
                drv_scan_result_size = (uint8_t)notify->count;
            }
        }

        rtos_msg_t msg = {0};
        msg.handler = wlan_scan_result_handler;
        luat_msgbus_put(&msg, 0);
        break;
    }
    case AIRLINK_DRV_RPC_ID_WLAN_STA_EVENT: {
        const drv_wlan_WlanStaIncNotify* notify = (const drv_wlan_WlanStaIncNotify*)msg_raw;
        struct wlan_sta_inc_ctx* ctx = (struct wlan_sta_inc_ctx*)luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(struct wlan_sta_inc_ctx));
        if (!ctx) return;
        memset(ctx, 0, sizeof(*ctx));
        strncpy(ctx->event, notify->event, sizeof(ctx->event) - 1);
        if (notify->has_ssid) {
            strncpy(ctx->ssid, notify->ssid, sizeof(ctx->ssid) - 1);
        }
        if (notify->has_bssid && notify->bssid.size >= 6) {
            ctx->has_bssid = true;
            memcpy(ctx->bssid, notify->bssid.bytes, 6);
        }
        if (notify->has_reason) {
            ctx->has_reason = true;
            ctx->reason = notify->reason;
        }
        rtos_msg_t msg = {0};
        msg.handler = wlan_sta_inc_handler;
        msg.ptr = ctx;
        luat_msgbus_put(&msg, 0);
        break;
    }
    case AIRLINK_DRV_RPC_ID_WLAN_IP_EVENT: {
        const drv_wlan_WlanIpReadyNotify* notify = (const drv_wlan_WlanIpReadyNotify*)msg_raw;
        struct wlan_ip_ready_ctx* ctx = (struct wlan_ip_ready_ctx*)luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(struct wlan_ip_ready_ctx));
        if (!ctx) return;
        memset(ctx, 0, sizeof(*ctx));
        if (notify->has_ip) {
            strncpy(ctx->ip, notify->ip, sizeof(ctx->ip) - 1);
        }
        if (notify->has_adapter) {
            ctx->adapter = notify->adapter;
        }
        rtos_msg_t msg = {0};
        msg.handler = wlan_ip_ready_handler;
        msg.ptr = ctx;
        luat_msgbus_put(&msg, 0);
        break;
    }
    case AIRLINK_DRV_RPC_ID_WLAN_AP_EVENT: {
        const drv_wlan_WlanApIncNotify* notify = (const drv_wlan_WlanApIncNotify*)msg_raw;
        struct wlan_ap_inc_ctx* ctx = (struct wlan_ap_inc_ctx*)luat_heap_opt_malloc(AIRLINK_MEM_TYPE, sizeof(struct wlan_ap_inc_ctx));
        if (!ctx) return;
        memset(ctx, 0, sizeof(*ctx));
        strncpy(ctx->event, notify->event, sizeof(ctx->event) - 1);
        if (notify->has_mac && notify->mac.size >= 6) {
            ctx->has_mac = true;
            memcpy(ctx->mac, notify->mac.bytes, 6);
        }
        rtos_msg_t msg = {0};
        msg.handler = wlan_ap_inc_handler;
        msg.ptr = ctx;
        luat_msgbus_put(&msg, 0);
        break;
    }
    default:
        break;
    }
}

static int wlan_result_check(bool has_code, drv_wlan_WlanResultCode code, int32_t os_errno) {
    if (!has_code) return 0;
    if (code == drv_wlan_WlanResultCode_WLAN_RES_OK) return 0;
    return os_errno != 0 ? os_errno : (int)code;
}

int luat_airlink_drv_rpc_wlan_init(luat_wlan_config_t* args) {
    wlan_notify_ensure_registered();
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
    wlan_notify_ensure_registered();
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

/*
 * AirLink WLAN nanopb RPC exec handler (服务端)
 *
 * 将 WlanRpcRequest 分发到对应的 luat_wlan_* 函数，填写 WlanRpcResponse。
 */

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC

#include "luat_airlink_rpc.h"
#include "luat_wlan.h"
#include "drv_wlan.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.rpc.wlan"
#include "luat_log.h"

#define AIRLINK_RPC_ID_WLAN  0x0300

static void set_result_ok(drv_wlan_WlanResult* r) {
    r->has_code = true;
    r->code = drv_wlan_WlanResultCode_WLAN_RES_OK;
}
static void set_result_fail(drv_wlan_WlanResult* r, int os_err) {
    r->has_code = true;
    r->code = drv_wlan_WlanResultCode_WLAN_RES_FAIL;
    r->has_os_errno = true;
    r->os_errno = os_err;
}

static int wlan_rpc_handler(uint16_t rpc_id,
                              const void* req_raw, void* resp_raw,
                              void* userdata) {
    const drv_wlan_WlanRpcRequest* req  = (const drv_wlan_WlanRpcRequest*)req_raw;
    drv_wlan_WlanRpcResponse*      resp = (drv_wlan_WlanRpcResponse*)resp_raw;

    resp->has_req_id = true;
    resp->req_id     = req->req_id;

    switch (req->which_payload) {
    case drv_wlan_WlanRpcRequest_init_tag: {
        int ret = luat_wlan_init(NULL);
        LLOGD("wlan_init ret=%d", ret);
        resp->which_payload = drv_wlan_WlanRpcResponse_init_tag;
        if (ret == 0) set_result_ok(&resp->payload.init.result);
        else          set_result_fail(&resp->payload.init.result, ret);
        break;
    }
    case drv_wlan_WlanRpcRequest_connect_tag: {
        const drv_wlan_WlanConnectRequest* c = &req->payload.connect;
        luat_wlan_conninfo_t info;
        memset(&info, 0, sizeof(info));
        strncpy(info.ssid, c->ssid, sizeof(info.ssid) - 1);
        if (c->has_password) {
            strncpy(info.password, c->password, sizeof(info.password) - 1);
        }
        if (c->has_bssid && c->bssid.size >= 6) {
            memcpy(info.bssid, c->bssid.bytes, 6);
        }
        if (c->has_authmode) {
            info.authmode = c->authmode;
        }
        int ret = luat_wlan_connect(&info);
        LLOGD("wlan_connect ssid=%s ret=%d", info.ssid, ret);
        resp->which_payload = drv_wlan_WlanRpcResponse_connect_tag;
        if (ret == 0) set_result_ok(&resp->payload.connect.result);
        else          set_result_fail(&resp->payload.connect.result, ret);
        break;
    }
    case drv_wlan_WlanRpcRequest_disconnect_tag: {
        int ret = luat_wlan_disconnect();
        LLOGD("wlan_disconnect ret=%d", ret);
        resp->which_payload = drv_wlan_WlanRpcResponse_disconnect_tag;
        if (ret == 0) set_result_ok(&resp->payload.disconnect.result);
        else          set_result_fail(&resp->payload.disconnect.result, ret);
        break;
    }
    case drv_wlan_WlanRpcRequest_ap_start_tag: {
        const drv_wlan_WlanApStartRequest* a = &req->payload.ap_start;
        luat_wlan_apinfo_t apinfo;
        memset(&apinfo, 0, sizeof(apinfo));
        strncpy(apinfo.ssid, a->ssid, sizeof(apinfo.ssid) - 1);
        if (a->has_password) {
            strncpy(apinfo.password, a->password, sizeof(apinfo.password) - 1);
        }
        if (a->has_channel) {
            apinfo.channel = (uint8_t)a->channel;
        }
        if (a->has_encrypt) {
            apinfo.encrypt = (uint8_t)a->encrypt;
        }
        if (a->has_gateway && a->gateway.size >= 4) {
            memcpy(apinfo.gateway, a->gateway.bytes, 4);
        }
        if (a->has_netmask && a->netmask.size >= 4) {
            memcpy(apinfo.netmask, a->netmask.bytes, 4);
        }
        int ret = luat_wlan_ap_start(&apinfo);
        LLOGD("wlan_ap_start ssid=%s ret=%d", apinfo.ssid, ret);
        resp->which_payload = drv_wlan_WlanRpcResponse_ap_start_tag;
        if (ret == 0) set_result_ok(&resp->payload.ap_start.result);
        else          set_result_fail(&resp->payload.ap_start.result, ret);
        break;
    }
    case drv_wlan_WlanRpcRequest_ap_stop_tag: {
        int ret = luat_wlan_ap_stop();
        LLOGD("wlan_ap_stop ret=%d", ret);
        resp->which_payload = drv_wlan_WlanRpcResponse_ap_stop_tag;
        if (ret == 0) set_result_ok(&resp->payload.ap_stop.result);
        else          set_result_fail(&resp->payload.ap_stop.result, ret);
        break;
    }
    case drv_wlan_WlanRpcRequest_scan_tag: {
        int ret = luat_wlan_scan();
        LLOGD("wlan_scan ret=%d", ret);
        resp->which_payload = drv_wlan_WlanRpcResponse_scan_tag;
        if (ret == 0) set_result_ok(&resp->payload.scan.result);
        else          set_result_fail(&resp->payload.scan.result, ret);
        break;
    }
    default:
        LLOGW("wlan_rpc: 未知 which_payload=%d", (int)req->which_payload);
        return -1;
    }
    return 0;
}

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_wlan_reg = {
    .rpc_id         = AIRLINK_RPC_ID_WLAN,
    .active         = 1,
    .req_desc       = drv_wlan_WlanRpcRequest_fields,
    .req_size       = sizeof(drv_wlan_WlanRpcRequest),
    .resp_desc      = drv_wlan_WlanRpcResponse_fields,
    .resp_size      = sizeof(drv_wlan_WlanRpcResponse),
    .handler        = wlan_rpc_handler,
    .notify_handler = NULL,
    .userdata       = NULL,
};

#endif /* LUAT_USE_AIRLINK_RPC */

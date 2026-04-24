/*
 * AirLink PM nanopb RPC exec handler (服务端)
 *
 * 将 PmRpcRequest 分发到对应的 luat_pm_* 函数，填写 PmRpcResponse。
 */

#include "luat_base.h"
#include "luat_airlink_rpc.h"
#include "luat_pm.h"
#include "drv_pm.pb.h"

#define LUAT_LOG_TAG "airlink.rpc.pm"
#include "luat_log.h"

#define AIRLINK_RPC_ID_PM  0x0400

static void set_result_ok(drv_pm_PmResult* r) {
    r->has_code = true;
    r->code = drv_pm_PmResultCode_PM_RES_OK;
}
static void set_result_fail(drv_pm_PmResult* r, int os_err) {
    r->has_code = true;
    r->code = drv_pm_PmResultCode_PM_RES_FAIL;
    r->has_os_errno = true;
    r->os_errno = os_err;
}

static int pm_rpc_handler(uint16_t rpc_id,
                           const void* req_raw, void* resp_raw,
                           void* userdata) {
    const drv_pm_PmRpcRequest* req  = (const drv_pm_PmRpcRequest*)req_raw;
    drv_pm_PmRpcResponse*      resp = (drv_pm_PmRpcResponse*)resp_raw;

    resp->has_req_id = true;
    resp->req_id     = req->req_id;

    switch (req->which_payload) {
    case drv_pm_PmRpcRequest_pm_request_tag: {
        uint32_t mode = req->payload.pm_request.mode;
        int ret = luat_pm_request((int)mode);
        LLOGD("pm_request mode=%u ret=%d", mode, ret);
        resp->which_payload = drv_pm_PmRpcResponse_pm_request_tag;
        if (ret == 0) set_result_ok(&resp->payload.pm_request.result);
        else          set_result_fail(&resp->payload.pm_request.result, ret);
        break;
    }
    case drv_pm_PmRpcRequest_power_ctrl_tag: {
        uint32_t id  = req->payload.power_ctrl.id;
        uint32_t val = req->payload.power_ctrl.val;
        int ret = luat_pm_power_ctrl((int)id, (int)val);
        LLOGD("pm_power_ctrl id=%u val=%u ret=%d", id, val, ret);
        resp->which_payload = drv_pm_PmRpcResponse_power_ctrl_tag;
        if (ret == 0) set_result_ok(&resp->payload.power_ctrl.result);
        else          set_result_fail(&resp->payload.power_ctrl.result, ret);
        break;
    }
    case drv_pm_PmRpcRequest_wakeup_pin_tag: {
        uint32_t pin = req->payload.wakeup_pin.pin;
        uint32_t val = req->payload.wakeup_pin.val;
        int ret = luat_pm_wakeup_pin((int)pin, (int)val);
        LLOGD("pm_wakeup_pin pin=%u val=%u ret=%d", pin, val, ret);
        resp->which_payload = drv_pm_PmRpcResponse_wakeup_pin_tag;
        if (ret == 0) set_result_ok(&resp->payload.wakeup_pin.result);
        else          set_result_fail(&resp->payload.wakeup_pin.result, ret);
        break;
    }
    default:
        LLOGW("pm_rpc: 未知 which_payload=%d", (int)req->which_payload);
        return -1;
    }
    return 0;
}

void luat_airlink_pm_rpc_exec_register(void) {
    luat_airlink_rpc_nb_register(
        AIRLINK_RPC_ID_PM,
        drv_pm_PmRpcRequest_fields,  sizeof(drv_pm_PmRpcRequest),
        drv_pm_PmRpcResponse_fields, sizeof(drv_pm_PmRpcResponse),
        pm_rpc_handler,
        NULL,
        NULL
    );
    LLOGD("PM RPC handler 已注册, rpc_id=0x%04X", AIRLINK_RPC_ID_PM);
}

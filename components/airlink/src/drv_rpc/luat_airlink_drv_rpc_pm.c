#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC_PM

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_mem.h"
#include "drv_pm.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#define AIRLINK_DRV_RPC_ID_PM  0x0400

static int pm_result_check(bool has_code, drv_pm_PmResultCode code, int32_t os_errno) {
    if (!has_code) return 0;
    if (code == drv_pm_PmResultCode_PM_RES_OK) return 0;
    return os_errno != 0 ? os_errno : (int)code;
}

int luat_airlink_drv_rpc_pm_request(int mode) {
    int airlink_mode = luat_airlink_current_mode_get();
    drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
    drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
    req.which_payload           = drv_pm_PmRpcRequest_pm_request_tag;
    req.payload.pm_request.mode = (uint32_t)mode;
    int rc = luat_airlink_rpc_nb_call((uint8_t)airlink_mode, AIRLINK_DRV_RPC_ID_PM,
                                      drv_pm_PmRpcRequest_fields,  &req,
                                      drv_pm_PmRpcResponse_fields, &resp,
                                      2000);
    if (rc != 0) return rc;
    if (resp.which_payload != drv_pm_PmRpcResponse_pm_request_tag) return -10;
    return pm_result_check(resp.payload.pm_request.result.has_code,
                           resp.payload.pm_request.result.code,
                           resp.payload.pm_request.result.os_errno);
}

int luat_airlink_drv_rpc_pm_power_ctrl(int id, uint8_t val) {
    int airlink_mode = luat_airlink_current_mode_get();
    drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
    drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
    req.which_payload          = drv_pm_PmRpcRequest_power_ctrl_tag;
    req.payload.power_ctrl.id  = (uint32_t)id;
    req.payload.power_ctrl.val = (uint32_t)val;
    int rc = luat_airlink_rpc_nb_call((uint8_t)airlink_mode, AIRLINK_DRV_RPC_ID_PM,
                                      drv_pm_PmRpcRequest_fields,  &req,
                                      drv_pm_PmRpcResponse_fields, &resp,
                                      2000);
    if (rc != 0) return rc;
    if (resp.which_payload != drv_pm_PmRpcResponse_power_ctrl_tag) return -10;
    return pm_result_check(resp.payload.power_ctrl.result.has_code,
                           resp.payload.power_ctrl.result.code,
                           resp.payload.power_ctrl.result.os_errno);
}

int luat_airlink_drv_rpc_pm_wakeup_pin(int pin, int val) {
    int airlink_mode = luat_airlink_current_mode_get();
    drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
    drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
    req.which_payload              = drv_pm_PmRpcRequest_wakeup_pin_tag;
    req.payload.wakeup_pin.pin     = (uint32_t)pin;
    req.payload.wakeup_pin.val     = (uint32_t)(val >= 0 ? val : 0);
    int rc = luat_airlink_rpc_nb_call((uint8_t)airlink_mode, AIRLINK_DRV_RPC_ID_PM,
                                      drv_pm_PmRpcRequest_fields,  &req,
                                      drv_pm_PmRpcResponse_fields, &resp,
                                      2000);
    if (rc != 0) return rc;
    if (resp.which_payload != drv_pm_PmRpcResponse_wakeup_pin_tag) return -10;
    return pm_result_check(resp.payload.wakeup_pin.result.has_code,
                           resp.payload.wakeup_pin.result.code,
                           resp.payload.wakeup_pin.result.os_errno);
}

#endif /* LUAT_USE_AIRLINK_RPC_PM */

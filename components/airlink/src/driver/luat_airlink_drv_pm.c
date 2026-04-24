#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_airlink_rpc.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "drv_pm.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink"
#include "luat_log.h"

#undef LLOGD
#define LLOGD(...) 

#define AIRLINK_DRV_RPC_ID_PM  0x0400

// 检查 PM RPC 响应 result，返回 0=OK，负值=失败
static int pm_result_check(bool has_code, drv_pm_PmResultCode code, int32_t os_errno) {
    if (!has_code) return 0;
    if (code == drv_pm_PmResultCode_PM_RES_OK) return 0;
    return os_errno != 0 ? os_errno : (int)code;
}

int luat_airlink_drv_pm_request(int mode) {
    int airlink_mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && airlink_mode >= 0) {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload              = drv_pm_PmRpcRequest_pm_request_tag;
        req.payload.pm_request.mode    = (uint32_t)mode;
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
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(uint8_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x600, sizeof(uint8_t) + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    uint8_t tmp = (uint8_t)mode;
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &tmp, sizeof(uint8_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_pm_power_ctrl(int id, uint8_t val) {
    int airlink_mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && airlink_mode >= 0) {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload              = drv_pm_PmRpcRequest_power_ctrl_tag;
        req.payload.power_ctrl.id      = (uint32_t)id;
        req.payload.power_ctrl.val     = (uint32_t)val;
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
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x601, 5 + 8) ;
    if (cmd == NULL) {
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &id, 4);
    memcpy(cmd->data + 8 + 4, &val, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_pm_wakeup_pin(int pin, int val) {
    int airlink_mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && airlink_mode >= 0) {
        drv_pm_PmRpcRequest  req  = drv_pm_PmRpcRequest_init_zero;
        drv_pm_PmRpcResponse resp = drv_pm_PmRpcResponse_init_zero;
        req.which_payload             = drv_pm_PmRpcRequest_wakeup_pin_tag;
        req.payload.wakeup_pin.pin    = (uint32_t)pin;
        req.payload.wakeup_pin.val    = (uint32_t)(val >= 0 ? val : 0);
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
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = 5 + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x602, 5 + 8) ;
    if (cmd == NULL) {
        return -101;
    }

    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, &pin, 4);
    memcpy(cmd->data + 8 + 4, &val, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}
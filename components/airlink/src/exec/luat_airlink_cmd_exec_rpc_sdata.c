/*
 * luat_airlink_cmd_exec_rpc_sdata.c
 *
 * RPC 服务端处理器 — SDATA 透传 notify (ID 0x0500)
 * 客户端调用 luat_airlink_sdata_send() 发 nb_notify，
 * 服务端收到后解码 SdataNotify 并发布 AIRLINK_SDATA 事件。
 */

#include "luat_base.h"  /* 必须在 #ifdef 之前，以获得 LUAT_USE_AIRLINK_RPC 宏 */

#ifdef LUAT_USE_AIRLINK_RPC
#include "luat_airlink_rpc.h"
#include "drv_sdata.pb.h"

#define LUAT_LOG_TAG "airlink.rpc.sdata"
#include "luat_log.h"

#define AIRLINK_RPC_ID_SDATA  0x0500

extern int luat_airlink_cmd_exec_sdata_data(const uint8_t* data, size_t len);

#ifdef LUAT_USE_AIRLINK_RPC_SDATA

static int sdata_rpc_notify_handler(uint16_t rpc_id, const void* msg_raw, void* userdata) {
    (void)rpc_id; (void)userdata;
    const SdataNotify* msg = (const SdataNotify*)msg_raw;
    return luat_airlink_cmd_exec_sdata_data(msg->data.bytes, msg->data.size);
}

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_sdata_reg = {
    .rpc_id         = AIRLINK_RPC_ID_SDATA,
    .active         = 1,
    .req_desc       = SdataNotify_fields,
    .req_size       = sizeof(SdataNotify),
    .resp_desc      = NULL,
    .resp_size      = 0,
    .handler        = NULL,
    .notify_handler = sdata_rpc_notify_handler,
    .userdata       = NULL,
};

#endif /* LUAT_USE_AIRLINK_RPC_SDATA */
#endif /* LUAT_USE_AIRLINK_RPC */

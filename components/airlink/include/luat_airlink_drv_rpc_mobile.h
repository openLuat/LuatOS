#ifndef LUAT_AIRLINK_DRV_RPC_MOBILE_H
#define LUAT_AIRLINK_DRV_RPC_MOBILE_H

#include "luat_base.h"

#if defined(LUAT_USE_AIRLINK_RPC) && (defined(LUAT_USE_MOBILE) || defined(LUAT_USE_DRV_MOBILE))

#include "luat_airlink.h"
#include "luat_mobile.h"

#define AIRLINK_DRV_RPC_MOBILE_PROTO_ERR        (-10)
#define AIRLINK_DRV_RPC_MOBILE_NOTIFY_EMPTY     (-11)
#define AIRLINK_DRV_RPC_MOBILE_REQID_MISMATCH   (-12)
#define AIRLINK_DRV_RPC_MOBILE_NOTIFY_NO_INFO   (-13)
#define AIRLINK_DRV_RPC_MOBILE_NOT_READY        (-14)

typedef struct {
    char imei[16];
    char imsi[16];
    char iccid[21];
    uint8_t sim_ready;
} luat_airlink_drv_rpc_mobile_sim_identity_status_t;

typedef struct {
    char sn[33];
    char muid[33];
    LUAT_MOBILE_SIM_STATUS_E sim_status;
    LUAT_MOBILE_REGISTER_STATUS_E register_status;
} luat_airlink_drv_rpc_mobile_global_status_t;

typedef struct {
    uint8_t csq;
    luat_mobile_signal_strength_info_t signal;
} luat_airlink_drv_rpc_mobile_signal_info_t;

typedef struct {
    uint32_t earfcn;
    uint32_t pci;
    uint32_t mcc;
    uint32_t mnc;
    uint32_t band;
    uint32_t eci;
    uint32_t cid;
    uint32_t tac;
} luat_airlink_drv_rpc_mobile_scell_extern_info_t;

typedef struct {
    uint32_t earfcn;
    uint32_t pci;
    uint32_t mcc;
    uint32_t mnc;
    uint32_t band;
    uint32_t eci;
    uint32_t cid;
    uint32_t tac;
    int32_t snr;
    int32_t rsrp;
    int32_t rsrq;
    int32_t rssi;
} luat_airlink_drv_rpc_mobile_scell_info_t;

typedef struct {
    int result;
    uint32_t req_id;
    uint8_t sim_id;
    uint8_t has_info;
    luat_mobile_cell_info_t info;
} luat_airlink_drv_rpc_mobile_cell_scan_notify_t;

typedef void (*luat_airlink_drv_rpc_mobile_notify_cb_t)(
    const luat_airlink_drv_rpc_mobile_cell_scan_notify_t* event,
    void* userdata
);

int luat_airlink_drv_rpc_mobile_sim_identity_status(
    uint8_t sim_id,
    luat_airlink_drv_rpc_mobile_sim_identity_status_t* out
);

// lua_yieldk 模式: 挂起协程, 响应到达后由 cont 解码结果
// 调用前必须先确认 lua_isyieldable(L) 为 true
int luat_airlink_drv_rpc_mobile_sim_identity_status_yield(
    lua_State* L, uint8_t sim_id,
    lua_KFunction cont, lua_KContext user_ctx
);

// 解码 sim_identity_status 响应中的 IMEI (供 Lua 包装层 post-yield 调用)
int luat_airlink_drv_rpc_mobile_decode_imei(const uint8_t* raw, uint16_t raw_len,
                                             char* imei, size_t imei_len);
int luat_airlink_drv_rpc_mobile_decode_imsi(const uint8_t* raw, uint16_t raw_len,
                                             char* imsi, size_t imsi_len);
int luat_airlink_drv_rpc_mobile_decode_iccid(const uint8_t* raw, uint16_t raw_len,
                                              char* iccid, size_t iccid_len);

// lua_yieldk 模式: global_status (SN / MUID / register_status)
int luat_airlink_drv_rpc_mobile_global_status_yield(
    lua_State* L, lua_KFunction cont, lua_KContext user_ctx
);
int luat_airlink_drv_rpc_mobile_decode_register_status(const uint8_t* raw, uint16_t raw_len);
int luat_airlink_drv_rpc_mobile_decode_sn(const uint8_t* raw, uint16_t raw_len,
                                           char* sn, size_t sn_len);
int luat_airlink_drv_rpc_mobile_decode_muid(const uint8_t* raw, uint16_t raw_len,
                                             char* muid, size_t muid_len);

// lua_yieldk 模式: signal (CSQ / RSSI / RSRP / RSRQ / SNR)
int luat_airlink_drv_rpc_mobile_signal_yield(
    lua_State* L, lua_KFunction cont, lua_KContext user_ctx
);
int luat_airlink_drv_rpc_mobile_decode_csq(const uint8_t* raw, uint16_t raw_len);
void luat_airlink_drv_rpc_mobile_decode_signal_info(const uint8_t* raw, uint16_t raw_len,
                                                     int16_t* rssi, int16_t* rsrp,
                                                     int16_t* rsrq, int16_t* snr);

int luat_airlink_drv_rpc_mobile_global_status(
    luat_airlink_drv_rpc_mobile_global_status_t* out
);
int luat_airlink_drv_rpc_mobile_signal(
    luat_airlink_drv_rpc_mobile_signal_info_t* out
);
int luat_airlink_drv_rpc_mobile_sync_cell_info(
    luat_mobile_cell_info_t* out
);
int luat_airlink_drv_rpc_mobile_cell_scan(
    uint8_t timeout_sec,
    uint32_t* req_id
);
int luat_airlink_drv_rpc_mobile_scell_extern(
    luat_airlink_drv_rpc_mobile_scell_extern_info_t* out
);

// lua_yieldk 模式: scell_extern (含 eci/cid/tac, 避免后续单独 RPC 调用阻塞)
int luat_airlink_drv_rpc_mobile_scell_extern_yield(
    lua_State* L, lua_KFunction cont, lua_KContext user_ctx
);
// 解码 scell_extern 响应中的 service cell 信息
int luat_airlink_drv_rpc_mobile_decode_scell_extern(const uint8_t* raw, uint16_t raw_len,
    luat_airlink_drv_rpc_mobile_scell_extern_info_t* out);

// lua_yieldk 模式: mobile.scell() 组合接口，从机一次 RPC 返回全部数据
int luat_airlink_drv_rpc_mobile_scell_yield(
    lua_State* L, lua_KFunction cont, lua_KContext user_ctx
);
int luat_airlink_drv_rpc_mobile_decode_scell(const uint8_t* raw, uint16_t raw_len,
    luat_airlink_drv_rpc_mobile_scell_info_t* out);
int luat_airlink_drv_rpc_mobile_scell(
    luat_airlink_drv_rpc_mobile_scell_info_t* out
);

int luat_airlink_drv_rpc_mobile_get_imei(
    uint8_t sim_id,
    char* buff,
    size_t buf_len
);
int luat_airlink_drv_rpc_mobile_get_imsi(
    uint8_t sim_id,
    char* buff,
    size_t buf_len
);
int luat_airlink_drv_rpc_mobile_get_iccid(
    uint8_t sim_id,
    char* buff,
    size_t buf_len
);
int luat_airlink_drv_rpc_mobile_get_sim_ready(
    uint8_t sim_id,
    uint8_t* sim_ready
);
int luat_airlink_drv_rpc_mobile_get_sn(
    char* buff,
    size_t buf_len
);
int luat_airlink_drv_rpc_mobile_get_muid(
    char* buff,
    size_t buf_len
);
int luat_airlink_drv_rpc_mobile_get_sim_status(
    LUAT_MOBILE_SIM_STATUS_E* sim_status
);
int luat_airlink_drv_rpc_mobile_get_register_status(
    LUAT_MOBILE_REGISTER_STATUS_E* register_status
);
int luat_airlink_drv_rpc_mobile_get_signal_strength(
    uint8_t* csq
);
int luat_airlink_drv_rpc_mobile_get_signal_strength_info(
    luat_mobile_signal_strength_info_t* info
);
int luat_airlink_drv_rpc_mobile_get_cell_info(
    luat_mobile_cell_info_t* info
);
int luat_airlink_drv_rpc_mobile_get_last_notify_cell_info(
    luat_mobile_cell_info_t* info
);
int luat_airlink_drv_rpc_mobile_get_extern_service_cell_info(
    luat_mobile_scell_extern_info_t* info
);
int luat_airlink_drv_rpc_mobile_get_last_cell_scan_notify(
    luat_airlink_drv_rpc_mobile_cell_scan_notify_t* out
);

void luat_airlink_drv_rpc_mobile_set_notify_callback(
    luat_airlink_drv_rpc_mobile_notify_cb_t cb,
    void* userdata
);
void luat_airlink_drv_rpc_mobile_notify_dispatch(
    uint16_t rpc_id,
    const void* msg_raw,
    void* userdata
);

#endif /* LUAT_USE_AIRLINK_RPC && (LUAT_USE_MOBILE || LUAT_USE_DRV_MOBILE) */

#endif /* LUAT_AIRLINK_DRV_RPC_MOBILE_H */

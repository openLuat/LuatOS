#ifndef LUAT_AIRLINK_RPC_H
#define LUAT_AIRLINK_RPC_H

#include "luat_airlink.h"

// =====================================================================
// RPC 模板 (同步调用), 需启用 LUAT_USE_AIRLINK_RPC
// =====================================================================

#define AIRLINK_CMD_RPC              0x30  // RPC 请求 cmd id
#define LUAT_AIRLINK_RPC_MAX_HANDLERS 32   // 最大同时注册的 RPC handler 数

// RPC 服务端处理函数类型
// 返回 0=成功(resp 中写入了 *resp_len 字节), 负值=错误码
typedef int (*luat_airlink_rpc_handler_t)(uint16_t rpc_id,
                                          const uint8_t* req, uint16_t req_len,
                                          uint8_t* resp, uint16_t resp_size,
                                          uint16_t* resp_len,
                                          void* userdata);

typedef struct luat_airlink_rpc_reg {
    uint16_t rpc_id;
    uint8_t  active;
    luat_airlink_rpc_handler_t handler;
    void*    userdata;
} luat_airlink_rpc_reg_t;

// 注册/注销 RPC handler (服务端)
int luat_airlink_rpc_register(uint16_t rpc_id, luat_airlink_rpc_handler_t handler, void* userdata);
int luat_airlink_rpc_unregister(uint16_t rpc_id);

// 同步调用对端 RPC, 返回 0=成功, -1=超时, -2=内存不足, -3=发送失败
// 必须在独立任务上下文调用, 不能在 airlink task 或 IRQ 中调用
int luat_airlink_rpc(uint8_t mode, uint16_t rpc_id,
                     const uint8_t* req, uint16_t req_len,
                     uint8_t* resp, uint16_t resp_size, uint16_t* resp_len,
                     uint32_t timeout_ms);

#endif /* LUAT_AIRLINK_RPC_H */

#ifndef LUAT_AIRLINK_RPC_H
#define LUAT_AIRLINK_RPC_H

#include "luat_airlink.h"

// =====================================================================
// RPC 框架, 需启用 LUAT_USE_AIRLINK_RPC
// =====================================================================

#define AIRLINK_CMD_RPC               0x30  // RPC 请求 cmd id
#define LUAT_AIRLINK_RPC_MAX_HANDLERS 8     // 最大动态注册的 RPC handler 数(Lua侧使用; C侧用静态表)

// cmd 0x30 payload 中 msg_type 字节的取值
#define AIRLINK_RPC_MSG_TYPE_REQUEST  0  // 同步请求, 对端须回应
#define AIRLINK_RPC_MSG_TYPE_NOTIFY   1  // fire-and-forget, 无需回应

// =====================================================================
// 原始字节 RPC (raw bytes handler)
// =====================================================================

// RPC 服务端处理函数类型 (raw bytes)
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

// 注册/注销原始字节 RPC handler (服务端)
int luat_airlink_rpc_register(uint16_t rpc_id, luat_airlink_rpc_handler_t handler, void* userdata);
int luat_airlink_rpc_unregister(uint16_t rpc_id);

// 同步调用对端 RPC (raw bytes), 返回 0=成功, -1=超时, -2=内存不足, -3=发送失败
// 必须在独立任务上下文调用, 不能在 airlink task 或 IRQ 中调用
int luat_airlink_rpc(uint8_t mode, uint16_t rpc_id,
                     const uint8_t* req, uint16_t req_len,
                     uint8_t* resp, uint16_t resp_size, uint16_t* resp_len,
                     uint32_t timeout_ms);

// =====================================================================
// nanopb typed RPC (handler 收到的是已解码的 C struct)
// =====================================================================

#include "pb.h"
#include "pb_encode.h"
#include "pb_decode.h"

// nanopb typed handler 函数类型
// req: 已解码的请求 struct 指针 (只读)
// resp: 预分配的响应 struct 指针 (handler 负责填充)
// 返回 0=成功, 负值=错误码
typedef int (*luat_airlink_rpc_nb_handler_t)(uint16_t rpc_id,
                                              const void* req,
                                              void* resp,
                                              void* userdata);

// notify handler 函数类型 (无响应)
typedef void (*luat_airlink_rpc_nb_notify_handler_t)(uint16_t rpc_id,
                                                      const void* msg,
                                                      void* userdata);

typedef struct luat_airlink_rpc_nb_reg {
    uint16_t rpc_id;
    uint8_t  active;
    const pb_msgdesc_t* req_desc;
    size_t               req_size;
    const pb_msgdesc_t* resp_desc;
    size_t               resp_size;
    luat_airlink_rpc_nb_handler_t        handler;
    luat_airlink_rpc_nb_notify_handler_t notify_handler;
    void* userdata;
} luat_airlink_rpc_nb_reg_t;

// 注册 nanopb typed handler (服务端)
// notify_handler 可为 NULL; 若非 NULL, 会在收到 NOTIFY 消息时调用
int luat_airlink_rpc_nb_register(uint16_t rpc_id,
                                  const pb_msgdesc_t* req_desc, size_t req_size,
                                  const pb_msgdesc_t* resp_desc, size_t resp_size,
                                  luat_airlink_rpc_nb_handler_t handler,
                                  luat_airlink_rpc_nb_notify_handler_t notify_handler,
                                  void* userdata);

int luat_airlink_rpc_nb_unregister(uint16_t rpc_id);

// 同步调用对端 nanopb RPC (编码 req → raw call → 解码 resp)
// 返回 0=成功, -1=超时, -2=内存不足, -3=发送失败, -4=编解码失败
int luat_airlink_rpc_nb_call(uint8_t mode, uint16_t rpc_id,
                              const pb_msgdesc_t* req_desc, const void* req,
                              const pb_msgdesc_t* resp_desc, void* resp,
                              uint32_t timeout_ms);

// Fire-and-forget notify (编码 msg 后以 NOTIFY 类型发送, 无需响应)
// 返回 0=成功, -2=内存不足, -3=发送失败, -4=编码失败
int luat_airlink_rpc_nb_notify(uint8_t mode, uint16_t rpc_id,
                                const pb_msgdesc_t* desc, const void* msg);

#endif /* LUAT_AIRLINK_RPC_H */

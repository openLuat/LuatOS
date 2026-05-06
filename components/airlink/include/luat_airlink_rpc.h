#ifndef LUAT_AIRLINK_RPC_H
#define LUAT_AIRLINK_RPC_H

#include "luat_airlink.h"

// =====================================================================
// RPC 框架, 需启用 LUAT_USE_AIRLINK_RPC
// =====================================================================

#define AIRLINK_CMD_RPC               0x30  // RPC 请求 cmd id

// cmd 0x30 payload 中 msg_type 字节的取值
#define AIRLINK_RPC_MSG_TYPE_REQUEST  0  // 同步请求, 对端须回应
#define AIRLINK_RPC_MSG_TYPE_NOTIFY   1  // fire-and-forget, 无需回应

// =====================================================================
// 原始字节 RPC (raw bytes handler) — 仅供内部 / 客户端 call 使用
// =====================================================================

// 同步调用对端 RPC (raw bytes), 返回 0=成功, -1=超时, -2=内存不足, -3=发送失败
// 必须在独立任务上下文调用, 不能在 airlink task 或 IRQ 中调用
int luat_airlink_rpc(uint8_t mode, uint16_t rpc_id,
                     const uint8_t* req, uint16_t req_len,
                     uint8_t* resp, uint16_t resp_size, uint16_t* resp_len,
                     uint32_t timeout_ms);

// =====================================================================
// nanopb typed RPC (handler 收到的是已解码的 C struct)
// =====================================================================

#ifdef LUAT_USE_AIRLINK_RPC

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

// 注册 nanopb typed handler (服务端) — 已移除动态注册，仅保留静态表机制
// 如需添加新 handler，请在 luat_airlink_rpc_nb_table.c 中添加静态条目

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

// =====================================================================
// RPC 统计与诊断
// =====================================================================

typedef struct {
    uint64_t call_total;       // 总调用次数
    uint64_t call_success;     // 成功次数
    uint64_t call_timeout;     // 超时次数
    uint64_t call_send_fail;   // 发送失败
    uint64_t call_encode_fail; // 编码失败
    uint64_t call_decode_fail; // 解码失败
    uint64_t notify_total;     // notify 总数
    uint64_t notify_success;   // notify 成功数
    uint64_t notify_encode_fail;
} luat_airlink_rpc_stats_t;

typedef struct {
    uint64_t total_ms;         // 累计耗时(ms)
    uint64_t count;            // 计数
    uint32_t min_ms;           // 最小耗时
    uint32_t max_ms;           // 最大耗时
} luat_airlink_rpc_latency_t;

typedef struct {
    uint64_t encode_total_us;  // 总编码时间(us)
    uint64_t decode_total_us;  // 总解码时间(us)
    uint64_t encode_count;
    uint64_t decode_count;
    uint32_t encode_max_us;    // 最大编码耗时
    uint32_t decode_max_us;    // 最大解码耗时
} luat_airlink_rpc_perf_t;

// 获取 RPC 统计信息
int luat_airlink_rpc_get_stats(luat_airlink_rpc_stats_t* stats);

// 获取 RPC 性能指标 (延迟、编解码)
int luat_airlink_rpc_get_perf(luat_airlink_rpc_latency_t* latency,
                               luat_airlink_rpc_perf_t* perf);

// 重置所有统计数据
int luat_airlink_rpc_reset_stats(void);

// 打印统计信息到日志
void luat_airlink_rpc_print_stats(void);

#endif /* LUAT_USE_AIRLINK_RPC */

#endif /* LUAT_AIRLINK_RPC_H */

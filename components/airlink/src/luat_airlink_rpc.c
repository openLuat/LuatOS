/*
 * AirLink RPC 框架 (通用同步调用模板 + nanopb typed 层)
 *
 * 线格式 cmd 0x30:
 *   [pkgid   : 8 bytes]  -- 0 = NOTIFY (无需响应)
 *   [rpc_id  : 2 bytes]
 *   [msg_type: 1 byte ]  -- 0=REQUEST, 1=NOTIFY
 *   [payload : N bytes]  -- nanopb 或 raw bytes
 *
 * 响应 cmd 0x08: [new_pkgid:8][req_pkgid:8][result_code:2][nanopb_resp_payload]
 *                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^
 *                              luat_airlink_result_send 中 buff 参数
 */

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_mcu.h"
#ifdef LUAT_USE_AIRLINK_RPC

#include "pb_encode.h"
#include "pb_decode.h"

#define LUAT_LOG_TAG "airlink.rpc"
#include "luat_log.h"

/* ------------------------------------------------------------------ */
/* RPC 统计与性能监控                                                   */
/* ------------------------------------------------------------------ */

static luat_airlink_rpc_stats_t g_rpc_stats = {0};
static luat_airlink_rpc_latency_t g_rpc_latency = {0};
static luat_airlink_rpc_perf_t g_rpc_perf = {0};
static luat_rtos_mutex_t g_rpc_stats_mutex = NULL;

// stats mutex 统一初始化 (幂等, 由 luat_airlink_init 调用)
void luat_airlink_rpc_stats_init(void) {
    if (g_rpc_stats_mutex == NULL) {
        luat_rtos_mutex_create(&g_rpc_stats_mutex);
    }
}

static inline void _stats_lock(void) {
    if (g_rpc_stats_mutex == NULL) {
        luat_rtos_mutex_create(&g_rpc_stats_mutex);
    }
    luat_rtos_mutex_lock(g_rpc_stats_mutex, LUAT_WAIT_FOREVER);
}

static inline void _stats_unlock(void) {
    if (g_rpc_stats_mutex != NULL) {
        luat_rtos_mutex_unlock(g_rpc_stats_mutex);
    }
}

static void _update_latency(uint32_t latency_ms) {
    g_rpc_latency.total_ms += latency_ms;
    g_rpc_latency.count++;
    if (latency_ms < g_rpc_latency.min_ms || g_rpc_latency.min_ms == 0) {
        g_rpc_latency.min_ms = latency_ms;
    }
    if (latency_ms > g_rpc_latency.max_ms) {
        g_rpc_latency.max_ms = latency_ms;
    }
}

static void _update_perf_encode(uint32_t us) {
    if (us > 1000) us = 1000;  // cap at 1000us to avoid overflow on older systems
    g_rpc_perf.encode_total_us += us;
    g_rpc_perf.encode_count++;
    if (us > g_rpc_perf.encode_max_us) {
        g_rpc_perf.encode_max_us = us;
    }
}

static void _update_perf_decode(uint32_t us) {
    if (us > 1000) us = 1000;  // cap at 1000us
    g_rpc_perf.decode_total_us += us;
    g_rpc_perf.decode_count++;
    if (us > g_rpc_perf.decode_max_us) {
        g_rpc_perf.decode_max_us = us;
    }
}

/* ------------------------------------------------------------------ */
/* nanopb typed RPC layer                                               */
/* ------------------------------------------------------------------ */

typedef struct {
    luat_rtos_semaphore_t sem;
    uint8_t*  out_buf;
    uint16_t  out_buf_size;
    uint16_t* out_len;
    int       ret_code;       // 0=success, <0=error
    volatile uint8_t timed_out; // 超时后 callback 负责释放
} rpc_sync_ctx_t;

/* result_reg exec callback，在 reg_mutex 下调用 */
static void rpc_sync_exec(struct luat_airlink_result_reg* reg, luat_airlink_cmd_t* cmd) {
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)reg->userdata;

    LLOGI("rpc_sync_exec ENTER cmd->len=%d timed_out=%d", cmd->len, (int)ctx->timed_out);

    if (ctx->timed_out) {
        // 调用方已超时并放弃等待，由 callback 释放资源
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return;
    }

    LLOGD("rpc_sync_exec cmd->len=%d", cmd->len);
    // cmd->data 格式: [new_pkgid:8][req_pkgid:8][result_code:2][resp payload]
    if (cmd->len >= 18) {
        int16_t result_code = 0;
        memcpy(&result_code, cmd->data + 16, 2);
        LLOGD("rpc_sync_exec result_code=%d", (int)result_code);
        ctx->ret_code = (int)result_code;

        uint16_t payload_len = cmd->len - 18;
        if (payload_len > ctx->out_buf_size) {
            payload_len = ctx->out_buf_size;
        }
        if (ctx->out_buf && payload_len > 0) {
            memcpy(ctx->out_buf, cmd->data + 18, payload_len);
        }
        if (ctx->out_len) {
            *ctx->out_len = payload_len;
        }
    } else {
        ctx->ret_code = -1;
        if (ctx->out_len) *ctx->out_len = 0;
    }

    luat_rtos_semaphore_release(ctx->sem);
}

/* ------------------------------------------------------------------ */
/* 同步 RPC 调用                                                         */
/* ------------------------------------------------------------------ */

int luat_airlink_rpc(uint8_t mode, uint16_t rpc_id,
                     const uint8_t* req, uint16_t req_len,
                     uint8_t* resp, uint16_t resp_size, uint16_t* resp_len,
                     uint32_t timeout_ms) {
    if (resp_len) *resp_len = 0;
    
    uint64_t start_tick = luat_mcu_tick64_ms();

    // 分配同步上下文
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)luat_heap_malloc(sizeof(rpc_sync_ctx_t));
    if (ctx == NULL) {
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;  // 视为发送失败
        _stats_unlock();
        LLOGE("rpc: malloc ctx failed");
        return -2;
    }
    memset(ctx, 0, sizeof(rpc_sync_ctx_t));
    ctx->out_buf      = resp;
    ctx->out_buf_size = resp_size;
    ctx->out_len      = resp_len;
    ctx->ret_code     = -1;
    ctx->timed_out    = 0;

    if (luat_rtos_semaphore_create(&ctx->sem, 1) != 0) {
        LLOGE("rpc: semaphore create failed");
        luat_heap_free(ctx);
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -2;
    }

    // 生成 pkgid 并注册 result_reg
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    luat_airlink_result_reg_t reg = {0};
    reg.tm       = luat_mcu_tick64_ms();
    reg.id       = pkgid;
    reg.userdata = ctx;
    reg.exec     = rpc_sync_exec;

    if (luat_airlink_result_reg(&reg) != 0) {
        LLOGE("rpc: result_reg 已满");
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -2;
    }

    // 构造 RPC cmd: [pkgid:8][rpc_id:2][msg_type:1][req payload]
    uint16_t cmd_data_len = 8 + 2 + 1 + req_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(AIRLINK_CMD_RPC, cmd_data_len);
    if (cmd == NULL) {
        LLOGE("rpc: malloc cmd failed");
        luat_airlink_result_unreg(pkgid);
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -2;
    }
    memcpy(cmd->data,     &pkgid, 8);
    memcpy(cmd->data + 8, &rpc_id, 2);
    cmd->data[10] = AIRLINK_RPC_MSG_TYPE_REQUEST;
    if (req && req_len > 0) {
        memcpy(cmd->data + 11, req, req_len);
    }

    LLOGD("rpc call: mode=%d rpc_id=0x%04X req_len=%d timeout=%dms pkgid=0x%llx", 
          mode, rpc_id, req_len, timeout_ms, pkgid);

    // 发送到指定 transport
    int send_ret = luat_airlink_send2transport(cmd, mode);
    luat_airlink_cmd_free(cmd);

    if (send_ret != 0) {
        LLOGE("rpc: send2transport failed %d", send_ret);
        luat_airlink_result_unreg(pkgid);
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -3;
    }

    LLOGI("rpc: waiting on semaphore pkgid=0x%llx timeout=%dms", pkgid, timeout_ms);
    // 阻塞等待
    int wait_ret = luat_rtos_semaphore_take(ctx->sem, timeout_ms);
    LLOGI("rpc: semaphore take ret=%d (pkgid=0x%llx)", wait_ret, pkgid);
    if (wait_ret != 0) {
        // 超时：尝试从注册表清理 result_reg slot
        uint64_t elapsed_ms = luat_mcu_tick64_ms() - start_tick;
        LLOGE("rpc: timeout after %llums (pkgid=0x%llx rpc_id=0x%04X)", elapsed_ms, pkgid, rpc_id);
        
        if (luat_airlink_result_unreg(pkgid) == 0) {
            // 清理成功：callback 不会触发，安全释放 ctx
            luat_rtos_semaphore_delete(ctx->sem);
            luat_heap_free(ctx);
        } else {
            // result_unreg 在持有 reg_mutex 后未找到 slot：
            // 说明 callback 已完成（在我们清理之前运行完毕并清空了 slot）。
            // callback 调用了 semaphore_release 但未释放 ctx，此处负责释放。
            ctx->timed_out = 1;  // 安全标志（防止极端情况下互斥锁超时）
            luat_rtos_semaphore_delete(ctx->sem);
            luat_heap_free(ctx);
        }
        
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_timeout++;
        _stats_unlock();
        
        return -1; // timeout
    }

    // 成功
    uint64_t elapsed_ms = luat_mcu_tick64_ms() - start_tick;
    int result = ctx->ret_code;
    
    _stats_lock();
    g_rpc_stats.call_total++;
    if (result == 0) {
        g_rpc_stats.call_success++;
        _update_latency(elapsed_ms);
        LLOGD("rpc: success (took %llums resp_len=%d)", elapsed_ms, ctx->out_len ? *ctx->out_len : 0);
    } else {
        if (result == -501 || result == -502) {
            g_rpc_stats.call_decode_fail++;
            LLOGE("rpc: codec error result=%d (took %llums)", result, elapsed_ms);
        } else {
            g_rpc_stats.call_send_fail++;
            LLOGE("rpc: result error %d (took %llums)", result, elapsed_ms);
        }
    }
    _stats_unlock();
    
    luat_airlink_result_unreg(pkgid);
    luat_rtos_semaphore_delete(ctx->sem);
    luat_heap_free(ctx);
    return result;
}

/* ------------------------------------------------------------------ */
/* nanopb typed RPC layer                                               */
/* ------------------------------------------------------------------ */

#define NB_ENC_BUF_SIZE  1500  // nanopb encode/decode 临时缓冲区大小 (UartRpcRequest 最大 518 字节, 预留余量)

// 静态处理表 (由 luat_airlink_rpc_nb_table.c 汇编，按宏控制哪些模块启用)
extern const luat_airlink_rpc_nb_reg_t* const luat_airlink_rpc_nb_static_table[];
extern const size_t luat_airlink_rpc_nb_static_count;

/* 服务端调用: 查找 nanopb typed handler 并调用 (含 decode/encode), 返回 0=找到并处理, -404=未找到 */
int luat_airlink_rpc_nb_dispatch(uint16_t rpc_id, uint8_t msg_type,
                                  const uint8_t* req_bytes, uint16_t req_len,
                                  uint8_t* resp_bytes, uint16_t resp_size, uint16_t* resp_len) {
    luat_airlink_rpc_nb_reg_t entry = {0};
    int found = 0;
    // 搜索静态表（无锁，编译期确定）
    for (size_t i = 0; i < luat_airlink_rpc_nb_static_count; i++) {
        if (luat_airlink_rpc_nb_static_table[i]->active &&
            luat_airlink_rpc_nb_static_table[i]->rpc_id == rpc_id) {
            entry = *luat_airlink_rpc_nb_static_table[i];
            found = 1;
            break;
        }
    }

    if (!found) return -404;

    if (msg_type == AIRLINK_RPC_MSG_TYPE_NOTIFY) {
        if (entry.notify_handler) {
            const pb_msgdesc_t* n_desc  = entry.notify_desc ? entry.notify_desc : entry.req_desc;
            size_t              n_size  = entry.notify_desc ? entry.notify_size : entry.req_size;
            if (n_desc && n_size > 0) {
                void* msg_struct = luat_heap_malloc(n_size);
                if (msg_struct) {
                    memset(msg_struct, 0, n_size);
                    pb_istream_t istream = pb_istream_from_buffer(req_bytes, req_len);
                    if (pb_decode(&istream, n_desc, msg_struct)) {
                        entry.notify_handler(rpc_id, msg_struct, entry.userdata);
                    } else {
                        LLOGE("rpc_nb_dispatch: pb_decode notify failed rpc_id=%04X", rpc_id);
                    }
                    luat_heap_free(msg_struct);
                }
            }
        }
        *resp_len = 0;
        return 0;
    }

    // REQUEST: decode req → call handler → encode resp
    void* req_struct  = NULL;
    void* resp_struct = NULL;
    int rc = 0;

    if (entry.req_desc && entry.req_size > 0) {
        req_struct = luat_heap_malloc(entry.req_size);
        if (!req_struct) { rc = -500; goto cleanup; }
        memset(req_struct, 0, entry.req_size);
        pb_istream_t istream = pb_istream_from_buffer(req_bytes, req_len);
        if (!pb_decode(&istream, entry.req_desc, req_struct)) {
            LLOGE("rpc_nb_dispatch: pb_decode req failed rpc_id=%04X", rpc_id);
            rc = -501;
            goto cleanup;
        }
    }

    if (entry.resp_desc && entry.resp_size > 0) {
        resp_struct = luat_heap_malloc(entry.resp_size);
        if (!resp_struct) { rc = -500; goto cleanup; }
        memset(resp_struct, 0, entry.resp_size);
    }

    rc = entry.handler(rpc_id, req_struct, resp_struct, entry.userdata);

    if (rc == 0 && resp_struct && entry.resp_desc) {
        pb_ostream_t ostream = pb_ostream_from_buffer(resp_bytes, resp_size);
        if (!pb_encode(&ostream, entry.resp_desc, resp_struct)) {
            LLOGE("rpc_nb_dispatch: pb_encode resp failed rpc_id=%04X", rpc_id);
            rc = -502;
            *resp_len = 0;
        } else {
            *resp_len = (uint16_t)ostream.bytes_written;
        }
    } else {
        *resp_len = 0;
    }

cleanup:
    if (req_struct)  luat_heap_free(req_struct);
    if (resp_struct) luat_heap_free(resp_struct);
    return rc;
}

int luat_airlink_rpc_nb_call(uint8_t mode, uint16_t rpc_id,
                              const pb_msgdesc_t* req_desc, const void* req,
                              const pb_msgdesc_t* resp_desc, void* resp,
                              uint32_t timeout_ms) {
    // 编码请求
    uint64_t enc_start = luat_mcu_tick64_ms();
    uint8_t* enc_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!enc_buf) {
        LLOGE("rpc_nb_call: malloc enc_buf failed");
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -2;
    }
    uint16_t enc_len = 0;
    if (req_desc && req) {
        pb_ostream_t ostream = pb_ostream_from_buffer(enc_buf, NB_ENC_BUF_SIZE);
        if (!pb_encode(&ostream, req_desc, req)) {
            LLOGE("rpc_nb_call: pb_encode req failed rpc_id=%04X", rpc_id);
            luat_heap_free(enc_buf);
            _stats_lock();
            g_rpc_stats.call_total++;
            g_rpc_stats.call_encode_fail++;
            _stats_unlock();
            return -4;
        }
        enc_len = (uint16_t)ostream.bytes_written;
    }
    uint32_t enc_ms = (uint32_t)(luat_mcu_tick64_ms() - enc_start);
    _stats_lock();
    if (enc_ms > 0) {
        g_rpc_perf.encode_total_us += (enc_ms * 1000);
        g_rpc_perf.encode_count++;
        if ((enc_ms * 1000) > g_rpc_perf.encode_max_us) {
            g_rpc_perf.encode_max_us = (enc_ms * 1000);
        }
    }
    _stats_unlock();
    LLOGD("rpc_nb_call: encode took %ums rpc_id=0x%04X enc_len=%d", enc_ms, rpc_id, enc_len);

    // 分配响应缓冲区
    uint8_t* resp_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!resp_buf) {
        LLOGE("rpc_nb_call: malloc resp_buf failed");
        luat_heap_free(enc_buf);
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -2;
    }
    uint16_t resp_len = 0;

    // 同步 RPC 调用
    int rc = luat_airlink_rpc(mode, rpc_id, enc_buf, enc_len,
                               resp_buf, NB_ENC_BUF_SIZE, &resp_len, timeout_ms);
    luat_heap_free(enc_buf);

    if (rc != 0) {
        luat_heap_free(resp_buf);
        return rc; // -1=timeout, -2=oom, -3=send fail
    }

    // 解码响应
    uint64_t dec_start = luat_mcu_tick64_ms();
    if (resp_desc && resp && resp_len > 0) {
        pb_istream_t istream = pb_istream_from_buffer(resp_buf, resp_len);
        if (!pb_decode(&istream, resp_desc, resp)) {
            LLOGE("rpc_nb_call: pb_decode resp failed rpc_id=%04X", rpc_id);
            luat_heap_free(resp_buf);
            _stats_lock();
            g_rpc_stats.call_total++;
            g_rpc_stats.call_decode_fail++;
            _stats_unlock();
            return -4;
        }
    }
    uint32_t dec_ms = (uint32_t)(luat_mcu_tick64_ms() - dec_start);
    _stats_lock();
    if (dec_ms > 0) {
        g_rpc_perf.decode_total_us += (dec_ms * 1000);
        g_rpc_perf.decode_count++;
        if ((dec_ms * 1000) > g_rpc_perf.decode_max_us) {
            g_rpc_perf.decode_max_us = (dec_ms * 1000);
        }
    }
    _stats_unlock();
    LLOGD("rpc_nb_call: decode took %ums rpc_id=0x%04X resp_len=%d", dec_ms, rpc_id, resp_len);
    luat_heap_free(resp_buf);
    return 0;
}

int luat_airlink_rpc_nb_notify(uint8_t mode, uint16_t rpc_id,
                                const pb_msgdesc_t* desc, const void* msg) {
    // 编码消息
    uint64_t enc_start = luat_mcu_tick64_ms();
    uint8_t* enc_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!enc_buf) {
        LLOGE("rpc_nb_notify: malloc failed");
        _stats_lock();
        g_rpc_stats.notify_total++;
        g_rpc_stats.notify_encode_fail++;
        _stats_unlock();
        return -2;
    }
    uint16_t enc_len = 0;
    if (desc && msg) {
        pb_ostream_t ostream = pb_ostream_from_buffer(enc_buf, NB_ENC_BUF_SIZE);
        if (!pb_encode(&ostream, desc, msg)) {
            LLOGE("rpc_nb_notify: pb_encode failed rpc_id=%04X", rpc_id);
            luat_heap_free(enc_buf);
            _stats_lock();
            g_rpc_stats.notify_total++;
            g_rpc_stats.notify_encode_fail++;
            _stats_unlock();
            return -4;
        }
        enc_len = (uint16_t)ostream.bytes_written;
    }
    uint32_t enc_ms = (uint32_t)(luat_mcu_tick64_ms() - enc_start);
    _stats_lock();
    if (enc_ms > 0) {
        g_rpc_perf.encode_total_us += (enc_ms * 1000);
        g_rpc_perf.encode_count++;
        if ((enc_ms * 1000) > g_rpc_perf.encode_max_us) {
            g_rpc_perf.encode_max_us = (enc_ms * 1000);
        }
    }
    _stats_unlock();

    // 构造 NOTIFY cmd: [pkgid=0:8][rpc_id:2][msg_type=NOTIFY:1][payload]
    uint16_t cmd_data_len = 8 + 2 + 1 + enc_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(AIRLINK_CMD_RPC, cmd_data_len);
    if (!cmd) {
        LLOGE("rpc_nb_notify: malloc cmd failed");
        luat_heap_free(enc_buf);
        _stats_lock();
        g_rpc_stats.notify_total++;
        g_rpc_stats.notify_encode_fail++;
        _stats_unlock();
        return -2;
    }
    uint64_t zero_pkgid = 0;
    memcpy(cmd->data,     &zero_pkgid, 8);
    memcpy(cmd->data + 8, &rpc_id, 2);
    cmd->data[10] = AIRLINK_RPC_MSG_TYPE_NOTIFY;
    if (enc_len > 0) {
        memcpy(cmd->data + 11, enc_buf, enc_len);
    }
    luat_heap_free(enc_buf);

    int ret = luat_airlink_send2transport(cmd, mode);
     luat_airlink_cmd_free(cmd);
    
    _stats_lock();
    g_rpc_stats.notify_total++;
    if (ret == 0) {
        g_rpc_stats.notify_success++;
    }
    _stats_unlock();
    
    if (ret != 0) {
        LLOGE("rpc_nb_notify: send2transport failed %d", ret);
        return -3;
    }
    return 0;
}

/* ------------------------------------------------------------------ */
/* RPC 统计 API                                                         */
/* ------------------------------------------------------------------ */

int luat_airlink_rpc_get_stats(luat_airlink_rpc_stats_t* stats) {
    if (!stats) return -1;
    _stats_lock();
    memcpy(stats, &g_rpc_stats, sizeof(luat_airlink_rpc_stats_t));
    _stats_unlock();
    return 0;
}

int luat_airlink_rpc_get_perf(luat_airlink_rpc_latency_t* latency,
                               luat_airlink_rpc_perf_t* perf) {
    _stats_lock();
    if (latency) {
        memcpy(latency, &g_rpc_latency, sizeof(luat_airlink_rpc_latency_t));
    }
    if (perf) {
        memcpy(perf, &g_rpc_perf, sizeof(luat_airlink_rpc_perf_t));
    }
    _stats_unlock();
    return 0;
}

int luat_airlink_rpc_reset_stats(void) {
    _stats_lock();
    memset(&g_rpc_stats, 0, sizeof(luat_airlink_rpc_stats_t));
    memset(&g_rpc_latency, 0, sizeof(luat_airlink_rpc_latency_t));
    memset(&g_rpc_perf, 0, sizeof(luat_airlink_rpc_perf_t));
    _stats_unlock();
    return 0;
}

void luat_airlink_rpc_print_stats(void) {
    luat_airlink_rpc_stats_t stats;
    luat_airlink_rpc_latency_t latency;
    luat_airlink_rpc_perf_t perf;
    
    luat_airlink_rpc_get_stats(&stats);
    luat_airlink_rpc_get_perf(&latency, &perf);
    
    LLOGI("=== RPC Statistics ===");
    LLOGI("Call: total=%llu success=%llu timeout=%llu send_fail=%llu encode_fail=%llu decode_fail=%llu",
          stats.call_total, stats.call_success, stats.call_timeout, 
          stats.call_send_fail, stats.call_encode_fail, stats.call_decode_fail);
    LLOGI("Notify: total=%llu success=%llu encode_fail=%llu",
          stats.notify_total, stats.notify_success, stats.notify_encode_fail);
    
    if (latency.count > 0) {
        uint32_t avg_ms = (uint32_t)(latency.total_ms / latency.count);
        LLOGI("Latency: count=%llu avg=%ums min=%ums max=%ums",
              latency.count, avg_ms, latency.min_ms, latency.max_ms);
    }
    
    if (perf.encode_count > 0) {
        uint32_t avg_enc_us = (uint32_t)(perf.encode_total_us / perf.encode_count);
        LLOGI("Encode: count=%llu avg=%uus max=%uus",
              perf.encode_count, avg_enc_us, perf.encode_max_us);
    }
    
    if (perf.decode_count > 0) {
        uint32_t avg_dec_us = (uint32_t)(perf.decode_total_us / perf.decode_count);
        LLOGI("Decode: count=%llu avg=%uus max=%uus",
              perf.decode_count, avg_dec_us, perf.decode_max_us);
    }
}

#endif /* LUAT_USE_AIRLINK_RPC */


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

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include "luat_msgbus.h"
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
    volatile uint8_t timed_out; // 超时标志, callback 据此决定是否通知
    volatile uint8_t refcnt;    // 引用计数: waiter(1) + slot/callback(1), 归零时销毁
    // yield 模式扩展
    uint8_t   is_yield;
    uint64_t  start_tick;      // 请求发起时间戳, 用于统计
    uint16_t  _owned_out_len;  // yield 模式下的自有 resp_len (替代外部指针)
    uint8_t*  enc_buf;         // 编码缓冲 (yield 模式下 ctx 释放时一并回收)
    uint8_t*  resp_buf;        // 响应原始缓冲 (yield 模式下 ctx 释放时一并回收)
    uint32_t  timeout_ms;      // 超时时间, 用于超时清理
    // lua_yieldk 模式扩展
    lua_State* coro_L;         // 挂起的协程 lua_State, 用于 lua_resume
    lua_KFunction user_cont;   // 用户提供的 continuation
    lua_KContext  user_k_ctx;  // 用户提供的 continuation 上下文
    int           has_raw;     // lua_resume 时是否已压入 raw_bytes
    luat_rtos_timer_t timeout_timer; // yield 模式超时定时器
    uint64_t      yield_pkgid; // yield 模式下的 RPC pkgid (用于超时 unreg)
    volatile uint8_t handled;  // 防止 timeout/resp 双重处理
    struct rpc_sync_ctx* yield_next; // yield 链表指针
} rpc_sync_ctx_t;

static rpc_sync_ctx_t* g_yield_list = NULL;  // 活跃 yield ctx 链表头
static luat_rtos_mutex_t g_yield_list_mutex = NULL;  // 保护 g_yield_list

#define NB_ENC_BUF_SIZE  AIRLINK_RPC_MAX_PAYLOAD  // nanopb encode/decode 临时缓冲区

// 统一释放 ctx 引用。最后一个释放者负责 delete sem/timer + free bufs + free ctx。
static void rpc_sync_ctx_release(rpc_sync_ctx_t* ctx) {
    if (ctx->refcnt == 0) return;
    ctx->refcnt--;
    if (ctx->refcnt == 0) {
        // 从 yield 链表中移除
        if (ctx->is_yield == 2) {
            if (g_yield_list_mutex == NULL) {
                luat_rtos_mutex_create(&g_yield_list_mutex);
            }
            luat_rtos_mutex_lock(g_yield_list_mutex, 1000);
            if (g_yield_list == ctx) {
                g_yield_list = ctx->yield_next;
            } else {
                for (rpc_sync_ctx_t** p = &g_yield_list; *p; p = &(*p)->yield_next) {
                    if (*p == ctx) {
                        *p = ctx->yield_next;
                        break;
                    }
                }
            }
            luat_rtos_mutex_unlock(g_yield_list_mutex);
            luat_rtos_timer_stop(ctx->timeout_timer);
            luat_rtos_timer_delete(ctx->timeout_timer);
        }
        if (!ctx->is_yield) {
            luat_rtos_semaphore_delete(ctx->sem);
        }
        if (ctx->enc_buf) {
            memset(ctx->enc_buf, 0xCC, NB_ENC_BUF_SIZE);
            luat_heap_free(ctx->enc_buf);
        }
        if (ctx->resp_buf) {
            memset(ctx->resp_buf, 0xCC, NB_ENC_BUF_SIZE);
            luat_heap_free(ctx->resp_buf);
        }
        luat_heap_free(ctx);
    }
}

/* result_reg exec callback，由 result dispatch 在锁外调用 */
static void rpc_sync_exec(struct luat_airlink_result_reg* reg, luat_airlink_cmd_t* cmd) {
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)reg->userdata;

    if (!ctx->timed_out) {
        // cmd->data 格式: [new_pkgid:8][req_pkgid:8][result_code:2][resp payload]
        if (cmd->len >= 18) {
            int16_t result_code = 0;
            memcpy(&result_code, cmd->data + 16, 2);
            ctx->ret_code = (int)result_code;

            uint16_t payload_len = cmd->len - 18;
            if (payload_len > ctx->out_buf_size) {
                LLOGE("rpc_sync_exec: resp %u exceeds buf %u, dropping",
                      payload_len, (unsigned)ctx->out_buf_size);
                ctx->ret_code = AIRLINK_ERR_RPC_RESP_TOO_LARGE;
                if (ctx->out_len) *ctx->out_len = 0;
            } else {
                if (ctx->out_buf && payload_len > 0) {
                    memcpy(ctx->out_buf, cmd->data + 18, payload_len);
                }
                if (ctx->out_len) {
                    *ctx->out_len = payload_len;
                }
            }
        } else {
            ctx->ret_code = -1;
            if (ctx->out_len) *ctx->out_len = 0;
        }
        luat_rtos_semaphore_release(ctx->sem);
    }
    rpc_sync_ctx_release(ctx);  // 释放 callback 引用
}

/* ---- lua_yieldk 模式的前向声明 ---- */
static int rpc_yield_resume_handler(lua_State* L, void* ptr);
static int rpc_yield_timeout_handler(lua_State* L, void* ptr);
static int rpc_yield_cont(lua_State* L, int status, lua_KContext k_ctx);
static void rpc_yield_timer_cb(void* param);

/* result_reg exec callback（lua_yieldk 模式），由 result dispatch 在 airlink 任务上调用
   注意: 此函数在 airlink task 上下文中执行, 不操作 refcnt.
   ctx 的生命周期由 Lua VM task 中的 msgbus handler 全权管理. */
static void rpc_async_exec_yield(struct luat_airlink_result_reg* reg, luat_airlink_cmd_t* cmd) {
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)reg->userdata;

    if (ctx->timed_out) {
        return;
    }

    if (cmd->len >= 18) {
        int16_t result_code = 0;
        memcpy(&result_code, cmd->data + 16, 2);
        ctx->ret_code = (int)result_code;

        uint16_t payload_len = cmd->len - 18;
        if (payload_len > ctx->out_buf_size) {
            ctx->ret_code = AIRLINK_ERR_RPC_RESP_TOO_LARGE;
            if (ctx->out_len) *ctx->out_len = 0;
        } else {
            if (ctx->out_buf && payload_len > 0) {
                memcpy(ctx->out_buf, cmd->data + 18, payload_len);
            }
            if (ctx->out_len) {
                *ctx->out_len = payload_len;
            }
        }
    } else {
        ctx->ret_code = -1;
        if (ctx->out_len) *ctx->out_len = 0;
    }

    // 通过 msgbus 投递到 Lua VM task, 由 rpc_yield_resume_handler 做 lua_resume
    rtos_msg_t msg = {0};
    msg.handler = rpc_yield_resume_handler;
    msg.ptr = ctx;
    if (luat_msgbus_put(&msg, 0) != 0) {
        LLOGW("rpc yield resume msgbus full, rely on timeout recovery");
    }
}

/* msgbus handler（lua_yieldk 模式），在 Lua VM task 上下文中执行，负责 lua_resume 唤醒协程 */
static int rpc_yield_resume_handler(lua_State* L, void* ptr) {
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)ptr;

    if (ctx->handled) {
        rpc_sync_ctx_release(ctx);  // 释放 response_slot 引用
        return 0;
    }
    ctx->handled = 1;

    // 尝试停止超时定时器
    if (luat_rtos_timer_stop(ctx->timeout_timer) == 0) {
        // 定时器已停止, timer callback 不会触发, 释放 timer 引用
        rpc_sync_ctx_release(ctx);
    }
    // 若 stop 失败: 定时器已触发, timeout msgbus 已入队, timer 引用由 timeout_handler 释放

    // 检查协程是否仍存活
    if (lua_status(ctx->coro_L) != LUA_YIELD) {
        rpc_sync_ctx_release(ctx);
        rpc_sync_ctx_release(ctx);
        return 0;
    }

    // 将响应数据压入协程栈
    if (ctx->ret_code == 0 && ctx->out_buf && ctx->out_len && *ctx->out_len > 0) {
        lua_pushlstring(ctx->coro_L, (const char*)ctx->out_buf, *ctx->out_len);
        ctx->has_raw = 1;
    } else {
        lua_pushnil(ctx->coro_L);
        ctx->has_raw = 0;
    }

    // 统计
    uint64_t elapsed_ms = luat_mcu_tick64_ms() - ctx->start_tick;
    _stats_lock();
    g_rpc_stats.call_total++;
    if (ctx->ret_code == 0) {
        g_rpc_stats.call_success++;
        _update_latency(elapsed_ms);
    } else {
        g_rpc_stats.call_send_fail++;
    }
    _stats_unlock();

    // 恢复协程
    int ret = lua_resume(ctx->coro_L, L, 1);
    if (ret != LUA_OK && ret != LUA_YIELD) {
        LLOGE("rpc yield resume error: %s", lua_tostring(ctx->coro_L, -1));
        lua_pop(ctx->coro_L, 1);
        rpc_sync_ctx_release(ctx);  // 错误路径: 释放 coroutine 引用 (continuation 未执行)
    }
    // LUA_OK: rpc_yield_cont 已执行并 release coroutine 引用

    // 释放 response_slot 引用
    rpc_sync_ctx_release(ctx);
    return 0;
}

/* FreeRTOS 定时器回调 (timer task 上下文), 投递 msgbus 到 rpc_yield_timeout_handler */
static void rpc_yield_timer_cb(void* param) {
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)param;
    rtos_msg_t msg = {0};
    msg.handler = rpc_yield_timeout_handler;
    msg.ptr = ctx;
    if (luat_msgbus_put(&msg, 0) != 0) {
        LLOGW("rpc yield timeout msgbus full, ctx may leak");
    }
}

/* msgbus handler（yield 超时），在 Lua VM task 上下文中执行 */
static int rpc_yield_timeout_handler(lua_State* L, void* ptr) {
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)ptr;

    if (ctx->handled) {
        rpc_sync_ctx_release(ctx);  // 释放 timer 引用
        return 0;
    }
    ctx->handled = 1;

    // 尝试注销 result_reg (防止后续响应到达)
    if (luat_airlink_result_unreg(ctx->yield_pkgid) == 0) {
        // 成功注销, rpc_async_exec_yield 不会触发, 释放 response_slot 引用
        rpc_sync_ctx_release(ctx);
    }
    // 若 unreg 失败: 响应已 dispatch, response_slot 引用由 resume_handler 释放

    // 检查协程是否仍存活
    if (lua_status(ctx->coro_L) != LUA_YIELD) {
        // 协程已死亡 (GC 回收或外部清理), continuation 不会执行
        rpc_sync_ctx_release(ctx);  // 释放 coroutine 引用
        rpc_sync_ctx_release(ctx);  // 释放 timer 引用
        return 0;
    }

    ctx->timed_out = 1;
    ctx->ret_code = -1;

    uint64_t elapsed_ms = luat_mcu_tick64_ms() - ctx->start_tick;

    _stats_lock();
    g_rpc_stats.call_total++;
    g_rpc_stats.call_timeout++;
    _stats_unlock();

    LLOGE("rpc yield timeout after %llums (pkgid=0x%llx)", elapsed_ms, ctx->yield_pkgid);

    // 压入 nil, 恢复协程
    lua_pushnil(ctx->coro_L);
    int ret = lua_resume(ctx->coro_L, L, 1);
    if (ret != LUA_OK && ret != LUA_YIELD) {
        LLOGE("rpc yield timeout resume error: %s", lua_tostring(ctx->coro_L, -1));
        lua_pop(ctx->coro_L, 1);
        rpc_sync_ctx_release(ctx);  // 错误路径: 释放 coroutine 引用
    }
    // LUA_OK: rpc_yield_cont 已执行并 release coroutine 引用

    // 释放 timer 引用
    rpc_sync_ctx_release(ctx);
    return 0;
}

/* lua_yieldk 的 continuation, lua_resume 恢复协程时调用
   Lua 的 resume() 总是传 LUA_YIELD 给 continuation, 而非常见编程预期的 LUA_OK.
   因此 accept 两者均为正常恢复, 对 user_cont 统一转成 LUA_OK. */
static int rpc_yield_cont(lua_State* L, int status, lua_KContext k_ctx) {
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)k_ctx;

    if (status != LUA_OK && status != LUA_YIELD) {
        // 协程被非正常恢复 (真错误, 如 LUA_ERRRUN)
        lua_pushnil(L);
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        rpc_sync_ctx_release(ctx);
        return 1;
    }

    // 栈上已有 raw_bytes (由 rpc_yield_resume_handler 压入)
    // 调用用户 continuation 解码, 传 LUA_OK 保持与常规 C continuation 约定一致
    if (ctx->user_cont) {
        lua_KFunction cont = ctx->user_cont;
        lua_KContext k_ctx = ctx->user_k_ctx;
        rpc_sync_ctx_release(ctx);
        return cont(L, LUA_OK, k_ctx);
    }

    // 无用户 continuation: 直接返回 raw_bytes
    rpc_sync_ctx_release(ctx);
    return 1;
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
        g_rpc_stats.call_send_fail++;
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
    ctx->is_yield     = 0;
    ctx->start_tick   = start_tick;
    ctx->timeout_ms   = timeout_ms;

    if (luat_rtos_semaphore_create(&ctx->sem, 1) != 0) {
        LLOGE("rpc: semaphore create failed");
        luat_heap_free(ctx);
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -2;
    }
    ctx->refcnt = 1;  // waiter 引用

    // 生成 pkgid 并注册 result_reg
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    luat_airlink_result_reg_t reg = {0};
    reg.tm       = luat_mcu_tick64_ms();
    reg.id       = pkgid;
    reg.userdata = ctx;
    reg.exec     = rpc_sync_exec;

    if (luat_airlink_result_reg(&reg) != 0) {
        LLOGE("rpc: result_reg 已满");
        rpc_sync_ctx_release(ctx);  // 释放 waiter 引用 (1→0 销毁)
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return AIRLINK_ERR_RESULT_REG_FULL;
    }
    ctx->refcnt = 2;  // waiter + slot

    // 构造 RPC cmd: [pkgid:8][rpc_id:2][msg_type:1][req payload]
    uint16_t cmd_data_len = 8 + 2 + 1 + req_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(AIRLINK_CMD_RPC, cmd_data_len);
    if (cmd == NULL) {
        LLOGE("rpc: malloc cmd failed");
        luat_airlink_result_unreg(pkgid);
        rpc_sync_ctx_release(ctx);  // slot 引用
        rpc_sync_ctx_release(ctx);  // waiter 引用
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

    // 发送到指定 transport
    int send_ret = luat_airlink_send2transport(cmd, mode);
    luat_airlink_cmd_free(cmd);

    if (send_ret != 0) {
        LLOGE("rpc: send2transport failed %d", send_ret);
        luat_airlink_result_unreg(pkgid);
        rpc_sync_ctx_release(ctx);  // slot 引用
        rpc_sync_ctx_release(ctx);  // waiter 引用
        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_send_fail++;
        _stats_unlock();
        return -3;
    }

    // ======== 信号量等待 ========
    int wait_ret = luat_rtos_semaphore_take(ctx->sem, timeout_ms);
    if (wait_ret != 0) {
        uint64_t elapsed_ms = luat_mcu_tick64_ms() - start_tick;
        LLOGE("rpc: timeout after %llums (pkgid=0x%llx rpc_id=0x%04X)", elapsed_ms, pkgid, rpc_id);

        if (luat_airlink_result_unreg(pkgid) == 0) {
            rpc_sync_ctx_release(ctx);  // slot
            rpc_sync_ctx_release(ctx);  // waiter
        } else {
            ctx->timed_out = 1;
            rpc_sync_ctx_release(ctx);  // waiter
        }

        _stats_lock();
        g_rpc_stats.call_total++;
        g_rpc_stats.call_timeout++;
        _stats_unlock();

        return -1;
    }

    // 成功: callback 已 sem_release + ctx_release，此处释放 waiter 引用
    uint64_t elapsed_ms = luat_mcu_tick64_ms() - start_tick;
    int result = ctx->ret_code;

    _stats_lock();
    g_rpc_stats.call_total++;
    if (result == 0) {
        g_rpc_stats.call_success++;
        _update_latency(elapsed_ms);
    } else {
        if (result == -501 || result == -502) {
            g_rpc_stats.call_decode_fail++;
            LLOGE("rpc: codec error result=%d (took %llums)", result, elapsed_ms);
        } else if (result == AIRLINK_ERR_RPC_RESP_TOO_LARGE) {
            g_rpc_stats.call_buf_overflow++;
            LLOGE("rpc: resp too large (took %llums)", elapsed_ms);
        } else {
            g_rpc_stats.call_send_fail++;
            LLOGE("rpc: result error %d (took %llums)", result, elapsed_ms);
        }
    }
    _stats_unlock();

    rpc_sync_ctx_release(ctx);  // 释放 waiter 引用
    return result;
}

/* ------------------------------------------------------------------ */
/* nanopb typed RPC layer                                               */
/* ------------------------------------------------------------------ */


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
    // 编码前预检: 请求 payload 是否超过统一上限
    if (req_desc && req) {
        size_t req_size = 0;
        if (!pb_get_encoded_size(&req_size, req_desc, req)) {
            LLOGE("rpc_nb_call: pb_get_encoded_size failed rpc_id=%04X", rpc_id);
            _stats_lock();
            g_rpc_stats.call_total++;
            g_rpc_stats.call_encode_fail++;
            _stats_unlock();
            return -4;
        }
        if (req_size > NB_ENC_BUF_SIZE) {
            LLOGE("rpc_nb_call: req payload %u exceeds NB_ENC_BUF_SIZE %u, rpc_id=%04X",
                  (unsigned)req_size, (unsigned)NB_ENC_BUF_SIZE, rpc_id);
            _stats_lock();
            g_rpc_stats.call_total++;
            g_rpc_stats.call_encode_fail++;
            _stats_unlock();
            return -5;
        }
    }

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
    // LLOGD("rpc_nb_call: encode took %ums rpc_id=0x%04X enc_len=%d", enc_ms, rpc_id, enc_len);

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
        return rc;
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
    // LLOGD("rpc_nb_call: decode took %ums rpc_id=0x%04X resp_len=%d", dec_ms, rpc_id, resp_len);
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

/* ------------------------------------------------------------------ */
/* nanopb lua_yieldk 调用 (真正同步, 无需 cwait)                         */
/* ------------------------------------------------------------------ */

// 调用前必须先检查 lua_isyieldable(L) 为 true, 否则行为未定义
// cont 会在 lua_resume 恢复协程时调用, 栈上有 raw_bytes (string) 作为参数
// cont 返回的 nresults 即成为原始 C 函数的返回值
int luat_airlink_rpc_nb_call_yield(lua_State* L, uint8_t mode, uint16_t rpc_id,
                                    const pb_msgdesc_t* req_desc, const void* req,
                                    uint32_t timeout_ms,
                                    lua_KFunction cont, lua_KContext user_ctx) {
    uint64_t start_tick = luat_mcu_tick64_ms();

    // ---- 编码请求 ----
    uint8_t* enc_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!enc_buf) {
        LLOGE("rpc_nb_call_yield: enc_buf malloc failed");
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_encode_fail++; _stats_unlock();
        return -2;
    }
    uint16_t enc_len = 0;
    if (req_desc && req) {
        pb_ostream_t ostream = pb_ostream_from_buffer(enc_buf, NB_ENC_BUF_SIZE);
        if (!pb_encode(&ostream, req_desc, req)) {
            luat_heap_free(enc_buf);
            LLOGE("rpc_nb_call_yield: pb_encode failed");
            _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_encode_fail++; _stats_unlock();
            return -4;
        }
        enc_len = (uint16_t)ostream.bytes_written;
    }

    // ---- 分配响应缓冲区 ----
    uint8_t* resp_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!resp_buf) {
        luat_heap_free(enc_buf);
        LLOGE("rpc_nb_call_yield: resp_buf malloc failed");
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_send_fail++; _stats_unlock();
        return -2;
    }

    // ---- 分配 ctx ----
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)luat_heap_malloc(sizeof(rpc_sync_ctx_t));
    if (!ctx) {
        luat_heap_free(enc_buf);
        luat_heap_free(resp_buf);
        LLOGE("rpc_nb_call_yield: ctx malloc failed");
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_send_fail++; _stats_unlock();
        return -2;
    }
    memset(ctx, 0, sizeof(rpc_sync_ctx_t));
    ctx->out_buf      = resp_buf;
    ctx->out_buf_size = NB_ENC_BUF_SIZE;
    ctx->out_len      = &ctx->_owned_out_len;
    ctx->ret_code     = -1;
    ctx->is_yield     = 2;    // 2 = lua_yieldk 模式
    ctx->start_tick   = start_tick;
    ctx->timeout_ms   = timeout_ms;
    ctx->enc_buf      = enc_buf;
    ctx->resp_buf     = resp_buf;
    ctx->coro_L       = L;
    ctx->user_cont    = cont;
    ctx->user_k_ctx   = user_ctx;
    ctx->refcnt       = 3;    // coroutine + response_slot + timer

    // ---- 创建超时定时器 ----
    if (luat_rtos_timer_create(&ctx->timeout_timer) != 0) {
        LLOGE("rpc_nb_call_yield: timer create failed");
        luat_heap_free(enc_buf);
        luat_heap_free(resp_buf);
        luat_heap_free(ctx);
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_send_fail++; _stats_unlock();
        return -2;
    }

    // ---- 生成 pkgid 并注册 result_reg ----
    uint64_t pkgid = luat_airlink_get_next_cmd_id();
    ctx->yield_pkgid = pkgid;
    luat_airlink_result_reg_t regx = {0};
    regx.tm       = luat_mcu_tick64_ms();
    regx.id       = pkgid;
    regx.userdata = ctx;
    regx.exec     = rpc_async_exec_yield;

    if (luat_airlink_result_reg(&regx) != 0) {
        LLOGE("rpc_nb_call_yield: result_reg full");
        luat_rtos_timer_delete(ctx->timeout_timer);
        rpc_sync_ctx_release(ctx);  // refcnt 3→2
        rpc_sync_ctx_release(ctx);  // refcnt 2→1
        rpc_sync_ctx_release(ctx);  // refcnt 1→0
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_send_fail++; _stats_unlock();
        return AIRLINK_ERR_RESULT_REG_FULL;
    }

    // ---- 构造 RPC cmd ----
    uint16_t cmd_data_len = 8 + 2 + 1 + enc_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(AIRLINK_CMD_RPC, cmd_data_len);
    if (!cmd) {
        LLOGE("rpc_nb_call_yield: cmd_new failed");
        luat_airlink_result_unreg(pkgid);
        luat_rtos_timer_delete(ctx->timeout_timer);
        rpc_sync_ctx_release(ctx);  // response_slot ref (unreg'd)
        rpc_sync_ctx_release(ctx);  // timer ref
        rpc_sync_ctx_release(ctx);  // coroutine ref
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_send_fail++; _stats_unlock();
        return -2;
    }
    memcpy(cmd->data,     &pkgid, 8);
    memcpy(cmd->data + 8, &rpc_id, 2);
    cmd->data[10] = AIRLINK_RPC_MSG_TYPE_REQUEST;
    if (enc_len > 0) {
        memcpy(cmd->data + 11, enc_buf, enc_len);
    }

    // ---- 启动超时定时器 (在发送之前, 避免 use-after-free 竞态) ----
    if (luat_rtos_timer_start(ctx->timeout_timer, timeout_ms, 0,
                               rpc_yield_timer_cb, ctx) != 0) {
        LLOGE("rpc_nb_call_yield: timer start failed");
        luat_airlink_cmd_free(cmd);
        luat_airlink_result_unreg(pkgid);
        luat_rtos_timer_delete(ctx->timeout_timer);
        rpc_sync_ctx_release(ctx);  // response_slot ref (unreg'd)
        rpc_sync_ctx_release(ctx);  // timer ref
        rpc_sync_ctx_release(ctx);  // coroutine ref
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_send_fail++; _stats_unlock();
        return -2;
    }

    // ---- 发送 RPC cmd ----
    int send_ret = luat_airlink_send2transport(cmd, mode);
    luat_airlink_cmd_free(cmd);

    if (send_ret != 0) {
        LLOGE("rpc_nb_call_yield: send2transport failed ret=%d", send_ret);
        // 停止定时器 (尚未 fire, 安全停止)
        luat_rtos_timer_stop(ctx->timeout_timer);
        luat_airlink_result_unreg(pkgid);
        luat_rtos_timer_delete(ctx->timeout_timer);
        rpc_sync_ctx_release(ctx);  // response_slot ref (unreg'd)
        rpc_sync_ctx_release(ctx);  // timer ref
        rpc_sync_ctx_release(ctx);  // coroutine ref
        _stats_lock(); g_rpc_stats.call_total++; g_rpc_stats.call_send_fail++; _stats_unlock();
        return -3;
    }

    // ---- 加入 yield 链表 (用于 shutdown 清理) ----
    if (g_yield_list_mutex == NULL) {
        luat_rtos_mutex_create(&g_yield_list_mutex);
    }
    luat_rtos_mutex_lock(g_yield_list_mutex, 1000);
    ctx->yield_next = g_yield_list;
    g_yield_list = ctx;
    luat_rtos_mutex_unlock(g_yield_list_mutex);

    // lua_yieldk 挂起协程, 响应到达后由 rpc_yield_cont → user_cont 链式恢复
    return lua_yieldk(L, 0, (lua_KContext)ctx, rpc_yield_cont);
}

/* 清理所有活跃 yield ctx 中协程已死亡的条目 (用于 shutdown / task delete) */
void luat_airlink_rpc_cleanup_dead_yields(void) {
    if (g_yield_list_mutex == NULL) {
        luat_rtos_mutex_create(&g_yield_list_mutex);
    }
    luat_rtos_mutex_lock(g_yield_list_mutex, 1000);
    // 收集已死亡协程的 ctx (从链表中移除, is_yield 置 0 防止 rpc_sync_ctx_release 重复操作)
    rpc_sync_ctx_t* dead_list = NULL;
    rpc_sync_ctx_t** p = &g_yield_list;
    while (*p) {
        rpc_sync_ctx_t* ctx = *p;
        if (ctx->is_yield == 2 && ctx->coro_L &&
            lua_status(ctx->coro_L) != LUA_YIELD) {
            *p = ctx->yield_next;       // 从链表中移除
            ctx->is_yield = 0;          // 禁止 rpc_sync_ctx_release 再操作链表/定时器
            ctx->yield_next = dead_list;
            dead_list = ctx;
        } else {
            p = &(*p)->yield_next;
        }
    }
    luat_rtos_mutex_unlock(g_yield_list_mutex);

    // 在锁外清理 (避免与 rpc_sync_ctx_release 死锁)
    while (dead_list) {
        rpc_sync_ctx_t* ctx = dead_list;
        dead_list = dead_list->yield_next;

        ctx->handled = 1;
        ctx->timed_out = 1;
        luat_airlink_result_unreg(ctx->yield_pkgid);
        luat_rtos_timer_stop(ctx->timeout_timer);
        luat_rtos_timer_delete(ctx->timeout_timer);
        while (ctx->refcnt > 1) {
            rpc_sync_ctx_release(ctx);
        }
        rpc_sync_ctx_release(ctx);  // 最后一次释放 (refcnt 1→0)
    }
}

void luat_airlink_rpc_print_stats(void) {
    luat_airlink_rpc_stats_t stats;
    luat_airlink_rpc_latency_t latency;
    luat_airlink_rpc_perf_t perf;
    
    luat_airlink_rpc_get_stats(&stats);
    luat_airlink_rpc_get_perf(&latency, &perf);
    
    LLOGI("=== RPC Statistics ===");
    LLOGI("Call: total=%llu success=%llu timeout=%llu send_fail=%llu encode_fail=%llu decode_fail=%llu buf_overflow=%llu",
          stats.call_total, stats.call_success, stats.call_timeout,
          stats.call_send_fail, stats.call_encode_fail, stats.call_decode_fail,
          stats.call_buf_overflow);
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

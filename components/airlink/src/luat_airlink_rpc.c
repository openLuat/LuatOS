/*
 * AirLink RPC 框架 (通用同步调用模板)
 *
 * 使用方式:
 *   服务端: luat_airlink_rpc_register(rpc_id, handler, userdata)
 *   调用方: luat_airlink_rpc(mode, rpc_id, req, req_len, resp, resp_size, &resp_len, timeout_ms)
 *
 * 线格式:
 *   请求 cmd 0x30: [pkgid:8][rpc_id:2][req payload]
 *   响应 cmd 0x08: [new_pkgid:8][req_pkgid:8][result_code:2][resp payload]
 *                                ^^^^^^^^^^^^^^^^^^^^^^^^^^^
 *                                luat_airlink_result_send 中 buff 参数
 */

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_rtos.h"
#include "luat_mem.h"
#include "luat_mcu.h"

#ifdef LUAT_USE_AIRLINK_RPC

#define LUAT_LOG_TAG "airlink.rpc"
#include "luat_log.h"

/* ------------------------------------------------------------------ */
/* RPC handler 注册表                                                   */
/* ------------------------------------------------------------------ */

static luat_airlink_rpc_reg_t s_rpc_regs[LUAT_AIRLINK_RPC_MAX_HANDLERS];
static luat_rtos_mutex_t s_rpc_reg_mutex = NULL;

static void rpc_reg_init(void) {
    if (s_rpc_reg_mutex == NULL) {
        luat_rtos_mutex_create(&s_rpc_reg_mutex);
    }
}

int luat_airlink_rpc_register(uint16_t rpc_id, luat_airlink_rpc_handler_t handler, void* userdata) {
    rpc_reg_init();
    luat_rtos_mutex_lock(s_rpc_reg_mutex, 1000);
    // 检查是否已存在相同 rpc_id
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (s_rpc_regs[i].active && s_rpc_regs[i].rpc_id == rpc_id) {
            s_rpc_regs[i].handler   = handler;
            s_rpc_regs[i].userdata  = userdata;
            luat_rtos_mutex_unlock(s_rpc_reg_mutex);
            return 0;
        }
    }
    // 找空槽位
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (!s_rpc_regs[i].active) {
            s_rpc_regs[i].rpc_id   = rpc_id;
            s_rpc_regs[i].handler  = handler;
            s_rpc_regs[i].userdata = userdata;
            s_rpc_regs[i].active   = 1;
            luat_rtos_mutex_unlock(s_rpc_reg_mutex);
            return 0;
        }
    }
    luat_rtos_mutex_unlock(s_rpc_reg_mutex);
    LLOGE("rpc_register: 注册表已满 (max %d)", LUAT_AIRLINK_RPC_MAX_HANDLERS);
    return -1;
}

int luat_airlink_rpc_unregister(uint16_t rpc_id) {
    rpc_reg_init();
    luat_rtos_mutex_lock(s_rpc_reg_mutex, 1000);
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (s_rpc_regs[i].active && s_rpc_regs[i].rpc_id == rpc_id) {
            memset(&s_rpc_regs[i], 0, sizeof(luat_airlink_rpc_reg_t));
            luat_rtos_mutex_unlock(s_rpc_reg_mutex);
            return 0;
        }
    }
    luat_rtos_mutex_unlock(s_rpc_reg_mutex);
    return -1;
}

/* 服务端调用：查找 handler 并调用，返回 handler 的返回值 */
int luat_airlink_rpc_dispatch(uint16_t rpc_id,
                               const uint8_t* req, uint16_t req_len,
                               uint8_t* resp, uint16_t resp_size, uint16_t* resp_len) {
    rpc_reg_init();
    luat_rtos_mutex_lock(s_rpc_reg_mutex, 1000);
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (s_rpc_regs[i].active && s_rpc_regs[i].rpc_id == rpc_id) {
            luat_airlink_rpc_handler_t handler = s_rpc_regs[i].handler;
            void* userdata = s_rpc_regs[i].userdata;
            luat_rtos_mutex_unlock(s_rpc_reg_mutex);
            return handler(rpc_id, req, req_len, resp, resp_size, resp_len, userdata);
        }
    }
    luat_rtos_mutex_unlock(s_rpc_reg_mutex);
    return -404; // handler not found
}

/* ------------------------------------------------------------------ */
/* 同步等待上下文                                                        */
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

    if (ctx->timed_out) {
        // 调用方已超时并放弃等待，由 callback 释放资源
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return;
    }

    // cmd->data 格式: [new_pkgid:8][req_pkgid:8][result_code:2][resp payload]
    if (cmd->len >= 18) {
        int16_t result_code = 0;
        memcpy(&result_code, cmd->data + 16, 2);
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

    // 分配同步上下文
    rpc_sync_ctx_t* ctx = (rpc_sync_ctx_t*)luat_heap_malloc(sizeof(rpc_sync_ctx_t));
    if (ctx == NULL) {
        LLOGE("rpc: malloc ctx failed");
        return -2;
    }
    memset(ctx, 0, sizeof(rpc_sync_ctx_t));
    ctx->out_buf      = resp;
    ctx->out_buf_size = resp_size;
    ctx->out_len      = resp_len;
    ctx->ret_code     = -1;
    ctx->timed_out    = 0;

    if (luat_rtos_semaphore_create(&ctx->sem, 0) != 0) {
        LLOGE("rpc: semaphore create failed");
        luat_heap_free(ctx);
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
        return -2;
    }

    // 构造 RPC cmd: [pkgid:8][rpc_id:2][req payload]
    uint16_t cmd_data_len = 8 + 2 + req_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(AIRLINK_CMD_RPC, cmd_data_len);
    if (cmd == NULL) {
        LLOGE("rpc: malloc cmd failed");
        luat_airlink_result_unreg(pkgid);
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return -2;
    }
    memcpy(cmd->data,     &pkgid, 8);
    memcpy(cmd->data + 8, &rpc_id, 2);
    if (req && req_len > 0) {
        memcpy(cmd->data + 10, req, req_len);
    }

    // 发送到指定 transport
    int send_ret = luat_airlink_send2transport(cmd, mode);
    luat_airlink_cmd_free(cmd);

    if (send_ret != 0) {
        LLOGE("rpc: send2transport failed %d", send_ret);
        luat_airlink_result_unreg(pkgid);
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return -3;
    }

    // 阻塞等待
    int wait_ret = luat_rtos_semaphore_take(ctx->sem, timeout_ms);
    if (wait_ret != 0) {
        // 超时：尝试从注册表清理 result_reg slot
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
        return -1; // timeout
    }

    // 成功
    int result = ctx->ret_code;
    luat_rtos_semaphore_delete(ctx->sem);
    luat_heap_free(ctx);
    return result;
}

#endif /* LUAT_USE_AIRLINK_RPC */

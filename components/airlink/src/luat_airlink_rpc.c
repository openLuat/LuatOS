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
#include "pb_encode.h"
#include "pb_decode.h"

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

    // 构造 RPC cmd: [pkgid:8][rpc_id:2][msg_type:1][req payload]
    uint16_t cmd_data_len = 8 + 2 + 1 + req_len;
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

/* ------------------------------------------------------------------ */
/* nanopb typed RPC layer                                               */
/* ------------------------------------------------------------------ */

#define NB_ENC_BUF_SIZE  768  // nanopb encode/decode 临时缓冲区大小 (UartRpcRequest 最大 518 字节)

static luat_airlink_rpc_nb_reg_t s_nb_regs[LUAT_AIRLINK_RPC_MAX_HANDLERS];
static luat_rtos_mutex_t s_nb_reg_mutex = NULL;

static void nb_reg_init(void) {
    if (s_nb_reg_mutex == NULL) {
        luat_rtos_mutex_create(&s_nb_reg_mutex);
    }
}

int luat_airlink_rpc_nb_register(uint16_t rpc_id,
                                  const pb_msgdesc_t* req_desc, size_t req_size,
                                  const pb_msgdesc_t* resp_desc, size_t resp_size,
                                  luat_airlink_rpc_nb_handler_t handler,
                                  luat_airlink_rpc_nb_notify_handler_t notify_handler,
                                  void* userdata) {
    nb_reg_init();
    luat_rtos_mutex_lock(s_nb_reg_mutex, 1000);
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (s_nb_regs[i].active && s_nb_regs[i].rpc_id == rpc_id) {
            s_nb_regs[i].req_desc       = req_desc;
            s_nb_regs[i].req_size       = req_size;
            s_nb_regs[i].resp_desc      = resp_desc;
            s_nb_regs[i].resp_size      = resp_size;
            s_nb_regs[i].handler        = handler;
            s_nb_regs[i].notify_handler = notify_handler;
            s_nb_regs[i].userdata       = userdata;
            luat_rtos_mutex_unlock(s_nb_reg_mutex);
            return 0;
        }
    }
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (!s_nb_regs[i].active) {
            s_nb_regs[i].rpc_id         = rpc_id;
            s_nb_regs[i].req_desc       = req_desc;
            s_nb_regs[i].req_size       = req_size;
            s_nb_regs[i].resp_desc      = resp_desc;
            s_nb_regs[i].resp_size      = resp_size;
            s_nb_regs[i].handler        = handler;
            s_nb_regs[i].notify_handler = notify_handler;
            s_nb_regs[i].userdata       = userdata;
            s_nb_regs[i].active         = 1;
            luat_rtos_mutex_unlock(s_nb_reg_mutex);
            return 0;
        }
    }
    luat_rtos_mutex_unlock(s_nb_reg_mutex);
    LLOGE("rpc_nb_register: 注册表已满");
    return -1;
}

int luat_airlink_rpc_nb_unregister(uint16_t rpc_id) {
    nb_reg_init();
    luat_rtos_mutex_lock(s_nb_reg_mutex, 1000);
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (s_nb_regs[i].active && s_nb_regs[i].rpc_id == rpc_id) {
            memset(&s_nb_regs[i], 0, sizeof(luat_airlink_rpc_nb_reg_t));
            luat_rtos_mutex_unlock(s_nb_reg_mutex);
            return 0;
        }
    }
    luat_rtos_mutex_unlock(s_nb_reg_mutex);
    return -1;
}

/* 服务端调用: 查找 nanopb typed handler 并调用 (含 decode/encode), 返回 0=找到并处理, -404=未找到 */
int luat_airlink_rpc_nb_dispatch(uint16_t rpc_id, uint8_t msg_type,
                                  const uint8_t* req_bytes, uint16_t req_len,
                                  uint8_t* resp_bytes, uint16_t resp_size, uint16_t* resp_len) {
    nb_reg_init();
    luat_rtos_mutex_lock(s_nb_reg_mutex, 1000);
    luat_airlink_rpc_nb_reg_t entry = {0};
    int found = 0;
    for (int i = 0; i < LUAT_AIRLINK_RPC_MAX_HANDLERS; i++) {
        if (s_nb_regs[i].active && s_nb_regs[i].rpc_id == rpc_id) {
            entry = s_nb_regs[i];
            found = 1;
            break;
        }
    }
    luat_rtos_mutex_unlock(s_nb_reg_mutex);

    if (!found) return -404;

    if (msg_type == AIRLINK_RPC_MSG_TYPE_NOTIFY) {
        if (entry.notify_handler && entry.req_desc && entry.req_size > 0) {
            void* msg_struct = luat_heap_malloc(entry.req_size);
            if (msg_struct) {
                memset(msg_struct, 0, entry.req_size);
                pb_istream_t istream = pb_istream_from_buffer(req_bytes, req_len);
                pb_decode(&istream, entry.req_desc, msg_struct);
                entry.notify_handler(rpc_id, msg_struct, entry.userdata);
                luat_heap_free(msg_struct);
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
    uint8_t* enc_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!enc_buf) {
        LLOGE("rpc_nb_call: malloc enc_buf failed");
        return -2;
    }
    uint16_t enc_len = 0;
    if (req_desc && req) {
        pb_ostream_t ostream = pb_ostream_from_buffer(enc_buf, NB_ENC_BUF_SIZE);
        if (!pb_encode(&ostream, req_desc, req)) {
            LLOGE("rpc_nb_call: pb_encode req failed rpc_id=%04X", rpc_id);
            luat_heap_free(enc_buf);
            return -4;
        }
        enc_len = (uint16_t)ostream.bytes_written;
    }

    // 分配响应缓冲区
    uint8_t* resp_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!resp_buf) {
        LLOGE("rpc_nb_call: malloc resp_buf failed");
        luat_heap_free(enc_buf);
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
    if (resp_desc && resp && resp_len > 0) {
        pb_istream_t istream = pb_istream_from_buffer(resp_buf, resp_len);
        if (!pb_decode(&istream, resp_desc, resp)) {
            LLOGE("rpc_nb_call: pb_decode resp failed rpc_id=%04X", rpc_id);
            luat_heap_free(resp_buf);
            return -4;
        }
    }
    luat_heap_free(resp_buf);
    return 0;
}

int luat_airlink_rpc_nb_notify(uint8_t mode, uint16_t rpc_id,
                                const pb_msgdesc_t* desc, const void* msg) {
    // 编码消息
    uint8_t* enc_buf = (uint8_t*)luat_heap_malloc(NB_ENC_BUF_SIZE);
    if (!enc_buf) {
        LLOGE("rpc_nb_notify: malloc failed");
        return -2;
    }
    uint16_t enc_len = 0;
    if (desc && msg) {
        pb_ostream_t ostream = pb_ostream_from_buffer(enc_buf, NB_ENC_BUF_SIZE);
        if (!pb_encode(&ostream, desc, msg)) {
            LLOGE("rpc_nb_notify: pb_encode failed rpc_id=%04X", rpc_id);
            luat_heap_free(enc_buf);
            return -4;
        }
        enc_len = (uint16_t)ostream.bytes_written;
    }

    // 构造 NOTIFY cmd: [pkgid=0:8][rpc_id:2][msg_type=NOTIFY:1][payload]
    uint16_t cmd_data_len = 8 + 2 + 1 + enc_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(AIRLINK_CMD_RPC, cmd_data_len);
    if (!cmd) {
        LLOGE("rpc_nb_notify: malloc cmd failed");
        luat_heap_free(enc_buf);
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
    if (ret != 0) {
        LLOGE("rpc_nb_notify: send2transport failed %d", ret);
        return -3;
    }
    return 0;
}

#endif /* LUAT_USE_AIRLINK_RPC */

#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_airlink_result.h"
#include "luat_airlink_ping.h"
#include "luat_airlink_transport.h"
#include "luat_rtos.h"
#include "luat_mcu.h"
#include "luat_malloc.h"

#define LUAT_LOG_TAG "airlink.ping"
#include "luat_log.h"

typedef struct {
    luat_rtos_semaphore_t sem;
    uint64_t rtt_ms;
    uint8_t* echo_buf;
    uint16_t echo_buf_size;
    uint16_t echo_len;
    int ret_code;
    volatile uint8_t timed_out;
} ping_sync_ctx_t;

// Called under reg_mutex when pong arrives
static void ping_sync_exec(struct luat_airlink_result_reg* reg, luat_airlink_cmd_t* cmd) {
    ping_sync_ctx_t* ctx = (ping_sync_ctx_t*)reg->userdata;

    if (ctx->timed_out) {
        // Caller already timed out and abandoned the slot; we clean up
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return;
    }

    // pong wire format: [pkgid:8][send_tick_ms:8][payload_len:2][payload:N]
    if (cmd->len >= 18) {
        uint64_t send_tick = 0;
        memcpy(&send_tick, cmd->data + 8, 8);
        ctx->rtt_ms = luat_mcu_tick64_ms() - send_tick;

        uint16_t payload_len = 0;
        memcpy(&payload_len, cmd->data + 16, 2);

        uint16_t actual = cmd->len - 18;
        if (payload_len > actual) payload_len = actual;
        if (payload_len > ctx->echo_buf_size) payload_len = ctx->echo_buf_size;

        if (ctx->echo_buf && payload_len > 0) {
            memcpy(ctx->echo_buf, cmd->data + 18, payload_len);
        }
        ctx->echo_len = payload_len;
        ctx->ret_code = 0;
    } else {
        ctx->ret_code = -4; // malformed pong
        ctx->echo_len = 0;
    }

    luat_rtos_semaphore_release(ctx->sem);
}

int luat_airlink_ping_raw(uint8_t mode, uint64_t pkgid,
                          const uint8_t* payload, uint16_t payload_len,
                          uint32_t timeout_ms,
                          uint64_t* rtt_ms_out,
                          uint8_t* echo_buf, uint16_t echo_buf_size,
                          uint16_t* echo_len_out) {
    if (rtt_ms_out) *rtt_ms_out = 0;
    if (echo_len_out) *echo_len_out = 0;

    ping_sync_ctx_t* ctx = (ping_sync_ctx_t*)luat_heap_malloc(sizeof(ping_sync_ctx_t));
    if (!ctx) {
        LLOGE("ping: malloc ctx failed");
        return -2;
    }
    memset(ctx, 0, sizeof(ping_sync_ctx_t));
    ctx->echo_buf = echo_buf;
    ctx->echo_buf_size = echo_buf_size;
    ctx->ret_code = -1;

    if (luat_rtos_semaphore_create(&ctx->sem, 0) != 0) {
        LLOGE("ping: semaphore create failed");
        luat_heap_free(ctx);
        return -2;
    }

    luat_airlink_result_reg_t reg = {0};
    reg.tm       = luat_mcu_tick64_ms();
    reg.id       = pkgid;
    reg.userdata = ctx;
    reg.exec     = ping_sync_exec;

    if (luat_airlink_result_reg(&reg) != 0) {
        LLOGE("ping: result_reg full");
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return -2;
    }

    // Build ping cmd: [pkgid:8][send_tick_ms:8][payload_len:2][payload:N]
    uint16_t cmd_data_len = 8 + 8 + 2 + payload_len;
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x01, cmd_data_len);
    if (!cmd) {
        LLOGE("ping: malloc cmd failed");
        luat_airlink_result_unreg(pkgid);
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return -2;
    }

    uint64_t now = luat_mcu_tick64_ms();
    memcpy(cmd->data,      &pkgid,       8);
    memcpy(cmd->data + 8,  &now,         8);
    memcpy(cmd->data + 16, &payload_len, 2);
    if (payload && payload_len > 0) {
        memcpy(cmd->data + 18, payload, payload_len);
    }

    int send_ret = luat_airlink_send2transport(cmd, mode);
    luat_airlink_cmd_free(cmd);

    if (send_ret != 0) {
        LLOGE("ping: send2transport failed %d", send_ret);
        luat_airlink_result_unreg(pkgid);
        luat_rtos_semaphore_delete(ctx->sem);
        luat_heap_free(ctx);
        return -3;
    }

    // Block until pong arrives or timeout
    int wait_ret = luat_rtos_semaphore_take(ctx->sem, timeout_ms);
    if (wait_ret != 0) {
        LLOGE("ping: timeout (pkgid=0x%llx)", (unsigned long long)pkgid);
        if (luat_airlink_result_unreg(pkgid) == 0) {
            // We cleared the slot; callback will not fire
            luat_rtos_semaphore_delete(ctx->sem);
            luat_heap_free(ctx);
        } else {
            // Callback already fired (or is racing); let it handle cleanup
            ctx->timed_out = 1;
            luat_rtos_semaphore_delete(ctx->sem);
            luat_heap_free(ctx);
        }
        return -1; // timeout
    }

    int result = ctx->ret_code;
    if (result == 0) {
        if (rtt_ms_out)  *rtt_ms_out  = ctx->rtt_ms;
        if (echo_len_out) *echo_len_out = ctx->echo_len;
    }
    luat_rtos_semaphore_delete(ctx->sem);
    luat_heap_free(ctx);
    return result;
}

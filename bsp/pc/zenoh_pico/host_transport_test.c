/* SPDX-License-Identifier: MIT */
/* AI-MANAGED: true */
/* 真实socketpair上的network API完成等待模型；不模拟对端回包或目标TCP ACK。 */
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>
#include <stdatomic.h>
#include <time.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <sys/socket.h>
/* libc堆桥先定义，避免c_common的malloc映射递归。 */
void *luat_heap_malloc(size_t n) { return malloc(n); }
void luat_heap_free(void *p) { free(p); }
#include "luat_zenoh_pico.h"
#include "luat_network_adapter.h"
#include "luat_mcu.h"
#include "zenoh-pico/system/link/tcp.h"

enum { FULL, SHORT_ZERO, PENDING, SHORT_PENDING, MIXED, DELAYED_COMPLETION,
       ZERO, ZERO_PENDING, PARTIAL_ERROR, BAD_RC, BAD_LENGTH };
static int mode, peer_fd = -1, budget;
static unsigned calls, after_fault, blocked_calls;
static int failed;
static luat_zp_io_failure_t diagnostic;
static uint64_t accepted;
static luat_event_t notices[16];
static unsigned notice_head, notice_count, notice_peak, notice_overflows, notice_reads;
static unsigned notice_refill;
static int missing_task;
static int notice(uint32_t id, uint32_t value) {
    if (notice_count == 16) { ++notice_overflows; return -1; }
    luat_event_t e = {0}; e.id = id; e.param1 = value;
    notices[(notice_head + notice_count++) % 16] = e;
    if (notice_count > notice_peak) notice_peak = notice_count;
    return 0;
}
int luat_rtos_event_recv(luat_rtos_task_handle task, uint32_t id, luat_event_t *out,
                         luat_rtos_event_wait_callback_t *callback, uint32_t timeout) {
    (void)callback;
    /* 目标EC7xx空邮箱的0会无界等待。主机明确失败，不能用空队列返回掩盖它。 */
    if (!timeout || timeout == LUAT_WAIT_FOREVER) {
        fputs("UNBOUNDED_EVENT_WAIT_REQUEST\n", stderr); exit(86);
    }
    if (!task || id || timeout != 1 || !out) return -1;
    if (!notice_count) return -1;
    *out = notices[notice_head]; notice_head = (notice_head + 1) % 16;
    --notice_count; ++notice_reads;
    /* 消费期间再到达一个事件，以16槽输入验证17条累计通知预算。 */
    if (notice_refill) { --notice_refill; notice(EV_NW_RESULT_EVENT, 0); }
    return 0;
}

uint64_t luat_mcu_tick64_ms(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec * 1000 + (uint64_t)t.tv_nsec / 1000000;
}
void luat_rtos_task_sleep(uint32_t ms) {
    struct timespec t = {ms / 1000, (long)(ms % 1000) * 1000000};
    while (nanosleep(&t, &t) && errno == EINTR) {}
}
luat_rtos_task_handle luat_rtos_get_current_handle(void) { return missing_task ? NULL : (void *)(uintptr_t)1; }
int luat_zenoh_pico_adapter(void) { return 0; }
int luat_zenoh_pico_rng_failed(void) { return 0; }
int luat_zenoh_pico_io_failed(void) { return failed; }
void luat_zenoh_pico_io_progress(int sending, size_t n) { if (sending && !failed) accepted += n; }
void luat_zenoh_pico_io_fail_at(const char *stage, int rc, size_t requested,
                              size_t transferred, uint64_t elapsed) {
    if (failed) return;
    failed = 1; diagnostic.stage = stage; diagnostic.rc = rc;
    diagnostic.requested = requested; diagnostic.transferred = transferred;
    diagnostic.elapsed_ms = elapsed; diagnostic.total_tx = accepted;
}
void luat_zenoh_pico_io_fail(void) { luat_zenoh_pico_io_fail_at("unspecified", -1, 0, 0, 0); }
network_ctrl_t *network_alloc_ctrl(uint8_t adapter) {
    if (adapter) return NULL;
    network_ctrl_t *c = luat_heap_malloc(sizeof(*c));
    if (c) { memset(c, 0, sizeof(*c)); c->socket_id = -1; }
    return c;
}
void network_init_ctrl(network_ctrl_t *c, HANDLE task, CBFuncEx_t callback, void *parameter) {
    c->task_handle = task; c->user_callback = callback; c->user_data = parameter;
}
void network_set_base_mode(network_ctrl_t *c, uint8_t tcp, uint32_t timeout,
                           uint8_t keep, uint32_t idle, uint8_t interval, uint8_t count) {
    (void)keep; (void)idle; (void)interval; (void)count;
    c->is_tcp = tcp; c->tcp_timeout_ms = timeout;
}
int network_connect(network_ctrl_t *c, const char *host, uint32_t length, luat_ip_addr_t *ip,
                    uint16_t port, uint32_t timeout) {
    (void)host; (void)length; (void)ip; (void)port; (void)timeout;
    int pair[2];
    if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair)) return -1;
    if (fcntl(pair[0], F_SETFL, O_NONBLOCK) < 0) { close(pair[0]); close(pair[1]); return -1; }
    c->socket_id = pair[0]; peer_fd = pair[1]; c->state = NW_STATE_ONLINE;
    return 0;
}
int network_close(network_ctrl_t *c, uint32_t timeout) {
    (void)timeout;
    if (c->socket_id >= 0) { close(c->socket_id); c->socket_id = -1; }
    return 0;
}
void network_force_close_socket(network_ctrl_t *c) { network_close(c, 0); }
void network_release_ctrl(network_ctrl_t *c) { network_close(c, 0); luat_heap_free(c); }
int network_rx(network_ctrl_t *c, uint8_t *p, uint32_t n, int flags, luat_ip_addr_t *ip,
               uint16_t *port, uint32_t *got) {
    (void)c; (void)p; (void)n; (void)flags; (void)ip; (void)port; *got = 0; return 0;
}
int network_tx(network_ctrl_t *c, const uint8_t *p, uint32_t n, int flags, luat_ip_addr_t *ip,
               uint16_t port, uint32_t *sent, uint32_t timeout) {
    (void)flags; (void)ip; (void)port;
    ++calls; *sent = 0;
    if (failed) { ++after_fault; return -1; }
    if (timeout) ++blocked_calls;
    if (mode == BAD_RC) return 2;
    if (mode == BAD_LENGTH) { *sent = n + 1; return 1; }
    if (mode == ZERO || mode == ZERO_PENDING) return mode == ZERO ? 0 : 1;
    if (mode == PARTIAL_ERROR && !budget) return -1;
    uint32_t limit = n;
    if ((mode == SHORT_ZERO || mode == SHORT_PENDING || mode == MIXED) && limit > 17) limit = 17;
    if (mode == PARTIAL_ERROR && limit > (uint32_t)budget) limit = (uint32_t)budget;
    ssize_t rc = send(c->socket_id, p, limit, 0);
    if (rc < 0) return -1;
    *sent = (uint32_t)rc;
    if (*sent && !timeout && notice(EV_NW_RESULT_TX, 0)) return -1;
    if (mode == PARTIAL_ERROR) budget -= (int)*sent;
    /* 数据已真实进入socket；只有阻塞调用等待模型完成，非阻塞以1报告待完成。 */
    if (mode == DELAYED_COMPLETION && timeout) {
        luat_rtos_task_sleep(timeout < 150 ? timeout : 150);
        return timeout < 150 ? -1 : 0;
    }
    if (mode == PENDING || mode == SHORT_PENDING || mode == PARTIAL_ERROR ||
        mode == DELAYED_COMPLETION || (mode == MIXED && (calls & 1))) return 1;
    return 0;
}

#define CHECK(x) do { if (!(x)) { fprintf(stderr, "ASSERT line=%d: %s\n", __LINE__, #x); return 1; } } while (0)
static uint8_t payload[4096];
static int receive_exact(const uint8_t *wanted, size_t n) {
    uint8_t bytes[4097]; size_t used = 0;
    uint64_t deadline = luat_mcu_tick64_ms() + 200;
    while (used < n && luat_mcu_tick64_ms() < deadline) {
        ssize_t rc = recv(peer_fd, bytes + used, sizeof(bytes) - used, MSG_DONTWAIT);
        if (rc > 0) used += (size_t)rc;
        else if (rc < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) luat_rtos_task_sleep(1);
        else break;
    }
    CHECK(used == n && !memcmp(bytes, wanted, n));
    CHECK(recv(peer_fd, bytes, sizeof(bytes), MSG_DONTWAIT) < 0 &&
          (errno == EAGAIN || errno == EWOULDBLOCK));
    return 0;
}
static int expect_success(_z_sys_net_socket_t s) {
    uint64_t start = luat_mcu_tick64_ms();
    size_t sent = _z_send_tcp(s, payload, sizeof(payload));
    CHECK(sent == sizeof(payload));
    CHECK(!failed && accepted == sizeof(payload));
    CHECK(!after_fault);
    CHECK(luat_mcu_tick64_ms() - start < 1000);
    CHECK(receive_exact(payload, sizeof(payload)) == 0);
    return 0;
}
static int expect_zero_deadline(_z_sys_net_socket_t s) {
    uint64_t start = luat_mcu_tick64_ms();
    CHECK(_z_send_tcp(s, payload, sizeof(payload)) == SIZE_MAX);
    uint64_t elapsed = luat_mcu_tick64_ms() - start;
    CHECK(failed && !strcmp(diagnostic.stage, "tx_timeout"));
    CHECK(diagnostic.requested == sizeof(payload) && diagnostic.transferred == 0);
    CHECK(elapsed >= 100 && elapsed < 1000 && calls > 1 && calls < 500);
    CHECK(!after_fault && accepted == 0);
    return 0;
}
static int expect_partial_error(_z_sys_net_socket_t s) {
    CHECK(_z_send_tcp(s, payload, sizeof(payload)) == SIZE_MAX);
    CHECK(failed && !strcmp(diagnostic.stage, "tx_error") && diagnostic.rc == -1);
    CHECK(diagnostic.transferred == 5 && diagnostic.total_tx == 5);
    CHECK(receive_exact(payload, 5) == 0);
    unsigned before = calls;
    CHECK(_z_send_tcp(s, payload, sizeof(payload)) == SIZE_MAX);
    CHECK(calls == before && !after_fault);
    return 0;
}
static int expect_invalid(_z_sys_net_socket_t s) {
    CHECK(_z_send_tcp(s, payload, sizeof(payload)) == SIZE_MAX);
    CHECK(failed && !strcmp(diagnostic.stage, "tx_error"));
    CHECK(diagnostic.transferred == 0 && !after_fault);
    return 0;
}
static int expect_unknown_event(_z_sys_net_socket_t s) {
    CHECK(notice(0x17, 0) == 0);
    CHECK(_z_send_tcp(s, payload, sizeof(payload)) == SIZE_MAX);
    CHECK(failed && !strcmp(diagnostic.stage, "event_unexpected") && calls == 0);
    return 0;
}
static int expect_receive_events(_z_sys_net_socket_t s) {
    const unsigned counts[] = {0, 1, 15, 16, 17};
    uint8_t byte;
    for (unsigned c = 0; c < sizeof(counts) / sizeof(counts[0]); ++c) {
        unsigned count = counts[c], before = notice_reads;
        for (unsigned i = 0; i < count && i < 16; ++i) CHECK(notice(EV_NW_RESULT_EVENT, 0) == 0);
        notice_refill = count > 16;
        CHECK(_z_read_tcp(s, &byte, 1) == SIZE_MAX);
        CHECK(!failed && notice_reads - before == (count < 16 ? count : 16));
        CHECK(notice_count == (count > 16 ? 1u : 0u));
        CHECK(_z_read_tcp(s, &byte, 1) == SIZE_MAX);
        CHECK(!failed && notice_count == 0 && notice_reads - before == count);
    }
    return 0;
}
static int expect_empty(_z_sys_net_socket_t s) {
    CHECK(_z_send_tcp(s, payload, 0) == 0 && calls == 0 && !failed); return 0;
}
int main(void) {
    _z_sys_net_socket_t no_task = {0}; _z_sys_net_endpoint_t endpoint = {0};
    missing_task = 1;
    CHECK(_z_open_tcp(&no_task, endpoint, 100) != 0 && !no_task.context);
    CHECK(failed && !strcmp(diagnostic.stage, "event_task"));
    missing_task = 0;
    puts("CONTRACT_PASS missing_task_rejected");
    for (size_t i = 0; i < sizeof(payload); ++i) payload[i] = (uint8_t)(i * 17 + i / 256);
    struct { const char *name; int mode; int (*test)(_z_sys_net_socket_t); } cases[] = {
        {"partial_rc0_4096", SHORT_ZERO, expect_success},
        {"pending_rc1_4096", PENDING, expect_success},
        {"partial_pending_rc1_4096", SHORT_PENDING, expect_success},
        {"mixed_rc0_rc1_4096", MIXED, expect_success},
        {"accepted_before_delayed_completion", DELAYED_COMPLETION, expect_success},
        {"zero_rc0_total_deadline", ZERO, expect_zero_deadline},
        {"zero_rc1_total_deadline", ZERO_PENDING, expect_zero_deadline},
        {"partial_failure_no_duplicate", PARTIAL_ERROR, expect_partial_error},
        {"unexpected_rc_rejected", BAD_RC, expect_invalid},
        {"oversized_count_rejected", BAD_LENGTH, expect_invalid},
        {"empty_write_no_call", FULL, expect_empty},
        {"unknown_private_event_is_failure", FULL, expect_unknown_event},
        {"receive_consumes_notices", FULL, expect_receive_events}
    };
    unsigned failures = 0;
    for (size_t i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        mode = cases[i].mode; calls = after_fault = blocked_calls = 0;
        failed = 0; accepted = 0; budget = 5; memset(&diagnostic, 0, sizeof(diagnostic));
        notice_overflows = notice_reads = 0; notice_peak = notice_count;
        _z_sys_net_socket_t s = {0}; _z_sys_net_endpoint_t ep = {0};
        if (_z_open_tcp(&s, ep, 100)) return 2;
        int rc = cases[i].test(s);
        printf("CONTRACT_%s %s calls=%u blocking_calls=%u accepted=%llu\n",
               rc ? "FAIL" : "PASS", cases[i].name, calls, blocked_calls, (unsigned long long)accepted);
        failures += rc != 0; _z_close_tcp(&s); close(peer_fd); peer_fd = -1;
        printf("NOTICE_END queued=%u read=%u peak=%u overflows=%u\n",
               notice_count, notice_reads, notice_peak, notice_overflows);
        if (notice_count || notice_overflows) { ++failures; notice_count = notice_head = 0; }
        /* 迟到旧代结果不能污染下一次open；只保留通知副本，不保留旧指针。 */
        if (i + 1 < sizeof(cases) / sizeof(cases[0])) notice(EV_NW_RESULT_EVENT, (uint32_t)-1);
    }
    printf("TRANSPORT_CONTRACT_DONE checks=%zu failures=%u scope=real_socket_API_model_not_RTOS_ACK\n",
           sizeof(cases) / sizeof(cases[0]), failures);
    return failures ? 1 : 0;
}

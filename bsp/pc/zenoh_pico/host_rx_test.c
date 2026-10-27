/* SPDX-License-Identifier: MIT */
/* AI-MANAGED: true */
/* 组合既有13项真实socket合同，新增有限短读/错误与字节守恒反例。 */
#define main tx_contract_main
#define network_rx test_empty_rx
#define luat_zenoh_pico_io_progress test_tx_progress
#define luat_zenoh_pico_io_fail_at test_tx_fail_at
#include "host_transport_test.c"
#undef main
#undef network_rx
#undef luat_zenoh_pico_io_progress
#undef luat_zenoh_pico_io_fail_at

static int rx_mode, rx_fault;
static unsigned rx_calls, rx_after_fault;
static size_t rx_total;
void luat_zenoh_pico_io_progress(int sending, size_t n) {
    test_tx_progress(sending, n);
    if (!sending && !failed) rx_total += n;
}
void luat_zenoh_pico_io_fail_at(const char *stage, int rc, size_t requested,
                              size_t transferred, uint64_t elapsed) {
    int had_failure = failed;
    test_tx_fail_at(stage, rc, requested, transferred, elapsed);
    if (!had_failure) diagnostic.total_rx = rx_total;
}
int network_rx(network_ctrl_t *c, uint8_t *p, uint32_t n, int flags, luat_ip_addr_t *ip,
               uint16_t *port, uint32_t *got) {
    (void)flags; (void)ip; (void)port; *got = 0;
    if (!rx_mode) return 0;
    ++rx_calls;
    if (rx_fault) { ++rx_after_fault; return -1; }
    if (rx_mode == 2 && rx_calls > 1) { rx_fault = 1; return -1; }
    if (rx_mode == 3) { *got = n + 1; return 0; }
    ssize_t z = recv(c->socket_id, p, n < 7 ? n : 7, MSG_DONTWAIT);
    if (z < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) return 0;
    if (z < 0) return -1;
    *got = (uint32_t)z; return 0;
}
#define RX_CHECK(x) do { if (!(x)) { fprintf(stderr, "RX_ASSERT line=%d: %s\n", __LINE__, #x); result = 1; goto cleanup; } } while (0)
static int rx_case(int scenario) {
    int result = 0;
    failed = 0; rx_fault = 0; rx_calls = rx_after_fault = 0; rx_total = 0;
    memset(&diagnostic, 0, sizeof(diagnostic));
    rx_mode = scenario == 2 ? 2 : scenario == 3 ? 3 : 1;
    _z_sys_net_socket_t s = {0}; _z_sys_net_endpoint_t ep = {0};
    RX_CHECK(_z_open_tcp(&s, ep, 100) == 0);
    RX_CHECK(fcntl(peer_fd, F_SETFL, O_NONBLOCK) == 0);
    size_t count = scenario == 0 ? 4096 : scenario == 1 ? 5 : scenario == 2 ? 14 : 0;
    if (count) RX_CHECK(send(peer_fd, payload, count, 0) == (ssize_t)count);
    uint8_t bytes[4096]; unsigned before = rx_calls;
    size_t got = _z_read_tcp(s, bytes, sizeof(bytes));
    RX_CHECK(rx_calls - before <= 16);
    if (scenario == 0) {
        /* 真正进展的短读应有界合并；不以循环次数代替整包字节核验。 */
        RX_CHECK(got > 7 && got <= sizeof(bytes));
        size_t done = got;
        while (done < sizeof(bytes)) {
            before = rx_calls; got = _z_read_tcp(s, bytes + done, sizeof(bytes) - done);
            RX_CHECK(got != SIZE_MAX && got > 0 && rx_calls - before <= 16);
            done += got;
        }
        RX_CHECK(!memcmp(bytes, payload, sizeof(bytes)) && rx_total == sizeof(bytes) && !failed);
    } else if (scenario == 1) {
        RX_CHECK(got == 5 && !failed && !memcmp(bytes, payload, 5) && rx_total == 5);
    } else if (scenario == 2 || scenario == 3) {
        RX_CHECK(got == (scenario == 2 ? 7u : SIZE_MAX) && failed && !strcmp(diagnostic.stage, "rx_error"));
        if (scenario == 2) RX_CHECK(!memcmp(bytes, payload, 7));
        RX_CHECK(diagnostic.transferred == (scenario == 2 ? 7u : 0u));
        RX_CHECK(diagnostic.total_rx == (scenario == 2 ? 7u : 0u));
        before = rx_calls; RX_CHECK(_z_read_tcp(s, bytes, 1) == SIZE_MAX);
        RX_CHECK(rx_calls == before && !rx_after_fault);
    } else {
        RX_CHECK(got == SIZE_MAX && !failed && rx_calls == 1);
    }
cleanup:
    _z_close_tcp(&s); if (peer_fd >= 0) close(peer_fd); peer_fd = -1; return result;
}
int main(void) {
    rx_mode = 0;
    if (tx_contract_main()) return 1;
    unsigned failures = 0;
    for (int i = 0; i < 5; ++i) {
        int rc = rx_case(i); failures += rc != 0;
        printf("RX_CONTRACT_%s case=%d read_calls=%u total_rx=%zu\n",
               rc ? "FAIL" : "PASS", i, rx_calls, rx_total);
    }
    printf("RX_CONTRACT_DONE checks=5 failures=%u scope=real_socket_API_model\n", failures);
    return failures ? 1 : 0;
}

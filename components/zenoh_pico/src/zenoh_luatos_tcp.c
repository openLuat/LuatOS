/* SPDX-License-Identifier: MIT */
#include "zenoh-pico/system/link/tcp.h"
#include "luat_zenoh_pico.h"
#include "luat_network_adapter.h"
#include "luat_malloc.h"
#include "luat_mcu.h"
#include <stdlib.h>
#include <string.h>

typedef struct { network_ctrl_t *net; uint32_t timeout; } tcp_context_t;

z_result_t _z_create_endpoint_tcp(_z_sys_net_endpoint_t *ep, const char *host, const char *port) {
    memset(ep, 0, sizeof(*ep));
    if (!host || !port || !*host || strlen(host) >= sizeof(ep->host) || strpbrk(host, ":[]")) return Z_EINVAL;
    char *end; unsigned long number = strtoul(port, &end, 10);
    if (!*port || *end || number == 0 || number > 65535) return Z_EINVAL;
    memcpy(ep->host, host, strlen(host) + 1); ep->port = (uint16_t)number; return 0;
}
void _z_free_endpoint_tcp(_z_sys_net_endpoint_t *ep) { memset(ep, 0, sizeof(*ep)); }
z_result_t _z_listen_tcp(_z_sys_net_socket_t *s, const _z_sys_net_endpoint_t ep) {
    (void)ep; s->context = NULL; return Z_EINVAL;
}
void _z_close_tcp(_z_sys_net_socket_t *s) {
    tcp_context_t *c = s->context;
    if (!c) return;
    s->context = NULL;
    if (c->net) {
        network_close(c->net, 100);
        network_force_close_socket(c->net);
        network_release_ctrl(c->net);
    }
    luat_heap_free(c);
}
void _z_socket_close(_z_sys_net_socket_t *s) { _z_close_tcp(s); }
z_result_t _z_socket_set_blocking(const _z_sys_net_socket_t *s, bool blocking) {
    /* adapter保持非阻塞，read_exact在本任务内实施有限总体超时。 */
    return s && s->context && !blocking ? 0 : Z_EINVAL;
}
z_result_t _z_open_tcp(_z_sys_net_socket_t *s, const _z_sys_net_endpoint_t ep, uint32_t timeout) {
    s->context = NULL;
    if (luat_zenoh_pico_rng_failed()) return _Z_ERR_SYSTEM_GENERIC;
    tcp_context_t *c = luat_heap_malloc(sizeof(*c));
    if (!c) return _Z_ERR_SYSTEM_OUT_OF_MEMORY;
    memset(c, 0, sizeof(*c)); c->timeout = timeout ? timeout : Z_CONFIG_SOCKET_TIMEOUT;
    c->net = network_alloc_ctrl((uint8_t)luat_zenoh_pico_adapter());
    s->context = c;
    if (!c->net) { _z_close_tcp(s); return _Z_ERR_SYSTEM_OUT_OF_MEMORY; }
    network_init_ctrl(c->net, luat_rtos_get_current_handle(), NULL, NULL);
    network_set_base_mode(c->net, 1, c->timeout, 0, 0, 0, 0);
    int rc = network_connect(c->net, ep.host, (uint32_t)strlen(ep.host), NULL, ep.port, Z_TRANSPORT_CONNECT_TIMEOUT);
    if (rc != 0) { _z_close_tcp(s); return _Z_ERR_TRANSPORT_OPEN_FAILED; }
    return 0;
}
size_t _z_read_tcp(const _z_sys_net_socket_t s, uint8_t *p, size_t n) {
    tcp_context_t *c = s.context;
    if (!c || !c->net || n > UINT32_MAX) { luat_zenoh_pico_io_fail(); return SIZE_MAX; }
    uint32_t got = 0;
    int rc = network_rx(c->net, p, (uint32_t)n, 0, NULL, NULL, &got);
    if (rc < 0) luat_zenoh_pico_io_fail();
    /* network_wait_rx(0)会永久等待；此处始终使用非阻塞实际读取。 */
    return rc == 0 && got ? got : SIZE_MAX;
}
size_t _z_read_exact_tcp(const _z_sys_net_socket_t s, uint8_t *p, size_t n) {
    tcp_context_t *c = s.context;
    if (!c) return SIZE_MAX;
    uint64_t start = luat_mcu_tick64_ms(); size_t done = 0;
    while (done < n && luat_mcu_tick64_ms() - start < c->timeout) {
        size_t got = _z_read_tcp(s, p + done, n - done);
        if (got != SIZE_MAX) done += got;
        else if (luat_zenoh_pico_io_failed()) return SIZE_MAX;
        else luat_rtos_task_sleep(1);
    }
    if (done == n) return done;
    luat_zenoh_pico_io_fail(); return SIZE_MAX;
}
size_t _z_send_tcp(const _z_sys_net_socket_t s, const uint8_t *p, size_t n) {
    if (luat_zenoh_pico_io_failed()) return SIZE_MAX;
    tcp_context_t *c = s.context;
    if (!c || n > UINT32_MAX) return SIZE_MAX;
    uint64_t start = luat_mcu_tick64_ms(); size_t done = 0;
    while (done < n && luat_mcu_tick64_ms() - start < c->timeout) {
        uint32_t sent = 0;
        uint64_t elapsed_ms = luat_mcu_tick64_ms() - start;
        if (elapsed_ms >= c->timeout) break;
        uint32_t remaining = c->timeout - (uint32_t)elapsed_ms;
        int rc = network_tx(c->net, p + done, (uint32_t)(n - done), 0, NULL, 0, &sent, remaining);
        if (rc != 0 || sent > n - done) break;
        done += sent;
        if (!sent) luat_rtos_task_sleep(1);
    }
    if (done == n) return done;
    /* 部分帧已发送时不可在新消息上继续，所属任务必须关闭连接。 */
    luat_zenoh_pico_io_fail(); return SIZE_MAX;
}

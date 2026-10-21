/* SPDX-License-Identifier: MIT */
/* 独立主机桥：真实pthread/socket，执行模块generic平台适配器，不模拟对端回包。 */
#include "luat_base.h"
#include "lua.h"
#include "luat_rtos.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include <pthread.h>
#include <stdatomic.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#ifdef ZENOH_GENERIC
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#endif

typedef union { max_align_t alignment; size_t size; } allocation_t;
static atomic_long allocations;
static _Thread_local long fail_after = -1;
long host_allocations(void) { return atomic_load(&allocations); }
void host_fail_after(long n) { fail_after = n; }
void *luat_heap_malloc(size_t n) {
    if (fail_after == 0) { fail_after = -1; return NULL; }
    if (fail_after > 0) --fail_after;
    if (n > SIZE_MAX - sizeof(allocation_t)) return NULL;
    allocation_t *a = malloc(sizeof(*a) + n);
    if (!a) return NULL;
    a->size = n; atomic_fetch_add(&allocations, 1); return a + 1;
}
void luat_heap_free(void *p) {
    if (p) { free((allocation_t *)p - 1); atomic_fetch_sub(&allocations, 1); }
}
void *luat_heap_realloc(void *p, size_t n) {
    if (!p) return luat_heap_malloc(n);
    if (!n) { luat_heap_free(p); return NULL; }
    allocation_t *old = (allocation_t *)p - 1;
    void *next = luat_heap_malloc(n);
    if (next) { memcpy(next, p, old->size < n ? old->size : n); luat_heap_free(p); }
    return next;
}
int luat_crypto_trng(char *p, size_t n) { arc4random_buf(p, n); return 0; }
void luat_rtos_task_sleep(uint32_t ms) { struct timespec t = {ms / 1000, (long)(ms % 1000) * 1000000}; nanosleep(&t, NULL); }
uint64_t luat_mcu_tick64_ms(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint64_t)t.tv_sec * 1000 + t.tv_nsec / 1000000; }

typedef struct {
    pthread_mutex_t lock;
    pthread_cond_t ready;
    uint32_t size, capacity, count, head;
    unsigned char bytes[];
} queue_t;
int luat_rtos_queue_create(luat_rtos_queue_t *out, uint32_t count, uint32_t size) {
    queue_t *q = luat_heap_malloc(sizeof(*q) + (size_t)count * size);
    if (!q) return -1;
    memset(q, 0, sizeof(*q)); q->capacity = count; q->size = size;
    pthread_mutex_init(&q->lock, NULL); pthread_cond_init(&q->ready, NULL); *out = q; return 0;
}
int luat_rtos_queue_delete(luat_rtos_queue_t handle) {
    queue_t *q = handle; pthread_mutex_destroy(&q->lock); pthread_cond_destroy(&q->ready); luat_heap_free(q); return 0;
}
int luat_rtos_queue_send(luat_rtos_queue_t handle, void *item, uint32_t size, uint32_t timeout) {
    (void)timeout; queue_t *q = handle;
    pthread_mutex_lock(&q->lock);
    if (size != q->size || q->count == q->capacity) { pthread_mutex_unlock(&q->lock); return -1; }
    memcpy(q->bytes + ((q->head + q->count) % q->capacity) * q->size, item, size); q->count++;
    pthread_cond_signal(&q->ready); pthread_mutex_unlock(&q->lock); return 0;
}
int luat_rtos_queue_recv(luat_rtos_queue_t handle, void *item, uint32_t size, uint32_t timeout) {
    (void)timeout; queue_t *q = handle;
    pthread_mutex_lock(&q->lock);
    if (!q->count || size != q->size) { pthread_mutex_unlock(&q->lock); return -1; }
    memcpy(item, q->bytes + q->head * q->size, size); q->head = (q->head + 1) % q->capacity; q->count--;
    pthread_mutex_unlock(&q->lock); return 0;
}
typedef struct { luat_rtos_task_entry entry; void *context; } entry_t;
static void *enter(void *context) { entry_t e = *(entry_t *)context; free(context); e.entry(e.context); return NULL; }
int luat_rtos_task_create(luat_rtos_task_handle *out, uint32_t stack, uint8_t priority, const char *name,
                          luat_rtos_task_entry entry, void *context, uint16_t mailbox) {
    (void)stack; (void)priority; (void)name; (void)mailbox;
    pthread_t *thread = malloc(sizeof(*thread)); entry_t *arg = malloc(sizeof(*arg));
    if (!thread || !arg) { free(thread); free(arg); return -1; }
    arg->entry = entry; arg->context = context;
    int rc = pthread_create(thread, NULL, enter, arg);
    if (rc) { free(thread); free(arg); return rc; }
    pthread_detach(*thread); *out = thread; return 0;
}
static pthread_mutex_t bus_lock = PTHREAD_MUTEX_INITIALIZER;
static rtos_msg_t bus[16];
static unsigned bus_head, bus_count;
uint32_t luat_msgbus_put(rtos_msg_t *message, size_t timeout) {
    (void)timeout; pthread_mutex_lock(&bus_lock);
    if (bus_count == 16) { pthread_mutex_unlock(&bus_lock); return 1; }
    bus[(bus_head + bus_count++) % 16] = *message; pthread_mutex_unlock(&bus_lock); return 0;
}
int host_message(rtos_msg_t *out) {
    pthread_mutex_lock(&bus_lock);
    if (!bus_count) { pthread_mutex_unlock(&bus_lock); return 0; }
    *out = bus[bus_head]; bus_head = (bus_head + 1) % 16; bus_count--;
    pthread_mutex_unlock(&bus_lock); return 1;
}

#ifdef ZENOH_GENERIC
/* 主机堆实现先调用libc，之后再引入c_common的malloc映射，避免递归。 */
#include "luat_network_adapter.h"
static pthread_mutex_t network_lock = PTHREAD_MUTEX_INITIALIZER;
static int current_socket = -1;
static atomic_uint short_reads, short_writes;
static atomic_int write_budget = -1, write_fault, write_gate;
static atomic_uint writes_after_fault, failure_bytes;
void host_write_failure_after(int n) {
    atomic_store(&writes_after_fault, 0); atomic_store(&failure_bytes, 0);
    atomic_store(&write_fault, 0); atomic_store(&write_budget, n);
    atomic_store(&write_gate, n >= 0);
}
void host_write_release(void) { atomic_store(&write_gate, 0); }
unsigned host_writes_after_fault(void) { return atomic_load(&writes_after_fault); }
unsigned host_failure_bytes(void) { return atomic_load(&failure_bytes); }
luat_rtos_task_handle luat_rtos_get_current_handle(void) { return (void *)(uintptr_t)pthread_self(); }
network_ctrl_t *network_alloc_ctrl(uint8_t adapter) {
    if (adapter != 0) return NULL;
    network_ctrl_t *c = luat_heap_malloc(sizeof(*c));
    if (c) { memset(c, 0, sizeof(*c)); c->socket_id = -1; }
    return c;
}
void network_init_ctrl(network_ctrl_t *c, HANDLE task, CBFuncEx_t callback, void *parameter) {
    c->task_handle = task; c->user_callback = callback; c->user_data = parameter;
}
void network_set_base_mode(network_ctrl_t *c, uint8_t tcp, uint32_t timeout,
                           uint8_t keep, uint32_t idle, uint8_t interval, uint8_t count) {
    (void)keep; (void)idle; (void)interval; (void)count; c->is_tcp = tcp; c->tcp_timeout_ms = timeout;
}
int network_connect(network_ctrl_t *c, const char *host, uint32_t length, luat_ip_addr_t *ip,
                     uint16_t port, uint32_t timeout) {
    (void)ip;
    /* 此桥只接已批准的本机隔离router，不做DNS或外网访问。 */
    if (length != 9 || memcmp(host, "127.0.0.1", 9) || port != 17447) return -1;
    c->socket_id = socket(AF_INET, SOCK_STREAM, 0);
    if (c->socket_id < 0) return -1;
    if (fcntl(c->socket_id, F_SETFL, O_NONBLOCK) < 0) return -1;
#ifdef SO_NOSIGPIPE
    int yes = 1; setsockopt(c->socket_id, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
#endif
    struct sockaddr_in address = {0}; address.sin_family = AF_INET;
    address.sin_port = htons(port); inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);
    int rc = connect(c->socket_id, (struct sockaddr *)&address, sizeof(address));
    if (rc < 0 && errno != EINPROGRESS) return -1;
    struct pollfd fd = {c->socket_id, POLLOUT, 0};
    if (poll(&fd, 1, (int)timeout) <= 0) return -1;
    int error = 0; socklen_t size = sizeof(error);
    if (getsockopt(c->socket_id, SOL_SOCKET, SO_ERROR, &error, &size) < 0 || error) return -1;
    c->state = NW_STATE_ONLINE;
    pthread_mutex_lock(&network_lock); current_socket = c->socket_id; pthread_mutex_unlock(&network_lock);
    return 0;
}
int network_close(network_ctrl_t *c, uint32_t timeout) {
    (void)timeout; pthread_mutex_lock(&network_lock);
    if (c->socket_id >= 0) {
        if (current_socket == c->socket_id) current_socket = -1;
        close(c->socket_id); c->socket_id = -1;
    }
    c->state = NW_STATE_OFF_LINE; pthread_mutex_unlock(&network_lock); return 0;
}
void network_force_close_socket(network_ctrl_t *c) { network_close(c, 0); }
void network_release_ctrl(network_ctrl_t *c) { network_close(c, 0); luat_heap_free(c); }
int network_rx(network_ctrl_t *c, uint8_t *p, uint32_t n, int flags, luat_ip_addr_t *ip, uint16_t *port, uint32_t *got) {
    (void)flags; (void)ip; (void)port; *got = 0;
    if (!n) return 0;
    ssize_t result = recv(c->socket_id, p, n > 7 ? 7 : n, 0);
    if (result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) return 0;
    if (result <= 0) return -1;
    *got = (uint32_t)result;
    if (*got < n) atomic_fetch_add(&short_reads, 1);
    return 0;
}
int network_tx(network_ctrl_t *c, const uint8_t *p, uint32_t n, int flags, luat_ip_addr_t *ip,
                uint16_t port, uint32_t *sent, uint32_t timeout) {
    (void)flags; (void)ip; (void)port; (void)timeout; *sent = 0;
    /* 仅故障测试：让VM在第一笔写前确定入队两条命令，最长等待100ms。 */
    for (int i = 0; atomic_load(&write_gate) && i < 100; ++i) luat_rtos_task_sleep(1);
    if (atomic_load(&write_fault)) { atomic_fetch_add(&writes_after_fault, 1); return -1; }
    int budget = atomic_load(&write_budget);
    if (budget == 0) { atomic_store(&write_fault, 1); return -1; }
    uint32_t limit = n > 17 ? 17 : n;
    if (budget > 0 && limit > (uint32_t)budget) limit = (uint32_t)budget;
#ifdef MSG_NOSIGNAL
    flags = MSG_NOSIGNAL;
#else
    flags = 0;
#endif
    ssize_t result = send(c->socket_id, p, limit, flags);
    if (result < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) return 0;
    if (result < 0) return -1;
    *sent = (uint32_t)result;
    if (budget > 0) {
        atomic_fetch_sub(&write_budget, (int)*sent);
        atomic_fetch_add(&failure_bytes, *sent);
    }
    if (*sent < n) atomic_fetch_add(&short_writes, 1);
    return 0;
}
int host_disconnect(void) {
    pthread_mutex_lock(&network_lock);
    int rc = current_socket >= 0 ? shutdown(current_socket, SHUT_RDWR) : -1;
    pthread_mutex_unlock(&network_lock); return rc;
}
unsigned host_short_reads(void) { return atomic_load(&short_reads); }
unsigned host_short_writes(void) { return atomic_load(&short_writes); }
#endif

/* 测试屏障暂停真实线程，终态仍由worker/SDK生成，不注入回调。 */
#include "luat_zenoh_pico.h"
int host_disconnect(void);
static pthread_mutex_t race_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t race_ready = PTHREAD_COND_INITIALIZER;
static int race_point, race_arrived, race_released, race_closed, race_thread_live;
static uint32_t race_generation;
static pthread_t race_thread;
void luat_zp_test_barrier(int point, uint32_t generation) {
    pthread_mutex_lock(&race_lock);
    if (race_point == point) {
        race_arrived = 1; race_generation = generation;
        pthread_cond_broadcast(&race_ready);
        while (!race_released) pthread_cond_wait(&race_ready, &race_lock);
        race_point = 0;
    }
    pthread_mutex_unlock(&race_lock);
}
static void *race_disconnect(void *unused) {
    (void)unused;
    pthread_mutex_lock(&race_lock);
    while (!race_arrived) pthread_cond_wait(&race_ready, &race_lock);
    uint32_t generation = race_generation;
    pthread_mutex_unlock(&race_lock);
    int disconnected = host_disconnect() == 0;
    uint64_t deadline = luat_mcu_tick64_ms() + 5000;
    while (luat_zenoh_pico_state(generation) != LUAT_ZP_CLOSED && luat_mcu_tick64_ms() < deadline)
        luat_rtos_task_sleep(1);
    pthread_mutex_lock(&race_lock);
    race_closed = disconnected && luat_zenoh_pico_state(generation) == LUAT_ZP_CLOSED;
    race_released = 1; pthread_cond_broadcast(&race_ready);
    pthread_mutex_unlock(&race_lock);
    return NULL;
}
int host_race_arm(int point) {
    if (point != 1 && point != 2) return -1;
    pthread_mutex_lock(&race_lock);
    if (race_point || race_thread_live) { pthread_mutex_unlock(&race_lock); return -1; }
    race_point = point; race_arrived = race_released = race_closed = 0;
    pthread_mutex_unlock(&race_lock);
    if (point == 2) {
        if (pthread_create(&race_thread, NULL, race_disconnect, NULL)) return -1;
        race_thread_live = 1;
    }
    return 0;
}
int host_race_arrived(void) {
    pthread_mutex_lock(&race_lock); int value = race_arrived; pthread_mutex_unlock(&race_lock); return value;
}
void host_race_release(void) {
    pthread_mutex_lock(&race_lock); race_released = 1; pthread_cond_broadcast(&race_ready); pthread_mutex_unlock(&race_lock);
}
int host_race_closed(void) {
    if (race_thread_live) { pthread_join(race_thread, NULL); race_thread_live = 0; }
    pthread_mutex_lock(&race_lock); int value = race_closed; pthread_mutex_unlock(&race_lock); return value;
}

// AI-MANAGED: true
// 编译实际驱动；pthread仅替代主机不存在的RTOS接口。
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef void lua_State;
typedef void* luat_rtos_mutex_t;
typedef struct { int id; } luat_uart_t;
typedef struct { uint16_t cmd, len; uint8_t data[]; } luat_airlink_cmd_t;
typedef struct { size_t len; luat_airlink_cmd_t* cmd; } airlink_queue_item_t;
typedef struct { int (*handler)(lua_State*, void*); void* ptr; int arg1; size_t arg2; } rtos_msg_t;
#define LUAT_AIRLINK_QUEUE_CMD 1

static _Thread_local int held_by_thread;
static atomic_int allocation_failure, mutex_failure, allocations, mutexes, errors, notifications;
static atomic_int init_barrier_enabled;
static pthread_mutex_t init_guard = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t init_cond = PTHREAD_COND_INITIALIZER;
static int init_arrivals;

static void test_log(const char* format, ...) __attribute__((format(printf, 1, 2)));
static void test_log(const char* format, ...) {
    assert(held_by_thread == 0);
    char message[256];
    va_list args;
    va_start(args, format);
    vsnprintf(message, sizeof(message), format, args);
    va_end(args);
    atomic_fetch_add(&errors, 1);
}
#define LLOGE(...) test_log(__VA_ARGS__)
static void* test_malloc(size_t n) {
    if (atomic_exchange(&allocation_failure, 0)) return NULL;
    void* p = malloc(n);
    if (p) atomic_fetch_add(&allocations, 1);
    if (p && atomic_load(&init_barrier_enabled)) {
        assert(pthread_mutex_lock(&init_guard) == 0);
        init_arrivals++;
        if (init_arrivals == 2) assert(pthread_cond_broadcast(&init_cond) == 0);
        while (init_arrivals < 2) assert(pthread_cond_wait(&init_cond, &init_guard) == 0);
        assert(pthread_mutex_unlock(&init_guard) == 0);
    }
    return p;
}
static void test_free(void* p) {
    if (p) { atomic_fetch_sub(&allocations, 1); free(p); }
}
#define luat_heap_malloc test_malloc
#define luat_heap_free test_free

#ifdef TEST_FIXED
static int luat_rtos_mutex_create(luat_rtos_mutex_t* out) {
    if (atomic_exchange(&mutex_failure, 0)) return -1;
    pthread_mutex_t* m = malloc(sizeof(*m));
    assert(m != NULL && pthread_mutex_init(m, NULL) == 0);
    *out = m;
    atomic_fetch_add(&mutexes, 1);
    return 0;
}
static uint64_t now_ms(void) {
    struct timespec t;
    assert(clock_gettime(CLOCK_MONOTONIC, &t) == 0);
    return (uint64_t)t.tv_sec * 1000 + (uint64_t)t.tv_nsec / 1000000;
}
static int luat_rtos_mutex_lock(luat_rtos_mutex_t h, uint32_t ms) {
    uint64_t end = now_ms() + ms;
    for (;;) {
        int r = pthread_mutex_trylock(h);
        if (r == 0) { held_by_thread++; return 0; }
        assert(r == EBUSY);
        if (now_ms() >= end) return -1;
        struct timespec pause = {0, 1000000};
        nanosleep(&pause, NULL);
    }
}
static int luat_rtos_mutex_unlock(luat_rtos_mutex_t h) {
    assert(held_by_thread > 0);
    held_by_thread--;
    return pthread_mutex_unlock(h);
}
static int luat_rtos_mutex_delete(luat_rtos_mutex_t h) {
    assert(pthread_mutex_destroy(h) == 0);
    atomic_fetch_sub(&mutexes, 1);
    free(h);
    return 0;
}
#endif

int l_uart_handler(lua_State* L, void* p) { (void)L; (void)p; return 0; }
static int luat_msgbus_put(rtos_msg_t* msg, int wait) {
    (void)msg; (void)wait;
    assert(held_by_thread == 0);
    atomic_fetch_add(&notifications, 1);
    return 0;
}
static uint64_t luat_airlink_get_next_cmd_id(void) {
    static uint64_t seq;
    return __sync_add_and_fetch(&seq, 1);
}
static luat_airlink_cmd_t* luat_airlink_cmd_new(int id, size_t n) {
    luat_airlink_cmd_t* p = test_malloc(sizeof(*p) + n);
    if (p) { p->cmd = (uint16_t)id; p->len = (uint16_t)n; }
    return p;
}
static int luat_airlink_queue_send(int kind, airlink_queue_item_t* item) {
    (void)kind;
    test_free(item->cmd);
    return 0;
}

int luat_airlink_drv_uart_read(int, void*, size_t);
int luat_airlink_drv_uart_rx_clear(int);
typedef struct { int op, port, result; size_t length; uint8_t data[4096]; } reader_t;
static void* reader(void* arg) {
    reader_t* r = arg;
    if (r->op == 1) r->result = luat_airlink_drv_uart_rx_clear(r->port);
    else r->result = luat_airlink_drv_uart_read(r->port, r->op == 2 ? NULL : r->data, r->length);
    return NULL;
}
static atomic_int inject;
static const void* injected_source;
static reader_t interrupted_reader;
static void* copy_hook(void* dest, const void* src, size_t n) {
    if (src == injected_source && atomic_exchange(&inject, 0)) {
        pthread_t t;
        assert(pthread_create(&t, NULL, reader, &interrupted_reader) == 0);
        assert(pthread_join(t, NULL) == 0);
    }
    return memcpy(dest, src, n);
}
#define memcpy copy_hook

/* SOURCE_UNDER_TEST */

#undef memcpy

static void reset_buffers(void) {
    for (int i = 0; i < 10; i++) {
        if (uart_rx_buffs[i]) {
#ifdef TEST_FIXED
            assert(luat_rtos_mutex_delete(uart_rx_buffs[i]->mutex) == 0);
#endif
            test_free(uart_rx_buffs[i]);
            uart_rx_buffs[i] = NULL;
        }
    }
    atomic_store(&inject, 0);
    injected_source = NULL;
    assert(atomic_load(&allocations) == 0);
    assert(atomic_load(&mutexes) == 0);
}

static void test_interleaving(size_t old_len, int op) {
    reset_buffers();
    uint8_t old[1040], incoming[130], out[4096];
    for (size_t i = 0; i < sizeof(old); i++) old[i] = (uint8_t)(17 + i % 197);
    memset(incoming, 0xe5, sizeof(incoming));
    assert(luat_airlink_drv_uart_data_cb(12, old, old_len) == 0);
    interrupted_reader = (reader_t){.op = op, .port = 12, .length = old_len};
    injected_source = incoming;
    atomic_store(&inject, 1);
    assert(luat_airlink_drv_uart_data_cb(12, incoming, sizeof(incoming)) == 0);
    assert(atomic_load(&inject) == 0);
#ifdef TEST_FIXED
    assert(interrupted_reader.result == -103);
    assert(luat_airlink_drv_uart_read(12, out, sizeof(out)) == (int)(old_len + sizeof(incoming)));
    assert(memcmp(out, old, old_len) == 0);
    assert(memcmp(out + old_len, incoming, sizeof(incoming)) == 0);
    printf("FIXED: old=%zu op=%d timeout_preserves_old_and_incoming\n", old_len, op);
#else
    assert(op == 0 && interrupted_reader.result == (int)old_len);
    assert(memcmp(interrupted_reader.data, old, old_len) == 0);
    assert(luat_airlink_drv_uart_read(12, out, sizeof(out)) == 130);
    assert(memcmp(out, old, 130) == 0 && memcmp(out, incoming, 130) != 0);
    printf("DEFECT_REPRODUCED: old=%zu stale_prefix=1 incoming_missing=1\n", old_len);
#endif
    assert(luat_airlink_drv_uart_read(12, NULL, 0) == 0);
}

static void test_serial_and_overflow(void) {
    reset_buffers();
    uint8_t a[4096], b[4097], out[4096];
    for (size_t i = 0; i < sizeof(a); i++) a[i] = (uint8_t)(i % 197);
    memset(b, 0x22, sizeof(b));
    assert(luat_airlink_drv_uart_read(11, out, 128) == 0);
    assert(luat_airlink_drv_uart_rx_clear(11) == 0);
    assert(luat_airlink_drv_uart_data_cb(11, a, 260) == 0);
    assert(luat_airlink_drv_uart_data_cb(12, b, 130) == 0);
    assert(luat_airlink_drv_uart_read(11, out, 128) == 128);
    assert(memcmp(out, a, 128) == 0);
    assert(luat_airlink_drv_uart_read(11, out, 1024) == 132);
    assert(memcmp(out, a + 128, 132) == 0);
    assert(luat_airlink_drv_uart_read(12, NULL, 0) == 130);
    assert(luat_airlink_drv_uart_rx_clear(12) == 0);
    assert(luat_airlink_drv_uart_data_cb(12, a, 4096) == 0);
    assert(luat_airlink_drv_uart_data_cb(12, b, 130) == 0);
    assert(luat_airlink_drv_uart_read(12, out, sizeof(out)) == 4096);
    assert(memcmp(out, a + 130, 3966) == 0 && memcmp(out + 3966, b, 130) == 0);
    assert(luat_airlink_drv_uart_data_cb(12, b, 4097) == -102);
    assert(luat_airlink_drv_uart_read(12, NULL, 0) == 0);
    assert(luat_airlink_drv_uart_data_cb(9, a, 13) == 0);
    assert(luat_airlink_drv_uart_read(20, out, 13) == 0);
#ifdef TEST_FIXED
    assert(luat_airlink_drv_uart_data_cb(12, b, SIZE_MAX) == -102);
#endif
    puts("serial_short_read_isolation_overflow_clear: PASS");
}

#ifdef TEST_FIXED
static void test_other_port_progress(void) {
    reset_buffers();
    uint8_t a[260], b[130];
    memset(a, 0x11, sizeof(a)); memset(b, 0x22, sizeof(b));
    assert(luat_airlink_drv_uart_data_cb(11, a, sizeof(a)) == 0);
    assert(luat_airlink_drv_uart_data_cb(12, b, sizeof(b)) == 0);
    interrupted_reader = (reader_t){.port = 11, .length = sizeof(a)};
    injected_source = b;
    atomic_store(&inject, 1);
    assert(luat_airlink_drv_uart_data_cb(12, b, sizeof(b)) == 0);
    assert(interrupted_reader.result == 260 && memcmp(interrupted_reader.data, a, sizeof(a)) == 0);
    assert(luat_airlink_drv_uart_read(12, NULL, 0) == 260);
    puts("other_port_progress: PASS");
}
static void test_failures(void) {
    reset_buffers();
    uint8_t a[130]; memset(a, 0x33, sizeof(a));
    atomic_store(&allocation_failure, 1);
    assert(luat_airlink_drv_uart_data_cb(12, a, sizeof(a)) == -101);
    assert(uart_rx_buffs[2] == NULL && atomic_load(&allocations) == 0);
    atomic_store(&mutex_failure, 1);
    assert(luat_airlink_drv_uart_data_cb(12, a, sizeof(a)) == -101);
    assert(uart_rx_buffs[2] == NULL && atomic_load(&allocations) == 0);
    assert(luat_airlink_drv_uart_data_cb(12, a, sizeof(a)) == 0);
    assert(luat_rtos_mutex_lock(uart_rx_buffs[2]->mutex, 20) == 0);
    for (int op = 0; op < 3; op++) {
        reader_t r = {.op = op, .port = 12, .length = sizeof(a)};
        pthread_t t;
        assert(pthread_create(&t, NULL, reader, &r) == 0 && pthread_join(t, NULL) == 0);
        assert(r.result == -103 && uart_rx_buffs[2]->remain == sizeof(a));
    }
    assert(luat_rtos_mutex_unlock(uart_rx_buffs[2]->mutex) == 0);
    assert(luat_airlink_drv_uart_read(12, NULL, 0) == 130);
    puts("allocation_mutex_failure_busy_preserve: PASS");
}
typedef struct { uint8_t value; int result; } producer_t;
static void* producer(void* p) {
    producer_t* a = p;
    uint8_t bytes[13]; memset(bytes, a->value, sizeof(bytes));
    a->result = luat_airlink_drv_uart_data_cb(12, bytes, sizeof(bytes));
    return NULL;
}
static void test_incoming_lock_timeout(void) {
    reset_buffers();
    uint8_t original[130], out[130]; memset(original, 0x33, sizeof(original));
    assert(luat_airlink_drv_uart_data_cb(12, original, sizeof(original)) == 0);
    int before = atomic_load(&notifications);
    assert(luat_rtos_mutex_lock(uart_rx_buffs[2]->mutex, 20) == 0);
    producer_t incoming = {.value = 0x44};
    pthread_t t;
    assert(pthread_create(&t, NULL, producer, &incoming) == 0);
    assert(pthread_join(t, NULL) == 0);
    assert(incoming.result == -103 && uart_rx_buffs[2]->remain == sizeof(original));
    assert(atomic_load(&notifications) == before);
    assert(luat_rtos_mutex_unlock(uart_rx_buffs[2]->mutex) == 0);
    assert(luat_airlink_drv_uart_read(12, out, sizeof(out)) == 130);
    assert(memcmp(original, out, sizeof(out)) == 0);
    puts("incoming_lock_timeout_rejects_without_cache_change_or_notification: PASS");
}
static void test_concurrent_initialization(void) {
    reset_buffers();
    assert(pthread_mutex_lock(&init_guard) == 0);
    init_arrivals = 0;
    atomic_store(&init_barrier_enabled, 1);
    assert(pthread_mutex_unlock(&init_guard) == 0);
    producer_t a = {.value = 0x11}, b = {.value = 0x22};
    pthread_t t1, t2;
    assert(pthread_create(&t1, NULL, producer, &a) == 0);
    assert(pthread_create(&t2, NULL, producer, &b) == 0);
    assert(pthread_join(t1, NULL) == 0 && pthread_join(t2, NULL) == 0);
    atomic_store(&init_barrier_enabled, 0);
    assert(a.result == 0 && b.result == 0);
    assert(atomic_load(&allocations) == 1 && atomic_load(&mutexes) == 1);
    uint8_t out[26];
    assert(luat_airlink_drv_uart_read(12, out, sizeof(out)) == 26);
    assert(out[0] != out[13]);
    for (size_t i = 0; i < 13; i++) assert(out[i] == out[0] && out[i + 13] == out[13]);
    puts("concurrent_initialization_single_published_buffer: PASS");
}
#endif

int main(void) {
    test_interleaving(1040, 0); test_interleaving(260, 0);
    test_serial_and_overflow();
#ifdef TEST_FIXED
    test_interleaving(260, 1); test_interleaving(260, 2);
    test_other_port_progress(); test_failures(); test_incoming_lock_timeout(); test_concurrent_initialization();
#endif
    reset_buffers();
    printf("driver_suite_complete notifications=%d errors=%d\n", atomic_load(&notifications), atomic_load(&errors));
    return 0;
}

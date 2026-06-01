#include <string.h>
#include <pthread.h>

#include "luat_base.h"
#include "luat_mcu.h"
#include "luat_mem.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_uart31_console.h"

#define UART31_ID 31
#define UART31_HISTORY_MAX 64

typedef struct uart31_history_item {
    int is_tx;
    uint64_t ts_ms;
    uint8_t* data;
    size_t len;
} uart31_history_item_t;

typedef struct uart31_ctx {
    pthread_mutex_t lock;
    int init_done;
    uint8_t* rx_buff;
    size_t rx_len;
    uart31_history_item_t history[UART31_HISTORY_MAX];
    size_t history_start;
    size_t history_count;
} uart31_ctx_t;

static uart31_ctx_t g_uart31 = {0};

extern void luat_uart_recv_callback(int uart_id, int len);
extern const luat_uart_drv_opts_t* uart_drvs[];

static void uart31_ensure_init(void) {
    if (g_uart31.init_done) {
        return;
    }
    pthread_mutex_init(&g_uart31.lock, NULL);
    g_uart31.init_done = 1;
}

static void uart31_history_push_locked(int is_tx, const uint8_t* data, size_t len) {
    size_t idx;
    uint8_t* copy = NULL;
    if (!data || !len) {
        return;
    }
    copy = luat_heap_malloc(len);
    if (!copy) {
        return;
    }
    memcpy(copy, data, len);
    if (g_uart31.history_count < UART31_HISTORY_MAX) {
        idx = (g_uart31.history_start + g_uart31.history_count) % UART31_HISTORY_MAX;
        g_uart31.history_count++;
    }
    else {
        idx = g_uart31.history_start;
        g_uart31.history_start = (g_uart31.history_start + 1) % UART31_HISTORY_MAX;
        if (g_uart31.history[idx].data) {
            luat_heap_free(g_uart31.history[idx].data);
        }
    }
    g_uart31.history[idx].is_tx = is_tx;
    g_uart31.history[idx].ts_ms = luat_mcu_tick64_ms();
    g_uart31.history[idx].data = copy;
    g_uart31.history[idx].len = len;
}

static int uart_setup_console31(void* userdata, luat_uart_t* uart) {
    (void)userdata;
    (void)uart;
    uart31_ensure_init();
    return 0;
}

static int uart_write_console31(void* userdata, int uart_id, void* data, size_t length) {
    (void)userdata;
    if (uart_id != UART31_ID || !data || length == 0) {
        return 0;
    }
    uart31_ensure_init();
    pthread_mutex_lock(&g_uart31.lock);
    uart31_history_push_locked(1, (const uint8_t*)data, length);
    pthread_mutex_unlock(&g_uart31.lock);
    return (int)length;
}

static int uart_read_console31(void* userdata, int uart_id, void* buffer, size_t length) {
    size_t n;
    (void)userdata;
    if (uart_id != UART31_ID || !buffer || length == 0) {
        return 0;
    }
    uart31_ensure_init();
    pthread_mutex_lock(&g_uart31.lock);
    n = (g_uart31.rx_len < length) ? g_uart31.rx_len : length;
    if (n > 0) {
        memcpy(buffer, g_uart31.rx_buff, n);
        g_uart31.rx_len -= n;
        if (g_uart31.rx_len > 0) {
            memmove(g_uart31.rx_buff, g_uart31.rx_buff + n, g_uart31.rx_len);
            g_uart31.rx_buff = luat_heap_realloc(g_uart31.rx_buff, g_uart31.rx_len);
        }
        else {
            luat_heap_free(g_uart31.rx_buff);
            g_uart31.rx_buff = NULL;
        }
    }
    pthread_mutex_unlock(&g_uart31.lock);
    return (int)n;
}

static int uart_close_console31(void* userdata, int uart_id) {
    (void)userdata;
    (void)uart_id;
    return 0;
}

int luat_uart31_console_inject_rx(const uint8_t* data, size_t len) {
    uint8_t* tmp;
    if (!data || !len) {
        return 0;
    }
    uart31_ensure_init();
    pthread_mutex_lock(&g_uart31.lock);
    tmp = luat_heap_realloc(g_uart31.rx_buff, g_uart31.rx_len + len);
    if (!tmp) {
        pthread_mutex_unlock(&g_uart31.lock);
        return -1;
    }
    g_uart31.rx_buff = tmp;
    memcpy(g_uart31.rx_buff + g_uart31.rx_len, data, len);
    g_uart31.rx_len += len;
    uart31_history_push_locked(0, data, len);
    pthread_mutex_unlock(&g_uart31.lock);

    luat_uart_recv_callback(UART31_ID, (int)len);
    return (int)len;
}

void luat_uart31_console_mount(void) {
    uart_drvs[UART31_ID] = &uart_console31;
}

void luat_uart31_console_visit_history(luat_uart31_console_visit_cb_t cb, void* userdata) {
    if (!cb) {
        return;
    }
    uart31_ensure_init();
    pthread_mutex_lock(&g_uart31.lock);
    for (size_t i = 0; i < g_uart31.history_count; i++) {
        size_t idx = (g_uart31.history_start + i) % UART31_HISTORY_MAX;
        cb(g_uart31.history[idx].is_tx,
           g_uart31.history[idx].ts_ms,
           g_uart31.history[idx].data,
           g_uart31.history[idx].len,
           userdata);
    }
    pthread_mutex_unlock(&g_uart31.lock);
}

const luat_uart_drv_opts_t uart_console31 = {
    .setup = uart_setup_console31,
    .write = uart_write_console31,
    .read = uart_read_console31,
    .close = uart_close_console31,
};

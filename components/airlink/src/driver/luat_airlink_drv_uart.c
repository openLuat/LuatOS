#include "luat_base.h"
#include "luat_airlink.h"
#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.uart"
#include "luat_log.h"

int l_uart_handler(lua_State *L, void* ptr);

// 接收缓存与互斥锁。close() 释放时需要引用，故定义在文件顶部。
typedef struct drv_uart_buff {
    size_t remain;
    size_t buff_size;
    luat_rtos_mutex_t mutex;
    uint8_t buff[4];
} drv_uart_buff_t;
static drv_uart_buff_t* uart_rx_buffs[10];


int luat_airlink_drv_uart_setup(luat_uart_t* conf) {
    // --- raw byte path ---
    // LLOGD("执行uart setup %d baud_rate %d", conf->id, conf->baud_rate);
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_uart_t) + sizeof(luat_airlink_cmd_t) + 8
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x400, sizeof(luat_uart_t) + 8);
    if (cmd == NULL) {
        LLOGE("内存分配失败!!");
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    memcpy(cmd->data + 8, conf, sizeof(luat_uart_t));
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
    return 0;
}

int luat_airlink_drv_uart_write(int uart_id, void* data, size_t length) {
    // --- raw byte path (非 RPC 模式) ---
    // 按 1535 字节分段，避免单次过大
    {
        size_t segment_size = 1535;
        const uint8_t* segment_data = (const uint8_t*)data;
        size_t remaining = length;
        size_t sent_total = 0;
        while (remaining > 0) {
            size_t chunk = (remaining > segment_size) ? segment_size : remaining;
            uint64_t next_id = luat_airlink_get_next_cmd_id();
            luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x401, chunk + 1 + 8);
            if (!cmd) { LLOGE("内存分配失败!!"); return (int)sent_total; }
            memcpy(cmd->data,     &next_id,   8);
            uint8_t tmp = (uint8_t)uart_id;
            memcpy(cmd->data + 8, &tmp,        1);
            memcpy(cmd->data + 9,  segment_data, chunk);
            airlink_queue_item_t item = {.len = sizeof(luat_airlink_cmd_t) + chunk + 9, .cmd = cmd};
            int ret = luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);
            if (ret != 0) return (int)sent_total;
            sent_total    += chunk;
            segment_data  += chunk;
            remaining     -= chunk;
        }
        return (int)sent_total;
    }
}

int luat_airlink_drv_uart_close(int uart_id) {
    // --- raw byte path ---
    uint64_t luat_airlink_next_cmd_id = luat_airlink_get_next_cmd_id();
    airlink_queue_item_t item = {
        .len = sizeof(luat_airlink_cmd_t) + 8 + 1
    };
    luat_airlink_cmd_t* cmd = luat_airlink_cmd_new(0x402, 8 + 1);
    if (cmd == NULL) {
        LLOGE("内存分配失败!!");
        return -101;
    }
    memcpy(cmd->data, &luat_airlink_next_cmd_id, 8);
    uint8_t tmp = (uint8_t)uart_id;
    memcpy(cmd->data + 8, &tmp, 1);
    item.cmd = cmd;
    luat_airlink_queue_send(LUAT_AIRLINK_QUEUE_CMD, &item);

    // 释放接收缓存与互斥锁，避免反复 open/close 累积泄漏。
    // 约定：close 由应用层在无并发读写时调用，此处先原子摘除指针再释放。
    if (uart_id >= 10 && uart_id <= 19) {
        drv_uart_buff_t* buff = __sync_lock_test_and_set(&uart_rx_buffs[uart_id - 10], NULL);
        if (buff != NULL) {
            luat_rtos_mutex_delete(buff->mutex);
            luat_heap_free(buff);
        }
    }
    return 0;
}

// 缓存和锁完全初始化后再原子发布；并发创建的败者释放自己的私有副本。
static drv_uart_buff_t* uart_rx_buff_get(uint8_t id, int create) {
    drv_uart_buff_t* buff = __sync_val_compare_and_swap(&uart_rx_buffs[id], NULL, NULL);
    if (buff != NULL || !create) {
        return buff;
    }
    drv_uart_buff_t* candidate = luat_heap_malloc(4096 + sizeof(drv_uart_buff_t));
    if (candidate == NULL) {
        LLOGE("RX buffer allocation failed");
        return NULL;
    }
    candidate->remain = 0;
    candidate->buff_size = 4096;
    candidate->mutex = NULL;
    if (luat_rtos_mutex_create(&candidate->mutex) != 0) {
        luat_heap_free(candidate);
        LLOGE("RX mutex creation failed");
        return NULL;
    }
    buff = __sync_val_compare_and_swap(&uart_rx_buffs[id], NULL, candidate);
    if (buff != NULL) {
        luat_rtos_mutex_delete(candidate->mutex);
        luat_heap_free(candidate);
        return buff;
    }
    return candidate;
}

// 原生接收和Lua读取共用同一把锁；有限等待避免阻塞AirLink任务。
static int uart_rx_buff_lock(drv_uart_buff_t* buff, int uart_id) {
    if (luat_rtos_mutex_lock(buff->mutex, 20) != 0) {
        LLOGE("RX mutex timeout uart %d", uart_id);
        return -103;
    }
    return 0;
}

int luat_airlink_drv_uart_data_cb(int uart_id, void* buffer, size_t length) {
    if (uart_id < 10 || uart_id > 19) {
        return 0;
    }
    drv_uart_buff_t* buff = uart_rx_buff_get(uart_id - 10, 1);
    if (buff == NULL) {
        return -101;
    }
    if (uart_rx_buff_lock(buff, uart_id) != 0) {
        return -103;
    }
    size_t old_remain = buff->remain;
    if (length > buff->buff_size) {
        buff->remain = 0;
        luat_rtos_mutex_unlock(buff->mutex);
        LLOGE("RX OVERFLOW remain %u income %lu", (unsigned)old_remain, (unsigned long)length);
        return -102;
    }
    int overflow = length > buff->buff_size - buff->remain;
    if (overflow) {
        size_t keep = buff->buff_size - length;
        if (keep > 0 && keep < buff->remain) {
            memmove(buff->buff, buff->buff + buff->remain - keep, keep);
        }
        buff->remain = keep;
    }
    memcpy(buff->buff + buff->remain, buffer, length);
    buff->remain += length;
    size_t notified_remain = buff->remain;
    luat_rtos_mutex_unlock(buff->mutex);

    // 日志和异步通知放锁外；通知长度是追加完成时的快照。
    if (overflow) {
        LLOGE("RX OVERFLOW remain %u income %lu", (unsigned)old_remain, (unsigned long)length);
    }
    rtos_msg_t msg = {0};
    msg.handler = l_uart_handler;
    msg.ptr = NULL;
    msg.arg1 = uart_id;
    msg.arg2 = notified_remain;
    luat_msgbus_put(&msg, 0);
    return 0;
}

int luat_airlink_drv_uart_read(int uart_id, void* data, size_t length) {
    if (uart_id < 10 || uart_id > 19) {
        return 0;
    }
    drv_uart_buff_t* buff = uart_rx_buff_get(uart_id - 10, 0);
    if (buff == NULL) {
        return 0;
    }
    if (uart_rx_buff_lock(buff, uart_id) != 0) {
        return -103;
    }
    if (data == NULL) {
        size_t remain = buff->remain;
        luat_rtos_mutex_unlock(buff->mutex);
        return (int)remain;
    }
    if (length > buff->remain) {
        length = buff->remain;
    }
    memcpy(data, buff->buff, length);
    memmove(buff->buff, buff->buff + length, buff->remain - length);
    buff->remain -= length;
    luat_rtos_mutex_unlock(buff->mutex);
    return (int)length;
}

int luat_airlink_drv_uart_sent_cb(int uart_id, void* buffer, size_t length) {
    // 发送完成通知不携带数据，保留统一回调签名。
    (void)buffer;
    (void)length;
    rtos_msg_t msg = {0};
    msg.handler = l_uart_handler;
    msg.ptr = NULL;
    msg.arg1 = uart_id;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
    return 0;
}

int luat_airlink_drv_uart_rx_clear(int uart_id) {
    if (uart_id < 10 || uart_id > 19) {
        return 0;
    }
    drv_uart_buff_t* buff = uart_rx_buff_get(uart_id - 10, 0);
    if (buff == NULL) {
        return 0;
    }
    if (uart_rx_buff_lock(buff, uart_id) != 0) {
        return -103;
    }
    buff->remain = 0;
    luat_rtos_mutex_unlock(buff->mutex);
    return 0;
}

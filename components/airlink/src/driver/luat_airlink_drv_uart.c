#include "luat_base.h"
#include "luat_spi.h"
#include "luat_airlink.h"
#include "luat_airlink_rpc.h"

#include "luat_rtos.h"
#include "luat_debug.h"
#include "luat_spi.h"
#include "luat_pm.h"
#include "luat_gpio.h"
#include "luat_airlink.h"
#include "luat_mem.h"
#include "luat_msgbus.h"
#include "drv_uart.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.uart"
#include "luat_log.h"

#define AIRLINK_DRV_RPC_ID_UART  0x0200
// UART write via nanopb 最大 500 字节（proto max_size 限制），大于则走原始路径
#define UART_WRITE_RPC_MAX  500

int l_uart_handler(lua_State *L, void* ptr);


int luat_airlink_drv_uart_setup(luat_uart_t* conf) {
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload               = drv_uart_UartRpcRequest_setup_tag;
        req.payload.setup.id            = (uint32_t)conf->id;
        req.payload.setup.has_baud_rate = true;
        req.payload.setup.baud_rate     = (uint32_t)conf->baud_rate;
        req.payload.setup.has_data_bits = true;
        req.payload.setup.data_bits     = conf->data_bits;
        req.payload.setup.has_stop_bits = true;
        req.payload.setup.stop_bits     = conf->stop_bits;
        req.payload.setup.has_parity    = true;
        req.payload.setup.parity        = (drv_uart_UartParity)conf->parity;
        req.payload.setup.has_bufsz     = true;
        req.payload.setup.bufsz         = (uint32_t)conf->bufsz;
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_UART,
                                          drv_uart_UartRpcRequest_fields,  &req,
                                          drv_uart_UartRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_uart_UartRpcResponse_setup_tag) return -10;
        if (resp.payload.setup.result.has_code &&
            resp.payload.setup.result.code != drv_uart_UartResultCode_UART_RES_OK) {
            return (int)resp.payload.setup.result.os_errno;
        }
        return 0;
    }
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
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        // 始终走 nb_call，按 UART_WRITE_RPC_MAX 分段循环
        const uint8_t* ptr = (const uint8_t*)data;
        size_t remaining = length;
        int sent_total = 0;
        while (remaining > 0) {
            size_t chunk = (remaining > UART_WRITE_RPC_MAX) ? UART_WRITE_RPC_MAX : remaining;
            drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
            drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
            req.which_payload           = drv_uart_UartRpcRequest_write_tag;
            req.payload.write.id        = (uint32_t)uart_id;
            req.payload.write.data.size = (pb_size_t)chunk;
            memcpy(req.payload.write.data.bytes, ptr, chunk);
            int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_UART,
                                              drv_uart_UartRpcRequest_fields,  &req,
                                              drv_uart_UartRpcResponse_fields, &resp,
                                              2000);
            if (rc != 0) return sent_total > 0 ? sent_total : rc;
            if (resp.which_payload != drv_uart_UartRpcResponse_write_tag) break;
            if (resp.payload.write.result.has_code &&
                resp.payload.write.result.code != drv_uart_UartResultCode_UART_RES_OK) {
                break;
            }
            int written = resp.payload.write.has_bytes_written
                        ? (int)resp.payload.write.bytes_written
                        : (int)chunk;
            sent_total += written;
            ptr       += chunk;
            remaining -= chunk;
            if (written < (int)chunk) break; // short write — stop
        }
        return sent_total;
    }
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
    int mode = luat_airlink_current_mode_get();
    if (luat_airlink_peer_rpc_supported() && mode >= 0) {
        drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
        drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
        req.which_payload          = drv_uart_UartRpcRequest_close_tag;
        req.payload.close.id       = (uint32_t)uart_id;
        int rc = luat_airlink_rpc_nb_call((uint8_t)mode, AIRLINK_DRV_RPC_ID_UART,
                                          drv_uart_UartRpcRequest_fields,  &req,
                                          drv_uart_UartRpcResponse_fields, &resp,
                                          2000);
        if (rc != 0) return rc;
        if (resp.which_payload != drv_uart_UartRpcResponse_close_tag) return -10;
        if (resp.payload.close.result.has_code &&
            resp.payload.close.result.code != drv_uart_UartResultCode_UART_RES_OK) {
            return (int)resp.payload.close.result.os_errno;
        }
        return 0;
    }
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
    return 0;
}

typedef struct drv_uart_buff {
    size_t remain;
    size_t buff_size;
    uint8_t buff[4];
}drv_uart_buff_t;
static drv_uart_buff_t* uart_rx_buffs[10];

int luat_airlink_drv_uart_data_cb(int uart_id, void* buffer, size_t length) {
    // TODO 要接收UART BUFF数据, 返回给用户代码
    if (uart_id >= 10 && uart_id <= 19) {
        uint8_t realy_id = uart_id - 10;
        if (uart_rx_buffs[realy_id] == NULL) {
            uart_rx_buffs[realy_id] = luat_heap_malloc(4096 + sizeof(drv_uart_buff_t));
            if (uart_rx_buffs[realy_id] == NULL) {
                LLOGE("内存分配失败!!");
                return -101;
            }
            uart_rx_buffs[realy_id]->buff_size = 4096;
            uart_rx_buffs[realy_id]->remain = 0;
        }
        if (uart_rx_buffs[realy_id]->remain + length > uart_rx_buffs[realy_id]->buff_size) {
            LLOGE("RX OVERFLOW remain %d income %d", uart_rx_buffs[realy_id]->remain, length);
            // 如果新数据本身就超过缓冲区大小,直接丢弃
            if (length > uart_rx_buffs[realy_id]->buff_size) {
                uart_rx_buffs[realy_id]->remain = 0;
                return -102;
            }
            // 丢弃旧数据头部, 保留尾部, 给新数据腾出空间
            size_t keep = uart_rx_buffs[realy_id]->buff_size - length;
            if (keep > 0 && keep < uart_rx_buffs[realy_id]->remain) {
                memmove(uart_rx_buffs[realy_id]->buff, uart_rx_buffs[realy_id]->buff + uart_rx_buffs[realy_id]->remain - keep, keep);
            }
            uart_rx_buffs[realy_id]->remain = keep;
        }
        memcpy(uart_rx_buffs[realy_id]->buff + uart_rx_buffs[realy_id]->remain,  buffer, length);
        uart_rx_buffs[realy_id]->remain += length;
        
        rtos_msg_t msg = {0};
        msg.handler = l_uart_handler;
        msg.ptr = NULL;
        msg.arg1 = uart_id;
        msg.arg2 = uart_rx_buffs[realy_id]->remain;
        luat_msgbus_put(&msg, 0);
        return 0;
    }
    return 0;
}

int luat_airlink_drv_uart_read(int uart_id, void* data, size_t length) {
    if (uart_id >= 10 && uart_id <= 19) {
        uint8_t realy_id = uart_id - 10;
        if (uart_rx_buffs[realy_id] == NULL) {
            return 0;
        }
        if (data == NULL) {
            return uart_rx_buffs[realy_id]->remain;
        }
        if (length > uart_rx_buffs[realy_id]->remain) {
            length = uart_rx_buffs[realy_id]->remain;
        }
        memcpy(data, uart_rx_buffs[realy_id]->buff, length);
        memmove(uart_rx_buffs[realy_id]->buff, uart_rx_buffs[realy_id]->buff + length, uart_rx_buffs[realy_id]->remain - length);
        uart_rx_buffs[realy_id]->remain -= length;
        // LLOGD("uart[%d] read %d bytes remain %d", uart_id, length, uart_rx_buffs[realy_id]->remain);
        return length;
    }
    return 0;
}

int luat_airlink_drv_uart_sent_cb(int uart_id, void* buffer, size_t length) {
    rtos_msg_t msg = {0};
    msg.handler = l_uart_handler;
    msg.ptr = NULL;
    msg.arg1 = uart_id;
    msg.arg2 = 0;
    luat_msgbus_put(&msg, 0);
    return 0;
}

#include <stdlib.h>
#include <string.h>//add for memset
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_msgbus.h"

#include "luat_uart_drv.h"

#define LUAT_LOG_TAG "uart"
#include "luat_log.h"

const luat_uart_drv_opts_t* uart_drvs[128];

// C层回调函数数组（用于airlink等底层组件）
// 与uart_cbs不同，这个直接存储C函数指针
static void (*uart_c_callbacks[128])(int uart_id, int len) = {NULL};

int luat_uart_setup(luat_uart_t* uart) {
    if (!luat_uart_exist(uart->id))
        return -1;
    return uart_drvs[uart->id]->setup(NULL, uart);
}

int luat_uart_write(int uart_id, void* buffer, size_t length) {
    if (!luat_uart_exist(uart_id))
        return -1;
    return uart_drvs[uart_id]->write(NULL, uart_id, buffer, length);
}

int luat_uart_read(int uart_id, void* buffer, size_t length) {
    if (!luat_uart_exist(uart_id))
        return -1;
    return uart_drvs[uart_id]->read(NULL, uart_id, buffer, length);
}

// void luat_uart_clear_rx_cache(int uart_id) {
//     return 0;
// }

int luat_uart_close(int uart_id) {
    if (!luat_uart_exist(uart_id))
        return 0;
    // 清除C层回调
    uart_c_callbacks[uart_id] = NULL;
    return uart_drvs[uart_id]->close(NULL, uart_id);
}

int luat_uart_exist(int uart_id) {
    if (uart_id < 0 || uart_id >= 128) {
        LLOGE("当前仅支持128个uart, 请检查id");
        return 0;
    }
    if (uart_drvs[uart_id] != NULL)
        return 1;
    return 0;
}

// 供Win32驱动调用的回调函数
// 当Win32 UART收到数据时，先调用C层回调（如果有），再走消息总线
void luat_uart_recv_callback(int uart_id, int len) {
    // 先调用C层回调（airlink等底层组件使用）
    if (uart_id >= 0 && uart_id < 128 && uart_c_callbacks[uart_id] != NULL) {
        uart_c_callbacks[uart_id](uart_id, len);
    }
    
    // 再走消息总线触发Lua层回调
    // 这个消息处理函数是l_uart_handler，它会检查uart_cbs
    extern int l_uart_handler(lua_State *L, void* ptr);
    rtos_msg_t msg = {0};
    msg.handler = l_uart_handler;
    msg.arg1 = uart_id;
    msg.arg2 = len;
    luat_msgbus_put(&msg, 1);
}

// 供luat_lib_uart.c中的luat_setup_cb调用
// 当Lua层设置uart.on("receive", func)时，这里保持兼容性
int luat_setup_cb(int uartid, int received, int sent) {
    return 0;
}

int luat_uart_ctrl(int uart_id, LUAT_UART_CTRL_CMD_E cmd, void* param) {
    LLOGD("luat_uart_ctrl: uart_id=%d, cmd=%d, param=%p", uart_id, cmd, param);
    
    if (uart_id < 0 || uart_id >= 128) {
        return -1;
    }
    
    if (cmd == LUAT_UART_SET_RECV_CALLBACK) {
        // param是C回调函数指针（airlink直接传入）
        if (param != NULL) {
            uart_c_callbacks[uart_id] = (void (*)(int, int))param;
            LLOGD("uart_c_callbacks[%d] set to %p", uart_id, param);
        }
    }
    else if (cmd == LUAT_UART_SET_SENT_CALLBACK) {
        // 发送回调暂不支持
        LLOGW("uart sent callback not supported in PC simulator");
    }
    
    return 0;
}

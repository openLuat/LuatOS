
#include "uv.h"

#include <stdlib.h>
#include <string.h>//add for memset
#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_uart.h"
#include "luat_uart_drv.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "uart.udp"
#include "luat_log.h"

#include "luat_pcconf.h"

void uv_buf_alloc(uv_handle_t *tcp, size_t size, uv_buf_t *buf);

typedef struct uart_drv_udp
{
    // UDP实例
    uv_udp_t udp;
    // void* userdata;
    // 远端配置, 默认应该是广播地址
    struct sockaddr_in remote;
    int state; // 0, closed, 1, open
    char* recv_buff;
    size_t recv_len;
}uart_drv_udp_t;

static uart_drv_udp_t udps[8];
extern uv_loop_t *main_loop;

static void uart_udp_recv_cb(uv_udp_t *udp,
                        ssize_t nread,
                        const uv_buf_t *buf,
                        const struct sockaddr *addr,
                        unsigned flags) {
    if (nread < 0) {
        luat_heap_free(buf->base);
        return;
    }
    if (nread == 0) {
        luat_heap_free(buf->base);
        return;
    }
    int uart_id = (int)udp->data;
    size_t newsize = udps[uart_id].recv_len + nread;
    if (udps[uart_id].recv_buff == NULL) {
        udps[uart_id].recv_buff = luat_heap_malloc(nread);
        udps[uart_id].recv_len = nread;
        memcpy(udps[uart_id].recv_buff, buf->base, nread);
    }
    else {
        void* ptr = luat_heap_realloc(udps[uart_id].recv_buff, newsize);
        if (ptr == NULL) {
            LLOGE("overflow when uart recv");
            luat_heap_free(buf->base);
            return;
        }
        udps[uart_id].recv_buff = ptr;
        memcpy(udps[uart_id].recv_buff + udps[uart_id].recv_len, buf->base, nread);
    }
    luat_heap_free(buf->base);
    rtos_msg_t msg = {
        .handler = l_uart_handler,
        .arg1 = uart_id,
        .arg2 = nread
    };
    luat_msgbus_put(&msg, 0);
}

static int uart_setup_udp(void* userdata, luat_uart_t* uart) {
    if (uart->id < 0 || uart->id >= 8) {
        return -1;
    }
    if (udps[uart->id].state) {
        return 0;
    }
    int ret = 0;
    LLOGD("初始化uart udp %d port %d %d", uart->id, 9000 + uart->id, 19000 + uart->id);
    ret = uv_udp_init(main_loop, &udps[uart->id].udp);
    if (ret)
        LLOGW("uv_udp_init %d", ret);
    udps[uart->id].udp.data = (void*)uart->id;
    struct sockaddr_in addr;
    uv_ip4_addr("0.0.0.0", 9000 + uart->id, &addr);
    ret = uv_udp_bind(&udps[uart->id].udp, (const struct sockaddr*) &addr, 0);
    if (ret)
        LLOGW("uv_udp_bind %d", ret);
    ret = uv_udp_recv_start(&udps[uart->id].udp, uv_buf_alloc, uart_udp_recv_cb);
    if (ret)
        LLOGW("uv_udp_recv_start %d", ret);
    udps[uart->id].state = 1;
    return 0;
}

static void on_sent_udp(uv_udp_send_t *req, int status) {
    if (status < 0) {
        LLOGW("uart udp 发送失败 %d", status);
        return;
    }
    rtos_msg_t msg = {
        .handler = l_uart_handler,
        .arg1 = (int)req->data,
        .arg2 = 0
    };
    luat_msgbus_put(&msg, 0);
}

static int uart_write_udp(void* userdata, int uart_id, void* data, size_t length) {
    if (uart_id < 0 || uart_id >= 8) {
        return 0;
    }
    if (udps[uart_id].state == 0) {
        return 0;
    }
    char* ptr = data;
    uv_buf_t buf;
    struct sockaddr_in dst_addr;
    int ret = 0;
    uv_ip4_addr("127.0.0.1", 19000 + uart_id, &dst_addr);
    while (length > 0) {
        if (length > 512) {
            buf = uv_buf_init(ptr, 512);
            length -= 512;
        }
        else {
            buf = uv_buf_init(ptr, length);
            length = 0;
        }
        uv_udp_send_t* req = luat_heap_malloc(sizeof(uv_udp_send_t));
        req->data = (void*)uart_id;
        ret = uv_udp_send(req, &udps[uart_id].udp, &buf, 1, &dst_addr, on_sent_udp);
        if (ret)
            LLOGE("uv_udp_send %d", ret);
        if (length > 0) {
            uv_sleep(1); // 减少UDP顺序错误
        }
    }
    return length;
}

static int uart_read_udp(void* userdata, int uart_id, void* buffer, size_t length) {
    if (uart_id < 0 || uart_id >= 8) {
        return 0;
    }
    if (udps[uart_id].state == 0) {
        return 0;
    }
    if (udps[uart_id].recv_len == 0) {
        return 0;
    }
    if (length > udps[uart_id].recv_len) {
        length = udps[uart_id].recv_len;
    }
    memcpy(buffer, udps[uart_id].recv_buff, length);
    if (udps[uart_id].recv_len > length) {
        size_t newsize = udps[uart_id].recv_len - length;
        memmove(udps[uart_id].recv_buff, udps[uart_id].recv_buff + udps[uart_id].recv_len, newsize);
        void* ptr = luat_heap_realloc(udps[uart_id].recv_buff, newsize);
        udps[uart_id].recv_buff = ptr;
        udps[uart_id].recv_len = newsize;
    }
    else {
        luat_heap_free(udps[uart_id].recv_buff);
        udps[uart_id].recv_buff = NULL;
        udps[uart_id].recv_len = 0;
    }
    return length;
}

static int uart_close_udp(void* userdata, int uart_id) {
    if (uart_id < 0 || uart_id >= 8) {
        return 0;
    }
    if (udps[uart_id].state == 0) {
        return 0;
    }
    return 0;
}


const luat_uart_drv_opts_t uart_udp = {
    .setup = uart_setup_udp,
    .write = uart_write_udp,
    .read = uart_read_udp,
    .close = uart_close_udp,
};

/*
千寻RTK与LuatOS对接的适配代码
*/

#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_gpio.h"
#include "luat_uart.h"
#include "luat_timer.h"
#include "luat_fs.h"
#include "luat_rtos.h"
#include "luat_network_adapter.h"

#include "qxwz_sdk.h"
#include "qxwz_user_impl.h"

#define LUAT_LOG_TAG "qxwz"
#include "luat_log.h"

#include "luat_mem.h"
#include "luat_mcu.h"

// 日志适配
qxwz_int32_t qxwz_printf(const qxwz_char_t *fmt, ...) {
    va_list args;
    qxwz_int32_t len = 0;
    va_start(args, fmt);
    luat_log_log(LUAT_LOG_DEBUG, LUAT_LOG_TAG, fmt, args);
    va_end(args);
    return 0;
}

// mutext 适配

qxwz_int32_t qxwz_mutex_init(qxwz_mutex_t *mutex) {
    return luat_rtos_mutex_create(&mutex->mutex_entity);
}

qxwz_int32_t qxwz_mutex_trylock(qxwz_mutex_t *mutex) {
    return luat_rtos_mutex_lock(mutex->mutex_entity, 0);
}

qxwz_int32_t qxwz_mutex_lock(qxwz_mutex_t *mutex) {
    return luat_rtos_mutex_lock(mutex->mutex_entity, LUAT_WAIT_FOREVER);
}

qxwz_int32_t qxwz_mutex_unlock(qxwz_mutex_t *mutex) {
    return luat_rtos_mutex_unlock(mutex->mutex_entity);
}

qxwz_int32_t qxwz_mutex_destroy(qxwz_mutex_t *mutex) {
    return luat_rtos_mutex_delete(mutex->mutex_entity);
}


// 内存适配
qxwz_void_t *qxwz_malloc(qxwz_uint32_t size) {
    return luat_heap_malloc(size);
}

qxwz_void_t *qxwz_calloc(qxwz_uint32_t nmemb, qxwz_uint32_t size) {
    return luat_heap_calloc(nmemb, size);
}
qxwz_void_t *qxwz_realloc(qxwz_void_t *ptr, qxwz_uint32_t size) {
    return luat_heap_realloc(ptr, size);
}
qxwz_void_t qxwz_free(qxwz_void_t *ptr) {
    luat_heap_free(ptr);
}

// 网络适配
static network_ctrl_t* qxwz_net_ctrl = NULL;
static uint8_t qxwz_adapter = 0xFF;

static int net_state = 0;

static int32_t qxwz_net_cb(void *data, void *param) {
    OS_EVENT *event = (OS_EVENT *)data;
    if (event->Param1) {
        net_state = 0;
        LLOGD("network_cb event %d", event->Param1);
        return 0;
    }
    if (event->ID == EV_NW_RESULT_LINK){
    
    }
    else if(event->ID == EV_NW_RESULT_CONNECT){
        net_state = 2;
        LLOGD("connect success");
    }
    else if(event->ID == EV_NW_RESULT_EVENT){
        LLOGD("data rx");
    }
    else if(event->ID == EV_NW_RESULT_CLOSE){
        net_state = 0;
        LLOGD("connect closed");
    }
    int ret = network_wait_event(qxwz_net_ctrl, NULL, 0, NULL);
    if (ret)
        LLOGD("network_wait_event ret %d", ret);
    return 0;
}

qxwz_int32_t qxwz_sock_create(void) {
    if (qxwz_net_ctrl == NULL) {
        qxwz_net_ctrl = network_alloc_ctrl(qxwz_adapter);
        if (qxwz_net_ctrl == NULL) {
            LLOGE("create network_ctrl failed");
            return QXWZ_SDK_ERR_FAIL;
        }
        network_init_ctrl(qxwz_net_ctrl, NULL, qxwz_net_cb, NULL);
        network_set_base_mode(qxwz_net_ctrl, 1, 10000, 0, 0, 0, 0);
	    network_set_local_port(qxwz_net_ctrl, 0);
        net_state = 0;
    }
    return 1; // 固定返回1
}

qxwz_int32_t qxwz_sock_connect(qxwz_int32_t sock, qxwz_sock_host_t *serv) {
    if (qxwz_net_ctrl == NULL) {
        LLOGE("call qxwz_sock_create first");
        return QXWZ_SDK_ERR_FAIL;
    }
    network_close(qxwz_net_ctrl, 0);
    int ret = network_connect(qxwz_net_ctrl, serv->hostname, strlen(serv->hostname), NULL, serv->port, 0);
    LLOGD("network_connect ret %d", ret);
    
    if (ret == 0) {
        net_state = 1;
        while (net_state != 1) {
            luat_rtos_task_sleep(10);
        }
    }
    else {
        LLOGD("network_connect ret %d", ret);
        return QXWZ_SDK_ERR_FAIL;
    }
    return net_state == 2 ? QXWZ_SDK_CODE_OK : QXWZ_SDK_ERR_FAIL;
}

qxwz_int32_t qxwz_sock_send(qxwz_int32_t sock, const qxwz_uint8_t *send_buf, qxwz_uint32_t len) {
    if (qxwz_net_ctrl == NULL) {
        LLOGE("call qxwz_sock_create first");
        return QXWZ_SDK_ERR_FAIL;
    }
    size_t tx_len = 0;
    int ret = network_tx(qxwz_net_ctrl, send_buf, len, 0, NULL, 0, &tx_len, 0);
    LLOGD("network_tx ret %d", ret);
    return ret == 0 ? QXWZ_SDK_CODE_OK : QXWZ_SDK_ERR_FAIL;
}

qxwz_int32_t qxwz_sock_recv(qxwz_int32_t sock, qxwz_uint8_t *recv_buf, qxwz_uint32_t len) {
    if (qxwz_net_ctrl == NULL) {
        LLOGE("call qxwz_sock_create first");
        return QXWZ_SDK_ERR_FAIL;
    }
    size_t rx_len = 0;
    int ret = 0;
    ret = network_rx(qxwz_net_ctrl, NULL, 0, 0, NULL, 0, &rx_len);
    if (ret) {
        LLOGE("network_rx ret %d", ret);
        return -2; // 有问题
    }
    if (rx_len == 0) {
        return -1; // 暂无数据
    }
    ret = network_rx(qxwz_net_ctrl, recv_buf, len > rx_len ? rx_len : len, 0, NULL, 0, &rx_len);
    if (ret || rx_len == 0) {
        LLOGE("network_rx ret %d rx_len %d", ret, rx_len);
        return -2; //肯定出问题了
    }
    return rx_len;
}

qxwz_int32_t qxwz_sock_close(qxwz_int32_t sock) {
    if (qxwz_net_ctrl == NULL) {
        LLOGE("call qxwz_sock_create first");
        return QXWZ_SDK_ERR_FAIL;
    }
    network_close(qxwz_net_ctrl, 0);
    return QXWZ_SDK_CODE_OK;
}

void qxwz_task(void* params) {
    (void)params;
    uint64_t ticks = 0;
    while (1) {
        ticks = luat_mcu_tick64_ms();
        qxwz_sdk_tick(ticks / 1000);
        luat_rtos_task_sleep(100); // 10~100ms
    }
}

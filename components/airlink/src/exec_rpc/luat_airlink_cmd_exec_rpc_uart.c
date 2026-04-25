/*
 * AirLink UART nanopb RPC exec handler (服务端)
 *
 * 将 UartRpcRequest 分发到对应的 luat_uart_* 函数，填写 UartRpcResponse。
 * UART id >= 10 的做 id -= 10 归一化（airlink 侧约定）。
 */

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC

#include "luat_airlink_rpc.h"
#include "luat_uart.h"
#include "drv_uart.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.rpc.uart"
#include "luat_log.h"

#define AIRLINK_RPC_ID_UART  0x0200

static void set_result_ok(drv_uart_UartResult* r) {
    r->has_code = true;
    r->code = drv_uart_UartResultCode_UART_RES_OK;
}
static void set_result_fail(drv_uart_UartResult* r, int os_err) {
    r->has_code = true;
    r->code = drv_uart_UartResultCode_UART_RES_FAIL;
    r->has_os_errno = true;
    r->os_errno = os_err;
}

static int uart_rpc_handler(uint16_t rpc_id,
                             const void* req_raw, void* resp_raw,
                             void* userdata) {
    const drv_uart_UartRpcRequest* req  = (const drv_uart_UartRpcRequest*)req_raw;
    drv_uart_UartRpcResponse*      resp = (drv_uart_UartRpcResponse*)resp_raw;

    resp->has_req_id = true;
    resp->req_id     = req->req_id;

    switch (req->which_payload) {
    case drv_uart_UartRpcRequest_setup_tag: {
        const drv_uart_UartSetupRequest* s = &req->payload.setup;
        luat_uart_t uart;
        memset(&uart, 0, sizeof(uart));
        uart.id        = (int)s->id;
        if (uart.id >= 10) uart.id -= 10;
        uart.baud_rate = s->has_baud_rate ? (int)s->baud_rate : 115200;
        uart.data_bits = s->has_data_bits ? (uint8_t)s->data_bits : 8;
        uart.stop_bits = s->has_stop_bits ? (uint8_t)s->stop_bits : 1;
        uart.parity    = s->has_parity    ? (uint8_t)s->parity    : 0;
        uart.bufsz     = s->has_bufsz     ? (size_t)s->bufsz      : 1024;
        uart.pin485    = 0xffffffff;
        int ret = luat_uart_setup(&uart);
        LLOGD("uart[%d] setup baud=%d ret=%d", uart.id, uart.baud_rate, ret);
        resp->which_payload = drv_uart_UartRpcResponse_setup_tag;
        if (ret == 0) set_result_ok(&resp->payload.setup.result);
        else          set_result_fail(&resp->payload.setup.result, ret);
        break;
    }
    case drv_uart_UartRpcRequest_write_tag: {
        const drv_uart_UartWriteRequest* w = &req->payload.write;
        int id = (int)w->id;
        if (id >= 10) id -= 10;
        int ret = luat_uart_write(id, (void*)w->data.bytes, (size_t)w->data.size);
        LLOGD("uart[%d] write %u bytes ret=%d", id, (unsigned)w->data.size, ret);
        resp->which_payload = drv_uart_UartRpcResponse_write_tag;
        if (ret >= 0) {
            set_result_ok(&resp->payload.write.result);
            resp->payload.write.has_bytes_written = true;
            resp->payload.write.bytes_written = ret;
        } else {
            set_result_fail(&resp->payload.write.result, ret);
        }
        break;
    }
    case drv_uart_UartRpcRequest_close_tag: {
        int id = (int)req->payload.close.id;
        if (id >= 10) id -= 10;
        int ret = luat_uart_close(id);
        LLOGD("uart[%d] close ret=%d", id, ret);
        resp->which_payload = drv_uart_UartRpcResponse_close_tag;
        if (ret == 0) set_result_ok(&resp->payload.close.result);
        else          set_result_fail(&resp->payload.close.result, ret);
        break;
    }
    default:
        LLOGW("uart_rpc: 未知 which_payload=%d", (int)req->which_payload);
        return -1;
    }
    return 0;
}

const luat_airlink_rpc_nb_reg_t luat_airlink_rpc_uart_reg = {
    .rpc_id         = AIRLINK_RPC_ID_UART,
    .active         = 1,
    .req_desc       = drv_uart_UartRpcRequest_fields,
    .req_size       = sizeof(drv_uart_UartRpcRequest),
    .resp_desc      = drv_uart_UartRpcResponse_fields,
    .resp_size      = sizeof(drv_uart_UartRpcResponse),
    .handler        = uart_rpc_handler,
    .notify_handler = NULL,
    .userdata       = NULL,
};

#endif /* LUAT_USE_AIRLINK_RPC */

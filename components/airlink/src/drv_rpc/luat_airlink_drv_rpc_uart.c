#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC_UART

#include "luat_airlink.h"
#include "luat_airlink_rpc.h"
#include "luat_uart.h"
#include "luat_mem.h"
#include "drv_uart.pb.h"
#include <string.h>

#define LUAT_LOG_TAG "airlink.uart"
#include "luat_log.h"

#define AIRLINK_DRV_RPC_ID_UART    0x0200
/* nanopb max_size for a single write chunk */
#define UART_WRITE_RPC_MAX  500

int luat_airlink_drv_rpc_uart_setup(luat_uart_t* conf) {
    int mode = luat_airlink_current_mode_get();
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

int luat_airlink_drv_rpc_uart_write(int uart_id, void* data, size_t length) {
    int mode = luat_airlink_current_mode_get();
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
        ptr        += chunk;
        remaining  -= chunk;
        if (written < (int)chunk) break;
    }
    return sent_total;
}

int luat_airlink_drv_rpc_uart_close(int uart_id) {
    int mode = luat_airlink_current_mode_get();
    drv_uart_UartRpcRequest  req  = drv_uart_UartRpcRequest_init_zero;
    drv_uart_UartRpcResponse resp = drv_uart_UartRpcResponse_init_zero;
    req.which_payload        = drv_uart_UartRpcRequest_close_tag;
    req.payload.close.id     = (uint32_t)uart_id;
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

#endif /* LUAT_USE_AIRLINK_RPC_UART */

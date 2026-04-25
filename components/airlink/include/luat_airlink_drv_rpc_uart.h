#ifndef LUAT_AIRLINK_DRV_RPC_UART_H
#define LUAT_AIRLINK_DRV_RPC_UART_H

#include "luat_base.h"

#ifdef LUAT_USE_AIRLINK_RPC_UART
#include "luat_airlink.h"
#include "luat_uart.h"

int luat_airlink_drv_rpc_uart_setup(luat_uart_t* conf);
int luat_airlink_drv_rpc_uart_write(int uart_id, void* data, size_t length);
int luat_airlink_drv_rpc_uart_close(int uart_id);

#endif /* LUAT_USE_AIRLINK_RPC_UART */

#endif /* LUAT_AIRLINK_DRV_RPC_UART_H */

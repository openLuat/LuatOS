#include "luat_base.h"
#include "luat_msgbus.h"
#include "luat_malloc.h"
#include "luat_uart.h"

#define LUAT_LOG_TAG "gnss"
#include "luat_log.h"

#include "minmea.h"
#define RECV_BUFF_SIZE (2048)

void luat_uart_set_app_recv(int id, luat_uart_recv_callback_t cb);



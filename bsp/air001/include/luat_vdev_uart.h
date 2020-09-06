
#include "luat_base.h"
#include "luat_uart.h"

// UART 设备
typedef struct luat_vdev_uart
{
    size_t count;
    luat_uart_t devs[8];
    char recvBuff[1024 * 8];
    char sendBuff[1024 * 8];
}luat_vdev_uart_t;

int luat_vdev_uart_init(void);


#include "luat_base.h"
#include "luat_vdev_gpio.h"
#include "luat_vdev_uart.h"

typedef struct luat_vdev
{
    // 头部信息, 识别码和版本号
    uint16_t magic; // 0x3A 0x3B
    uint16_t version;

    // LuaVM内存池
    size_t luatvm_heap_size;
    char * luatvm_heap_ptr;

    luat_vdev_gpio_t gpio;
    luat_vdev_uart_t uart;

}luat_vdev_t;


int luat_vdev_init();


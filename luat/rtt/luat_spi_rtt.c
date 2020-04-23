

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_log.h"

#include "rtthread.h"
#include "rthw.h"
#include "rtdevice.h"

#define DBG_TAG           "luat.spi"
#define DBG_LVL           DBG_WARN
#include <rtdbg.h>

#ifdef RT_USING_SPI

#define SPI_DEVICE_ID_MAX 3
static struct rt_spi_bus_device* spi_devs[SPI_DEVICE_ID_MAX + 1];

static int luat_spi_rtt_init() {
    char name[16];
    name[0] = 's';
    name[1] = 'p';
    name[2] = 'i';
    name[4] = 0x00;
    
    // 搜索
    for (size_t i = 0; i <= SPI_DEVICE_ID_MAX; i++)
    {
        name[3] = '0' + i;
        spi_devs[i] = (struct rt_i2c_bus_device *)rt_device_find(name);
        LOG_I("search spi name=%s ptr=0x%08X", name, spi_devs[i]);
    }
}

INIT_COMPONENT_EXPORT(luat_spi_rtt_init);

int luat_spi_exist(int id) {
    if (id < 0 || id > SPI_DEVICE_ID_MAX) {
        LOG_W("no such spi device id=%ld", id);
        return 0;
    }
    LOG_I("spi id=%d ptr=0x%08X", id, spi_devs[id]);
    return spi_devs[id] == RT_NULL ? 0 : 1;
}

//初始化配置SPI各项参数，并打开SPI
//成功返回0
int8_t luat_spi_setup(luat_spi_t* spi) {
    return -1;
}
//关闭SPI，成功返回0
uint8_t luat_spi_close(uint8_t spi_id) {
    return -1;
}
//收发SPI数据，返回接收字节数
uint32_t luat_spi_transfer(uint8_t spi_id, uint8_t* send_buf, uint8_t* recv_buf, uint32_t length) {
    return -1;
}
//收SPI数据，返回接收字节数
uint32_t luat_spi_recv(uint8_t spi_id, uint8_t* recv_buf, uint32_t length) {
    return -1;
}
//发SPI数据，返回发送字节数
uint32_t luat_spi_send(uint8_t spi_id, uint8_t* send_buf, uint32_t length) {
    return -1;
}

#endif

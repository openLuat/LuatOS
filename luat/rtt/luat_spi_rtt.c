

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_log.h"

#include "rtthread.h"
#include "rthw.h"
#include "rtdevice.h"

#ifdef SOC_FAMILY_STM32
#include "drv_gpio.h"
#endif

#define DBG_TAG           "luat.spi"
#define DBG_LVL           DBG_WARN
#include <rtdbg.h>

#ifdef RT_USING_SPI

#define SPI_DEVICE_ID_MAX 3
static struct rt_spi_bus_device* spi_devs[SPI_DEVICE_ID_MAX + 1];

static int luat_spi_rtt_init() {
    char name[5];
    name[0] = 's';
    name[1] = 'p';
    name[2] = 'i';
    name[4] = '0';
    name[5] = 0x00;

    // 搜索
    for (size_t i = 0; i <= SPI_DEVICE_ID_MAX; i++)
    {
        name[3] = '0' + i;
        spi_devs[i] = (struct rt_spi_bus_device *)rt_device_find(name);
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
    char bus_name[4];
    char device_name[4];
    device_name[0] = bus_name[0] = 's';
    device_name[1] = bus_name[1] = 'p';
    device_name[2] = bus_name[2] = 'i';
    device_name[4] = '0';
    device_name[5] = bus_name[4] = 0x00;
    if(spi->id > SPI_DEVICE_ID_MAX)
        return -1;
    else
    {
        bus_name[3] = '0' + spi->id;
        device_name[3] = '0' + spi->id;
    }
#ifdef SOC_W60X
    wm_spi_bus_attach_device(bus_name, device_name, spi->cs);
#else
#ifdef SOC_FAMILY_STM32
    //todo
    //rt_spi_bus_attach_device(bus_name, device_name, cs_gpiox, cs_gpio_pin);
    return -1;
#else //其他不去适配
    return -1;
#endif
#endif
    struct rt_spi_device *spi_dev;     /* SPI 设备句柄 */
    spi_dev = (struct rt_spi_device *)rt_device_find(device_name);
    struct rt_spi_configuration cfg;
    cfg.data_width = spi->dataw;
    if(spi->master == 1)
        cfg.mode |= RT_SPI_MASTER;
    else
        cfg.mode |= RT_SPI_SLAVE;
    if(spi->bit_dict == 1)
        cfg.mode |= RT_SPI_MSB;
    else
        cfg.mode |= RT_SPI_LSB;
    if(spi->CPHA)
        cfg.mode |= RT_SPI_CPHA;
    if(spi->CPOL)
        cfg.mode |= RT_SPI_CPOL;
    cfg.max_hz = spi->bandrate;
    rt_spi_configure(spi_dev, &cfg);
    //free(spi_devs[spi->id]);
    spi_devs[spi->id] = spi_dev;
    return 0;
}
//关闭SPI，成功返回0
uint8_t luat_spi_close(uint8_t spi_id) {
    return rt_spi_release_bus(spi_devs[spi_id]);
}
//收发SPI数据，返回接收字节数
uint32_t luat_spi_transfer(uint8_t spi_id, const uint8_t* send_buf, uint8_t* recv_buf, uint32_t length) {
    return rt_spi_transfer(spi_devs[spi_id], send_buf, recv_buf, length);
}
//收SPI数据，返回接收字节数
uint32_t luat_spi_recv(uint8_t spi_id, uint8_t* recv_buf, uint32_t length) {
    return rt_spi_recv(spi_devs[spi_id], recv_buf, length);
}
//发SPI数据，返回发送字节数
uint32_t luat_spi_send(uint8_t spi_id, const uint8_t* send_buf, uint32_t length) {
    return rt_spi_send(spi_devs[spi_id], send_buf, length);
}

#endif

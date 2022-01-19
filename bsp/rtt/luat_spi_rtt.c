

#include "luat_base.h"
#include "luat_spi.h"
#include "luat_log.h"
#include "luat_gpio.h"

#include "rtthread.h"
#include "rthw.h"
#include "rtdevice.h"

#ifdef SOC_FAMILY_STM32
#include "drv_gpio.h"
#endif

#define LUAT_LOG_TAG "spi"
#include "luat_log.h"


#define MAX_DEVICE_COUNT 10

static struct rt_spi_device* luat_spi_device[MAX_DEVICE_COUNT];


static struct rt_spi_device * findDev(int id) {
    char buff[7] = {0};
    sprintf_(buff, "spi%02d", id);
    rt_device_t drv = rt_device_find(buff);
    if (drv == NULL) {
        return RT_NULL;
    }
    if (drv->type != RT_Device_Class_SPIDevice) {
        LLOGW("not spi device %s", buff);
    }
    return (struct rt_spi_device *)drv;
}

int luat_spi_exist(int id) {
    return findDev(id) == RT_NULL ? 0 : 1;
}

int luat_spi_device_setup(luat_spi_device_t* spi_dev) {
    char bus_name[8] = {0};
    char device_name[8] = {0};
    int ret = 0;
    size_t i = 0;
    struct rt_spi_device *spi_device = RT_NULL;     /* SPI 设备句柄 */
    spi_device = (struct rt_spi_device *)rt_malloc(sizeof(struct rt_spi_device));
    RT_ASSERT(spi_device != RT_NULL);

    sprintf_(bus_name, "spi%d", spi_dev->bus_id);
    for ( i = 0; i < MAX_DEVICE_COUNT; i++){
        if (luat_spi_device[i] == RT_NULL){
            sprintf_(device_name, "spi%02d", spi_dev->bus_id*10+i);
            break;
        }
    }

    ret = rt_spi_bus_attach_device(spi_device, device_name,bus_name, NULL);
    if (ret != RT_EOK) {
        rt_free(spi_device);
        LLOGE("fail to attach_device %s", device_name);
        return ret;
    }

    spi_dev->user_data = spi_device;
    spi_dev->spi_config.id=i;
    luat_spi_device[i] = spi_device;

    struct rt_spi_configuration cfg;
    cfg.data_width = spi_dev->spi_config.dataw;
    if(spi_dev->spi_config.master == 1)
        cfg.mode |= RT_SPI_MASTER;
    else
        cfg.mode |= RT_SPI_SLAVE;
    if(spi_dev->spi_config.bit_dict == 1)
        cfg.mode |= RT_SPI_MSB;
    else
        cfg.mode |= RT_SPI_LSB;
    if(spi_dev->spi_config.CPHA)
        cfg.mode |= RT_SPI_CPHA;
    if(spi_dev->spi_config.CPOL)
        cfg.mode |= RT_SPI_CPOL;
    cfg.max_hz = spi_dev->spi_config.bandrate;
    ret = rt_spi_configure(spi_device, &cfg);

    luat_gpio_mode(spi_dev->spi_config.cs, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH); // CS
    return ret;
}

//关闭SPI设备，成功返回0
int luat_spi_device_close(luat_spi_device_t* spi_dev) {
    luat_spi_device[spi_dev->spi_config.id] = NULL;
    rt_free((struct rt_spi_device*)(spi_dev->user_data));
    return rt_spi_release((struct rt_spi_device*)(spi_dev->user_data));
}

//收发SPI数据，返回接收字节数
int luat_spi_device_transfer(luat_spi_device_t* spi_dev, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    luat_gpio_set(spi_dev->spi_config.cs, Luat_GPIO_LOW);
    int ret = rt_spi_send_then_recv((struct rt_spi_device*)(spi_dev->user_data), send_buf, send_length, recv_buf, recv_length);
    luat_gpio_set(spi_dev->spi_config.cs, Luat_GPIO_HIGH);
    return ret;
}

//收SPI数据，返回接收字节数
int luat_spi_device_recv(luat_spi_device_t* spi_dev, char* recv_buf, size_t length) {
    luat_gpio_set(spi_dev->spi_config.cs, Luat_GPIO_LOW);
    int ret = rt_spi_recv((struct rt_spi_device*)(spi_dev->user_data), recv_buf, length);
    luat_gpio_set(spi_dev->spi_config.cs, Luat_GPIO_HIGH);
    return ret;
}

//发SPI数据，返回发送字节数
int luat_spi_device_send(luat_spi_device_t* spi_dev, const char* send_buf, size_t length) {
    luat_gpio_set(spi_dev->spi_config.cs, Luat_GPIO_LOW);
    int ret = rt_spi_send((struct rt_spi_device*)(spi_dev->user_data), send_buf, length);
    luat_gpio_set(spi_dev->spi_config.cs, Luat_GPIO_HIGH);
    return ret;
}


int luat_spi_bus_setup(luat_spi_device_t* spi_dev){
    char bus_name[8] = {0};
    char device_name[8] = {0};
    int ret = 0;
    
    struct rt_spi_device *spi_device = NULL;     /* SPI 设备句柄 */

    sprintf_(bus_name, "spi%d", spi_dev->bus_id);
    sprintf_(device_name, "spi%02d", spi_dev->bus_id);
#ifdef SOC_W60X
    wm_spi_bus_attach_device(bus_name, device_name, spi_dev->spi_config.cs);
    spi_device = findDev(spi_dev->bus_id);
#else
    spi_device = (struct rt_spi_device *)rt_malloc(sizeof(struct rt_spi_device));
    ret = rt_spi_bus_attach_device(spi_device, device_name,bus_name, NULL);
    if (ret != RT_EOK) {
        rt_free(spi_device);
        LLOGE("fail to attach_device %s", device_name);
        return ret;
    }
#endif
// rt_hw_spi_device_attach("spi3", "spi30", GPIOD, GPIO_PIN_7);
    return ret;
}

//初始化配置SPI各项参数，并打开SPI
//成功返回0
int luat_spi_setup(luat_spi_t* spi) {
    char bus_name[8] = {0};
    char device_name[8] = {0};
    int ret = 0;
    
    struct rt_spi_device *spi_dev = NULL;     /* SPI 设备句柄 */

    sprintf_(bus_name, "spi%d", spi->id);
    sprintf_(device_name, "spi%02d", spi->id);
#ifdef SOC_W60X
    wm_spi_bus_attach_device(bus_name, device_name, spi->cs);
    spi_dev = findDev(spi->id);
#else
    spi_dev = (struct rt_spi_device *)rt_malloc(sizeof(struct rt_spi_device));
    RT_ASSERT(spi_dev != RT_NULL);
    ret = rt_spi_bus_attach_device(spi_dev, device_name, bus_name, NULL);
    if (ret != RT_EOK) {
        rt_free(spi_dev);
        LLOGE("fail to attach_device %s", device_name);
        return ret;
    }
#endif
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
    ret = rt_spi_configure(spi_dev, &cfg);
    return ret;
}
//关闭SPI，成功返回0
int luat_spi_close(int spi_id) {
    return 0;
}
//收发SPI数据，返回接收字节数
int luat_spi_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    struct rt_spi_device * drv = findDev(spi_id);
    if (drv == NULL)
        return -1;
    drv = (struct rt_spi_device *)rt_device_find("spi30");
    return rt_spi_send_then_recv(drv, send_buf, send_length, recv_buf, recv_length);
}
//收SPI数据，返回接收字节数
int luat_spi_recv(int spi_id, char* recv_buf, size_t length) {
    struct rt_spi_device * drv = findDev(spi_id);
    if (drv == NULL)
        return -1;
    drv = (struct rt_spi_device *)rt_device_find("spi30");
    return rt_spi_recv(drv, recv_buf, length);
}
//发SPI数据，返回发送字节数
int luat_spi_send(int spi_id, const char* send_buf, size_t length) {
    // struct rt_spi_device * drv = findDev(spi_id);
    // if (drv == NULL)
    //     return -1;
    struct rt_spi_device * drv = (struct rt_spi_device *)rt_device_find("spi30");
    int a = rt_spi_send(drv, send_buf, length);
    // rt_kprintf("luat_spi_send spi_id:%d send_buf:%s length:%d return:%d \r\n", spi_id,send_buf, length,a);
    return a;
}


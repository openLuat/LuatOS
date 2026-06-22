#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_spi.h"
#include "luat_rtos.h"

#define LUAT_SPI_CS_SELECT 0
#define LUAT_SPI_CS_CLEAR  1

// luat_spi_device_t* 在lua层看到的是一个userdata
LUAT_WEAK int luat_spi_device_setup(luat_spi_device_t* spi_dev) {
    luat_spi_bus_setup(spi_dev);
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_mode(spi_dev->spi_config.cs, Luat_GPIO_OUTPUT, Luat_GPIO_DEFAULT, Luat_GPIO_HIGH); // CS
    return 0;
}

//关闭SPI设备，成功返回0
LUAT_WEAK int luat_spi_device_close(luat_spi_device_t* spi_dev) {
    return luat_spi_close(spi_dev->bus_id);
}

//收发SPI数据，返回接收字节数
LUAT_WEAK int luat_spi_device_transfer(luat_spi_device_t* spi_dev, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    int ret = -1;
    luat_spi_lock(spi_dev->bus_id);
    luat_spi_device_config(spi_dev);
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_SELECT);
    if (spi_dev->spi_config.mode){
        if (send_length>recv_length){
            recv_length = send_length;
        }else{
            send_length = recv_length;
        }
        ret = luat_spi_transfer(spi_dev->bus_id, send_buf, send_length, recv_buf, recv_length);
    }else{
        if (send_length){
            ret = luat_spi_send(spi_dev->bus_id, send_buf, send_length);
        }
        if (recv_length){
            ret = luat_spi_recv(spi_dev->bus_id, recv_buf, recv_length);
        }
    }
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_CLEAR);
    luat_spi_unlock(spi_dev->bus_id);
    return ret;
}

//收SPI数据，返回接收字节数
LUAT_WEAK int luat_spi_device_recv(luat_spi_device_t* spi_dev, char* recv_buf, size_t length) {
	luat_spi_lock(spi_dev->bus_id);
    luat_spi_device_config(spi_dev);
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_SELECT);
    int ret = luat_spi_recv(spi_dev->bus_id, recv_buf, length);
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_CLEAR);
    luat_spi_unlock(spi_dev->bus_id);
    return ret;
}

//发SPI数据，返回发送字节数
LUAT_WEAK int luat_spi_device_send(luat_spi_device_t* spi_dev, const char* send_buf, size_t length) {
	luat_spi_lock(spi_dev->bus_id);
    luat_spi_device_config(spi_dev);
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_SELECT);
    int ret = luat_spi_send(spi_dev->bus_id, send_buf, length);
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_CLEAR);
    luat_spi_unlock(spi_dev->bus_id);
    return ret;
}

LUAT_WEAK int luat_spi_lock(int spi_id)
{
    return -1;
}

LUAT_WEAK int luat_spi_unlock(int spi_id)
{
	return -1;
}

// 弱默认：BSP 未实现 trans_msgs 时返回 -1，由调用方走 luat_spi_transfer 回退路径
LUAT_WEAK int luat_spi_trans_msgs(int spi_id, luat_spi_msg_t* msgs, size_t count) {
    (void)spi_id; (void)msgs; (void)count;
    return -1;
}

// 弱默认：BSP 未实现 xfer2 时返回 -1，强双工接口不允许半双工降级
LUAT_WEAK int luat_spi_xfer2(int spi_id, const uint8_t* tx, uint8_t* rx, size_t len) {
    (void)spi_id; (void)tx; (void)rx; (void)len;
    return -1;
}

// 弱默认：通用 device 级 trans_msgs 回退实现，逐条转译为 luat_spi_send/_recv
// PAUSE_MS 走 luat_rtos_task_sleep；PAUSE_US 当 len>=1000 时近似为 sleep(len/1000)；
// XFER 默认返回 -1（禁止半双工降级）。
LUAT_WEAK int luat_spi_device_trans_msgs(luat_spi_device_t* spi_dev, luat_spi_msg_t* msgs, size_t count) {
    if (!spi_dev) return -1;
    if (count == 0) return 0;
    if (!msgs) return -1;
    luat_spi_lock(spi_dev->bus_id);
    luat_spi_device_config(spi_dev);
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_SELECT);
    int ret = 0;
    for (size_t i = 0; i < count && ret >= 0; i++) {
        switch (msgs[i].mode) {
            case LUAT_SPI_MSG_SEND:
                if (msgs[i].len > 0) {
                    if (!msgs[i].buff) { ret = -1; break; }
                    int r = luat_spi_send(spi_dev->bus_id, (const char*)msgs[i].buff, msgs[i].len);
                    if (r < 0) ret = -1;
                }
                break;
            case LUAT_SPI_MSG_RECV:
                if (msgs[i].len > 0) {
                    if (!msgs[i].buff) { ret = -1; break; }
                    int r = luat_spi_recv(spi_dev->bus_id, (char*)msgs[i].buff, msgs[i].len);
                    if (r < 0) ret = -1;
                }
                break;
            case LUAT_SPI_MSG_PAUSE_US:
                if (msgs[i].len >= 1000) {
                    luat_rtos_task_sleep((uint32_t)(msgs[i].len / 1000));
                }
                break;
            case LUAT_SPI_MSG_PAUSE_MS:
                luat_rtos_task_sleep((uint32_t)msgs[i].len);
                break;
            case LUAT_SPI_MSG_XFER:
                ret = -1;
                break;
            default:
                ret = -1;
                break;
        }
    }
    if (spi_dev->spi_config.cs != 255)
        luat_gpio_set(spi_dev->spi_config.cs, LUAT_SPI_CS_CLEAR);
    luat_spi_unlock(spi_dev->bus_id);
    return ret;
}

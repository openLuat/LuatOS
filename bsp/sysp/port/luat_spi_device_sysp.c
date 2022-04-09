#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_spi.h"

// luat_spi_device_t* 在lua层看到的是一个userdata
int luat_spi_device_setup(luat_spi_device_t* spi_dev) {
    return 0;
}

//关闭SPI设备，成功返回0
int luat_spi_device_close(luat_spi_device_t* spi_dev) {
    return 0;
}

//收发SPI数据，返回接收字节数
int luat_spi_device_transfer(luat_spi_device_t* spi_dev, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    memset(recv_buf, 0, recv_length);
    return recv_length;
}

//收SPI数据，返回接收字节数
int luat_spi_device_recv(luat_spi_device_t* spi_dev, char* recv_buf, size_t length) {
    memset(recv_buf, 0, length);
    return length;
}

//发SPI数据，返回发送字节数
int luat_spi_device_send(luat_spi_device_t* spi_dev, const char* send_buf, size_t length) {
    return length;
}


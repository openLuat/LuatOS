
#include "luat_base.h"
#include "luat_gpio.h"
#include "luat_msgbus.h"
#include "luat_spi.h"

int luat_spi_device_config(luat_spi_device_t* spi_dev){
    return 0;
}

int luat_spi_bus_setup(luat_spi_device_t* spi_dev){
    return 0;
}

int luat_spi_setup(luat_spi_t* spi) {
    return 0;
}
//关闭SPI，成功返回0
int luat_spi_close(int spi_id) {
    return 0;
}
//收发SPI数据，返回接收字节数
int luat_spi_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length) {
    memset(recv_buf, 0, recv_length);
    return recv_length;
}
//收SPI数据，返回接收字节数
int luat_spi_recv(int spi_id, char* recv_buf, size_t length) {
    memset(recv_buf, 0, length);
    return length;
}
//发SPI数据，返回发送字节数
int luat_spi_send(int spi_id, const char* send_buf, size_t length) {
    return length;
}

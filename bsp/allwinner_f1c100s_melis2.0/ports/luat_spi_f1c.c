#include "luat_base.h"
#include "luat_spi.h"

int luat_spi_setup(luat_spi_t* spi) {
    return -1;
}
//关闭SPI，成功返回0
int luat_spi_close(int spi_id) {
    return 0;
}
//收发SPI数据，返回接收字节数
int luat_spi_transfer(int spi_id, const char* send_buf, char* recv_buf, size_t length) {
    return 0;
}
//收SPI数据，返回接收字节数
int luat_spi_recv(int spi_id, char* recv_buf, size_t length) {
    return 0;
}
//发SPI数据，返回发送字节数
int luat_spi_send(int spi_id, const char* send_buf, size_t length) {
    return 0;
}

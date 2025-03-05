/*
SPI从机模式的驱动头文件
*/

#ifndef LUAT_SPISLAVE_H
#define LUAT_SPISLAVE_H

#include "luat_base.h"
#include "luat_spi.h"
// typedef struct luat_spislave_conf {
//     luat_spi_t base; // 继承spi配置结构体
//     size_t buff_len; // 接收长度,注意tx/rx是相同大小的,默认4k
//     uint8_t *rx_buff; // 接收缓冲区
//     uint8_t *tx_buff; // 发送缓冲区
// } luat_spislave_conf_t;

/*初始化SPI从机*/
int luat_spislave_setup(luat_spi_t* conf);
/*反初始化SPI从机*/
int luat_spislave_close(int spi_id);
/*开始SPI传输,异步的 */
int luat_spislave_start(int spi_id, const char* send_buf, char* recv_buf, size_t length);
/*停止SPI传输*/
int luat_spislave_stop(int spi_id);
/*获取接收到的长度 */
int luat_spislave_get_rxlen(int spi_id);
/*停止传输并获取接收到的长度 */
int luat_spislave_stopAndGetlen(int spi_id);

#endif
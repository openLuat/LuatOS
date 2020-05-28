
#include "luat_base.h"

typedef struct luat_spi
{
    /* data */
    uint8_t  id;      // id
    uint8_t  CPHA;    // CPHA
    uint8_t  CPOL;    // CPOL
    uint8_t  dataw;   // 数据宽度
    uint8_t  bit_dict;// 高低位顺序    可选，默认高位在前
    uint8_t  master;  // 主模式     可选，默认主
    uint8_t  mode;    // 全双工       可选，默认全双工
    uint32_t bandrate;// 最大频率20M
    uint32_t cs;      // cs控制引脚
} luat_spi_t;

/**
    spiId,--串口id
    cs,
    0,--CPHA
    0,--CPOL
    8,--数据宽度
    20000000,--最大频率20M
    spi.MSB,--高低位顺序    可选，默认高位在前
    spi.master,--主模式     可选，默认主
    spi.full,--全双工       可选，默认全双工
*/

//初始化配置SPI各项参数，并打开SPI
//成功返回0
int8_t luat_spi_setup(luat_spi_t* spi);
//关闭SPI，成功返回0
uint8_t luat_spi_close(uint8_t spi_id);
//收发SPI数据，返回接收字节数
uint32_t luat_spi_transfer(uint8_t spi_id, const uint8_t* send_buf, uint8_t* recv_buf, uint32_t length);
//收SPI数据，返回接收字节数
uint32_t luat_spi_recv(uint8_t spi_id, uint8_t* recv_buf, uint32_t length);
//发SPI数据，返回发送字节数
uint32_t luat_spi_send(uint8_t spi_id, const uint8_t* send_buf, uint32_t length);

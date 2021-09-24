
#ifndef LUAT_SPIV2
#define LUAT_SPIV2
#include "luat_base.h"

typedef struct luat_spiv2
{
    /* data */
    int  bus_id;     // bus
    int  CPHA;    // CPHA
    int  CPOL;    // CPOL
    int  dataw;   // 数据宽度
    int  bit_dict;// 高低位顺序    可选，默认高位在前
    int  master;  // 主模式     可选，默认主
    int  mode;    // 全双工       可选，默认全双工
    int bandrate;// 最大频率
    int cs;      // cs控制引脚
    void *user_data;// some user data
} luat_spiv2_t;

/**
    busId,
    cs,
    0,--CPHA
    0,--CPOL
    8,--数据宽度
    20000000,--最大频率20M
    spi.MSB,--高低位顺序    可选，默认高位在前
    spi.master,--主模式     可选，默认主
    spi.full,--全双工       可选，默认全双工
*/
//初始化配置SPI设备各项参数，并打开SPI
//成功返回dev_id,失败返回-1
int luat_spiv2_setup(luat_spiv2_t* spi_dev);
//关闭SPI总线，成功返回0
int luat_spiv2_bus_close(int bus_id);
//关闭SPI设备，成功返回0
int luat_spiv2_device_close(int dev_id);
//收发SPI数据，返回接收字节数
int luat_spiv2_transfer(int dev_id, const char* send_buf, char* recv_buf, size_t length);
//收SPI数据，返回接收字节数
int luat_spiv2_recv(int dev_id, char* recv_buf, size_t length);
//发SPI数据，返回发送字节数
int luat_spiv2_send(int dev_id, const char* send_buf, size_t length);

#endif


#ifndef LUAT_SPI_H
#define LUAT_SPI_H
#include "luat_base.h"

typedef struct luat_spi
{
    /* data */
    int  id;      // id
    int  CPHA;    // CPHA
    int  CPOL;    // CPOL
    int  dataw;   // 数据宽度
    int  bit_dict;// 高低位顺序    可选，默认高位在前
    int  master;  // 主模式     可选，默认主
    int  mode;    // 全双工       可选，默认全双工
    int bandrate;// 最大频率20M
    int cs;      // cs控制引脚
} luat_spi_t;

typedef struct luat_spi_device
{
    uint8_t  bus_id;
    luat_spi_t spi_config;
    void* user_data;
} luat_spi_device_t;

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
int luat_spi_setup(luat_spi_t* spi);
//关闭SPI，成功返回0
int luat_spi_close(int spi_id);
//收发SPI数据，返回接收字节数
int luat_spi_transfer(int spi_id, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length);
//收SPI数据，返回接收字节数
int luat_spi_recv(int spi_id, char* recv_buf, size_t length);
//发SPI数据，返回发送字节数
int luat_spi_send(int spi_id, const char* send_buf, size_t length);

// 初始化总线
int luat_spi_bus_setup(luat_spi_device_t* spi_dev);
// 初始化设备
int luat_spi_device_setup(luat_spi_device_t* spi_dev);
// 配置设备
int luat_spi_device_config(luat_spi_device_t* spi_dev);
//关闭SPI设备，成功返回0
int luat_spi_device_close(luat_spi_device_t* spi_dev);
//收发SPI数据，返回接收字节数
int luat_spi_device_transfer(luat_spi_device_t* spi_dev, const char* send_buf, size_t send_length, char* recv_buf, size_t recv_length);
//收SPI数据，返回接收字节数
int luat_spi_device_recv(luat_spi_device_t* spi_dev, char* recv_buf, size_t length);
//发SPI数据，返回发送字节数
int luat_spi_device_send(luat_spi_device_t* spi_dev, const char* send_buf, size_t length);

#endif

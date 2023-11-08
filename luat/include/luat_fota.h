#ifndef LUAT_FOTA_H
#define LUAT_FOTA_H

#include "luat_base.h"
#include "luat_spi.h"
/**
 * @defgroup luatos_fota 远程升级接口
 * @{
 */

/**
 * @brief 用于初始化fota,创建写入升级包数据的上下文结构体
 * 
 * @param start_address,开始地址 718/716系列填0
 * @param  len 长度 718/716系列填0
 * @param  spi_device 长度 718/716系列填NULL
 * @param  path 长度 718/716系列填NULL
 * @param  pathlen 长度 718/716系列填0
 * @return  
 */

int luat_fota_init(uint32_t start_address, uint32_t len, luat_spi_device_t* spi_device, const char *path, uint32_t pathlen);

/// @brief 用于向本地 Flash 中写入升级包数据
/// @param data 升级包数据
/// @param len 升级包数据长度
/// @return int =0成功，其他失败
int luat_fota_write(uint8_t *data, uint32_t len);

/// @brief 用于结束升级包下载
/// @return int =0成功，其他失败
int luat_fota_done(void);

int luat_fota_end(uint8_t is_ok);

/// @brief 等待fota 准备，目前没有什么作用
/// @param  
/// @return uint8_t =1 准备好
uint8_t luat_fota_wait_ready(void);
/** @}*/
#endif

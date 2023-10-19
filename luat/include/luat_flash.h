
#ifndef LUAT_flash_H
#define LUAT_flash_H
#include "luat_base.h"
/**
 * @defgroup luatos_flash 片上Flash操作
 * @{
 */

/**
 * @brief 读取指定区域的Flash数据
 * 
 * @param buff[OUT] 读出的数据
 * @param addr 偏移量, 与具体设备相关
 * @param len 读取长度
 * @return int <= 0错误 >0实际读取的大小
 */
int luat_flash_read(char* buff, size_t addr, size_t len);

/**
 * @brief 写入指定区域的flash数据
 * 
 * @param buff[IN] 写入的数据
 * @param addr 偏移量, 与具体设备相关
 * @param len 写入长度
 * @return int <= 0错误 >0实际写入的大小
 */
int luat_flash_write(char* buff, size_t addr, size_t len);

/**
 * @brief 抹除指定区域的flash数据
 * 
 * @param addr 偏移量, 与具体设备相关
 * @param len 抹除长度,通常为区域大小, 例如4096
 * @return int != 0错误 =0 正常
 */
int luat_flash_erase(size_t addr, size_t len);


/**
 * @brief 获取kv起始地址与长度
 * @param len kv大小, 与具体设备相关
 * @return size_t = 0错误 !=0 正常
 */
size_t luat_flash_get_fskv_addr(size_t *len);

/**
 * @}
 */
#endif

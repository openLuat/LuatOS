#ifndef LUAT_I2C_H
#define LUAT_I2C_H

#include "luat_base.h"

enum{
    I2C_SPEED_SLOW = 0,
    I2C_SPEED_FAST,
    I2C_SPEED_PLUS,
    I2C_SPEED_HSMODE,
};

/**
 * @defgroup luatos_device_i2c I2C接口
 * @{
*/

/**
 * @brief 检查i2c是否存在
 * 
 * @param id i2c_id
 * @return 1存在 0不存在
 */
int luat_i2c_exist(int id);

/**
 * @brief 初始化i2c
 * 
 * @param id i2c_id
 * @param speed i2c 速度
 * @return 0成功 其他失败
 */
int luat_i2c_setup(int id, int speed);

/**
 * @brief 关闭 i2c
 * 
 * @param id i2c_id
 * @return 0成功 其他失败
 */

int luat_i2c_close(int id);
/**
 * @brief I2C 发送数据
 * 
 * @param id i2c_id
 * @param addr 7位设备地址
 * @param buff 数据buff
 * @param len 数据长度
 * @param stop 是否发送停止位
 * @return 0成功 其他失败
 */

int luat_i2c_send(int id, int addr, void* buff, size_t len, uint8_t stop);

/**
 * @brief I2C 接受数据
 * 
 * @param id i2c_id
 * @param addr 7位设备地址
 * @param buff 数据buff
 * @param len 数据长度
 * @return 0成功 其他失败
 */
int luat_i2c_recv(int id, int addr, void* buff, size_t len);

/**
 * @brief I2C 写寄存器
 * 
 * @param id i2c_id
 * @param addr 7位设备地址
 * @param reg 寄存器地址
 * @param buff 数据
 * @param len 数据长度
 * @param stop 是否发送停止位
 * @return 0成功 其他失败
 */
int luat_i2c_write_reg(int id, int addr, int reg, void* buff, size_t len, uint8_t stop);
/**
 * @brief I2C 读寄存器
 * 
 * @param id i2c_id
 * @param addr 7位设备地址
 * @param reg 寄存器地址
 * @param buff 数据
 * @param len 数据长度
 * @return 0成功 其他失败
 */
int luat_i2c_read_reg(int id, int addr, int reg, void* buff, size_t len);
/**
 * @brief I2C 收发数据
 * 
 * @param id i2c_id
 * @param addr 7位设备地址
 * @param reg 读的寄存器
 * @param reg_len 寄存器长度
 * @param buff 如果reg，reg_len 不为NULL，buff 为读的数据保存缓冲区，反之为写的缓冲区
 * @param len 数据长度
 * @return 0成功 其他失败
 */
int luat_i2c_transfer(int id, int addr, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len);

/**
 * @brief I2C 收发数据(异步)
 * 
 * @param id i2c_id
 * @param addr 7位设备地址
 * @param is_read 是否为读写
 * @param reg 读的寄存器
 * @param reg_len 寄存器长度
 * @param buff 如果reg，reg_len 不为NULL，buff 为读的数据保存缓冲区，反之为写的缓冲区
 * @param len 数据长度
 * @param Toms 数据长度
 * @param CB 回调函数
 * @param pParam 回调函数参数
 * @return 0成功 其他失败
 */
int luat_i2c_no_block_transfer(int id, int addr, uint8_t is_read, uint8_t *reg, size_t reg_len, uint8_t *buff, size_t len, uint16_t Toms, void *CB, void *pParam);

/**
 * @brief 设置i2c复用
 * @attention 
 * @attention 
 * @param id i2c_id
 * @return -1 失败 其他正常
 */
int luat_i2c_set_iomux(int id, uint8_t value);

int luat_i2c_set_polling_mode(int id, uint8_t on_off);

/**
 * @brief 锁定I2C，只有主模式下才能使用，多个设备挂载在同一条总线上需要使用
 *
 * @param id i2c总线id
 * @return int 成功返回0，其他-1
 */
int luat_i2c_lock(int id);

/**
 * @brief 释放I2C，只有主模式下才能使用，多个设备挂载在同一条总线上需要使用
 *
 * @param id i2c总线id
 * @return int 成功返回0，其他-1
 */
int luat_i2c_unlock(int id);
/**@}*/
/** @}*/

#define LUAT_EI2C_TYPE "EI2C*"

typedef struct luat_ei2c {
    int8_t sda;
    int8_t scl;
    int16_t udelay;
} luat_ei2c_t;//软件i2c

int i2c_soft_setup(luat_ei2c_t *ei2c);
int i2c_soft_recv(luat_ei2c_t *ei2c, unsigned char addr, char *buff, size_t len);
int i2c_soft_send(luat_ei2c_t *ei2c, unsigned char addr, char *data, size_t len, uint8_t stop);
int i2c_soft_close(luat_ei2c_t *ei2c);

#define toei2c(L) ((luat_ei2c_t *)luaL_checkudata(L, 1, LUAT_EI2C_TYPE))

#endif

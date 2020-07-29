/**
 * @file hw_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief 通用硬件外设操作，包括uart,gpio,spi,i2c,hw_timer等等
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __HW_API_H__
#define __HW_API_H__
/**
 * @brief 硬件外设在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 */
void luatos_hw_init(void);
#endif
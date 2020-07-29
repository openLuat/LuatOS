/**
 * @file hw_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief 通用硬件外设操作，包括uart，ADC，gpio，spi，i2c，hw_timer，lp_timer等等
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __HW_API_H__
#define __HW_API_H__
#include "api_config.h"
/**
 * @brief 硬件外设在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 */
void luatos_hw_init(void);

/**
 * @brief 创建一个非高精度定时器
 * 
 * @note 允许在时间到时，回调函数或者任务通知，回调函数优先，无回调函数情况下，才任务通知
 * @param callback_entry_address 定时器时间到，回调函数入口地址，和回调通知任务不能同时用
 * @param task_handle 定时器时间到，回调通知的任务，和回调函数不能同时用
 * @param timer_param 定时器回调参数，返回给回调函数，或者发送luatos_message_t.param2给task
 * @param timeout_ms 定时器时间，单位ms
 * @param repeat 是否重复运行，1是，0否
 * @param lowpower_mode 是否可以在低功耗模式下运行, 1可以，0不可以
 * @return LUATOS_HANDLE 返回一个定时器句柄，失败返回NULL
 */
LUATOS_HANDLE luatos_hw_create_timer(
    u32 callback_entry_address, LUATOS_HANDLE task_handle, u32 timer_param, u32 timeout_ms, u8 repeat, u8 lowpower_mode);

/**
 * @brief 销毁一个非高精度定时器
 * 
 * @param timer_handle 定时器句柄
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_destory_timer(LUATOS_HANDLE timer_handle);

/**
 * @brief 启动一个非高精度定时器
 * 
 * @param timer_handle 
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_start_timer(LUATOS_HANDLE timer_handle);

/**
 * @brief 停止一个非高精度定时器
 * 
 * @param timer_handle 
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_stop_timer(LUATOS_HANDLE timer_handle);

/**
 * @brief 停止同一个回调函数的所有非高精度定时器
 * 
 * @param callback_entry_address 回调函数入口地址
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_hw_stop_callback_timers(u32 callback_entry_address);
#endif
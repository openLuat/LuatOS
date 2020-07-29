/**
 * @file os_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief OS相关API
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __OS_API_H__
#define __OS_API_H__
#include "api_config.h"
/**
 * @brief OS在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 */
void luatos_os_init(void);

/**
 * @brief luatos向sdk发送数据，通常用于message发送，虚拟AT发送等
 * 
 * @param param1 参数1
 *              @arg @ref 0xffffffff 虚拟AT发送
 * @param param2 参数2
 *              @arg @ref 发送虚拟AT时，为AT数据首地址，一般转换为char *
 * @param param3 参数3
 *              @arg @ref 发送虚拟AT时，为AT数据长度
 * @param param4 参数4
 * @return LUATOS_STATUS
 */
LUATOS_STATUS luatos_os_send_message(uint32_t param1, uint32_t param2, uint32_t param3, uint32_t param4);

/**
 * @brief sdk向luatos发送数据，通常用于message发送，虚拟AT发送等
 * 
 * @param [out]message 接收到的message
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_os_wait_message(luatos_message_t *message);
/**
 * @brief 在发生重大异常时，选择进入debug模式冻结系统，或者重启
 * 
 * @param enable 是否进入debug模式冻结系统
 *              @arg @ref 1 进入debug模式
 *              @arg @ref 0 重启
 * @return LUATOS_STATUS 
 */

LUATOS_STATUS luatos_os_set_debug_break(u8 enable);
/**
 * @brief 读取 在发生重大异常时，选择进入debug模式冻结系统，或者重启的标志位
 * 
 * @return u8 标志位说明
 *          @arg @ref 1 进入debug模式
 *          @arg @ref 0 重启 
 */
u8 luatos_os_get_debug_break(void);

/**
 * @brief 断言
 * 
 * @param cond 断言条件
 * @param fmt 附加打印格式
 * @param ... 附加打印参数
 */
void luatos_os_assert(uint8_t cond, const char *fmt, ...);

/**
 * @brief 格式化打印调试信息
 * 
 * @param fmt 打印格式
 * @param ... 打印参数
 */
void luatos_os_trace_fmt(const char *fmt, ...);

/**
 * @brief 打印字符串调试信息，适用于SDK无法正常打印某些格式的情况
 * 
 * @param string 需要输出的字符串
 */
void luatos_os_trace_string(const char *string);

/**
 * @brief 重启，必须保证可靠重启
 * 
 */
void luatos_os_reset(void);

/**
 * @brief 关机
 * 
 */
void luatos_os_shutdown(void);

/**
 * @brief 创建一个task，并且进入可立即运行的状态
 * 
 * @param entry_address task实体函数的入口地址
 * @param task_param task的输入参数
 * @param task_name task名称
 * @param stack_size 栈空间期望大小
 * @param priority task优先级
 * @param [out]handle 返回的task句柄
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_os_start_task(u32 entry_address, void *task_param, const char *task_name, u32 stack_size, u8 priority, u32 *handle);


#endif

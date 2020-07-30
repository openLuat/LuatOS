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
 * @param [OUT]handle 返回的task句柄
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_os_start_task(u32 entry_address, void *task_param, const char *task_name, u32 stack_size, u8 priority, LUATOS_HANDLE *handle);

/**
 * @brief task休眠
 * 
 * @param msec 休眠时间，单位ms
 */
void luatos_os_task_sleep(u32 msec);

/**
 * @brief 进入临界保护，一般需要关闭中断
 * 
 * @return LUATOS_HANDLE 返回一个句柄，用于退出临界保护
 */
LUATOS_HANDLE luatos_os_enter_critical_section(void);

/**
 * @brief 退出临界保护，一般需要打开中断
 * 
 * @param handle 进入临界保护时返回的句柄
 */
void luatos_os_exit_critical_section(LUATOS_HANDLE handle);

/**
 * @brief 创建一个信号量
 * 
 * @param init_value 信号量初始值，一般为1
 * @return LUATOS_HANDLE 返回一个信号量，如果失败为NULL
 */
LUATOS_HANDLE luatos_os_create_semaphore(u32 init_value);

/**
 * @brief 销毁一个信号量
 * 
 * @param handle 信号量
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_os_destroy_semaphore(LUATOS_HANDLE handle);

/**
 * @brief 获取一个信号量，根据等待时间参数决定是否立刻返回
 * 
 * @param handle 希望获取的信号量
 * @param timeout 超时参数
 *              @arg @ref 0 如果获取不到，立刻返回失败
 *              @arg @ref 0xffffffff 如果获取不到，则一直等待
 *              @arg @ref 其他为等待时间，单位ms
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_os_wait_semaphore(LUATOS_HANDLE handle, u32 timeout);

/**
 * @brief 立刻释放一个信号量
 * 
 * @param handle 释放的信号量
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_os_release_semaphore(LUATOS_HANDLE handle);

/**
 * @brief 获取开机到现在经历的时间
 * 
 * @return uint64_t 单位是ms
 */
uint64_t luatos_os_get_run_time_ms(void);

/**
 * @brief 获取开机到现在经历的时间，不是必须实现的
 * 
 * @return uint64_t 单位是us
 */
uint64_t luatos_os_get_run_time_us(void);

/**
 * @brief 动态分配内存
 * 
 * @param size 希望分配到的字节数
 * @return void* 失败为NULL，否则返回首地址
 */
void *luatos_os_malloc(u32 size);

/**
 * @brief 动态分配一块内存，并初始化为全0
 * 
 * @param size 希望分配到的字节数
 * @return void* 失败为NULL，否则返回首地址
 */
void *luatos_os_zalloc(u32 size);

/**
 * @brief 在内存的动态存储区中分配num个长度为size的连续空间，函数返回一个指向分配起始地址的指针；如果分配不成功，返回NULL。
 * 
 * @param num num个
 * @param size 长度为size
 * @return void* 失败为NULL，否则返回首地址
 */
void *luatos_os_calloc(u32 num, u32 size);
/**
 * @brief 改变已分配的动态内存大小
 * 
 * @note 先判断当前的指针是否有足够的连续空间，如果有，修改ptr指向的空间大小，并且将ptr返回；
 *      如果空间不够，先按照newsize指定的大小分配空间，将原有数据从头到尾拷贝到新分配的内存区域，
 *      而后释放原来ptr所指内存区域，同时返回新分配的内存区域的首地址。
 *      如果ptr为NULL，则realloc()和malloc()类似。分配一个newsize的内存块，返回一个指向该内存块的指针
 *      如果newsize为0，效果等同于free()
 * @param ptr 要改变内存大小的指针名
 * @param newsize 新的大小
 * @return void* 失败为NULL，否则返回首地址
 */
void *luatos_os_realloc(void *ptr, u32 newsize);

/**
 * @brief 释放已分配的动态内存
 * 
 * @param ptr 内存首地址
 */
void luatos_os_free(void *ptr);
#endif

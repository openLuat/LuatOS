/**
 * @file nw_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief 网络link相关API，如wifi连接/断开AP，蜂窝网络建立/去除PDP承载，以太网网线接入/断开，以及进入/退出飞行模式。
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */

#ifndef __NW_API_H__
#define __NW_API_H__

#if (LUATOS_USE_NW_API == 1)
/**
 * @brief 网络link在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 */
void luatos_nw_init(void);
#else

#endif
#endif
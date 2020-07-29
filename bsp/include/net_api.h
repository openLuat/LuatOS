/**
 * @file net_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief TCP/IP相关API
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __NET_API_H__
#define __NET_API_h__

#if (LUATOS_USE_NET_API == 1)
/**
 * @brief TCP/IP 在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 */
void luatos_net_init(void);
#else

#endif
#endif
/**
 * @file user_config.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief 用户的配置，会覆盖默认配置
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __USER_CONFIG_H__
#define __USER_CONFIG_H__
/**
 * @brief LUATOS_NO_STD_TYPE 没有对stdint相关的定义，打开后使用luatos定义的类型，如果关闭，必须加入对stdint相关的定义的头文件，比如stdint.h stddef.h
 */
#define LUATOS_NO_STD_TYPE
//include "stdint.h"
//include "stddef.h"
/**
 * @brief LUATOS_NO_NW_API 无网络link功能，打开后去除相关API
 */
//#define LUATOS_NO_NW_API
/*
* 
*/
/**
 * @brief LUATOS_NO_NET_API 无TCP/IP功能，打开后去除相关API
 */
//#define LUATOS_NO_NET_API
#endif
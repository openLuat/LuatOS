/**
 * @file nw_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief 网络link相关API，如wifi连接/断开AP，蜂窝网络建立/去除PDP承载，以太网启动/关闭，以及进入/退出飞行模式。
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */

#ifndef __NW_API_H__
#define __NW_API_H__
#include "api_config.h"
enum
{
    LUATOS_NW_TYPE_WIFI,
    LUATOS_NW_TYPE_GPRS,
    LUATOS_NW_TYPE_ETH,
    LUATOS_NW_TYPE_ALL,

    LUATOS_NW_ID_WIFI_MAC = 0,
    LUATOS_NW_ID_ETH_MAC,
    LUATOS_NW_ID_IMEI,
    LUATOS_NW_ID_ICCID,
    LUATOS_NW_ID_IMSI,
};


/**
 * @brief 网络link在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 */
void luatos_nw_init(void);

/**
 * @brief 启动一种网络link
 * 
 * @param type 网络link类型
 *              @arg @ref LUATOS_NW_TYPE_WIFI WIFI连接
 *              @arg @ref LUATOS_NW_TYPE_GPRS 蜂窝网络连接
 *              @arg @ref LUATOS_NW_TYPE_ETH  以太网网络连接
 * @param param link参数，根据不同的link类型参数不同
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_nw_start(u32 type, void *param);

/**
 * @brief 停止一种网络link
 * 
 * @param type 网络link类型
 *              @arg @ref LUATOS_NW_TYPE_WIFI WIFI连接
 *              @arg @ref LUATOS_NW_TYPE_GPRS 蜂窝网络连接
 *              @arg @ref LUATOS_NW_TYPE_ETH  以太网网络连接
 *              @arg @ref LUATOS_NW_TYPE_ALL  所有网络连接
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_nw_stop(u32 type);

/**
 * @brief 检测网络link状态
 * 
 * @param type 网络link类型
 *              @arg @ref LUATOS_NW_TYPE_WIFI WIFI连接
 *              @arg @ref LUATOS_NW_TYPE_GPRS 蜂窝网络连接
 *              @arg @ref LUATOS_NW_TYPE_ETH  以太网网络连接
 *              @arg @ref LUATOS_NW_TYPE_ALL  任意一种网络连接
 * @return LUATOS_STATUS 
 *              @arg @ref LUATOS_OK 准备就绪，可以使用
 *              @arg @ref 其他都是未准备好，不可使用
 */
LUATOS_STATUS luatos_nw_get_ready(u32 type);

/**
 * @brief 进出飞行模式
 * 
 * @param on_off 飞行模式标志
 *              @arg @ref 0 退出飞行模式
 *              @arg @ref 1 进入飞行模式
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_nw_fly_mode(u8 on_off);

/**
 * @brief 获取link相关的id信息
 * 
 * @param id id类型
 *              @arg @ref LUATOS_NW_ID_WIFI_MAC wifi的mac
 *              @arg @ref LUATOS_NW_ID_ETH_MAC 以太网控制的mac
 *              @arg @ref LUATOS_NW_ID_IMEI 蜂窝网络模块的imei
 *              @arg @ref LUATOS_NW_ID_ICCID 蜂窝网络SIM卡的iccid
 *              @arg @ref LUATOS_NW_ID_ICCID 蜂窝网络SIM卡的imsi
 * @param buf 输出数据区
 * @param len 输出数据区长度
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_nw_get_id(u8 id, char *buf, u8 len);

#endif
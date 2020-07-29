/**
 * @file api_config.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief API的默认配置
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */

#ifndef __API_CONFIG_H__
#define __API_CONFIG_H__
#include "user_config.h"

#if defined LUATOS_NO_STD_TYPE
typedef unsigned char       u8;
typedef char                s8;
typedef unsigned short      u16;
typedef short               s16;
typedef unsigned int        u32;
typedef int                 s32;
typedef unsigned long long  u64;
typedef long long           s64;
typedef unsigned char       bool;
typedef unsigned char       uint8_t;
typedef char                int8_t;
typedef unsigned short      uint16_t;
typedef short               int16_t;
typedef unsigned int        uint32_t;
typedef int                 int32_t;
typedef unsigned long long  uint64_t;
typedef long long           int64_t;

#define true                1
#define false               0
#ifndef TRUE
#define TRUE                (1==1)
#endif
#ifndef FALSE
#define FALSE               (1==0)
#endif
#ifndef NULL
#define NULL                (void *)0
#endif
#endif

typedef uint32_t        LUATOS_HANDLE;
typedef void			TASK_RET;
/** @struct pv_union_t
 * @brief 32bit数据集合
 * 
 */
typedef union
{
	void *p;
	char *pc8;
	uint8_t *pu8;
	uint16_t *pu16;
	uint32_t *pu32;
	uint32_t u32;
	uint8_t u8[4];
	uint16_t u16[2];
}pv_union_t;

/** @enum luatos_status
 * @brief luatos的通用返回值
 * 
 */
enum LUATOS_STATUS
{
    LUATOS_OK                       = 0,        /// < 成功
    LUATOS_ERROR_UNKNOW             = -100,     /// < 未知错误
    LUATOS_ERROR_NO_SUCH_ID         = -101,     /// < ID序号错误，比如未使用到的socket ID, 硬件ID等
	LUATOS_ERROR_PERMISSION_DENIED  = -102,     /// < 没有权限操作，一般为未初始化就使用了
	LUATOS_ERROR_PARAM_INVALID      = -103,     /// < 参数格式不正确
	LUATOS_ERROR_PARAM_OVERFLOW     = -104,     /// < 参数越界
	LUATOS_ERROR_DEVICE_BUSY        = -105,     /// < 设备正在使用
	LUATOS_ERROR_OPERATION_FAILED   = -106,     /// < 设备操作失败
	LUATOS_ERROR_BUFFER_FULL        = -107,     /// < 缓冲区满
	LUATOS_ERROR_NO_MEMORY          = -108,     /// < 内存不足，一般是动态分配失败
	LUATOS_ERROR_CMD_NOT_SUPPORT    = -109,     /// < 不支持的命令
	LUATOS_ERROR_NO_DATA            = -110,     /// < 数据输入为空
	LUATOS_ERROR_NO_FLASH           = -111,     /// < flash空间不足
	LUATOS_ERROR_NO_TIMER           = -112,     /// < 定时器不足
	LUATOS_ERROR_TIMEOUT            = -113,     /// < 超时
	LUATOS_ERROR_PROTOCL            = -114,     /// < 协议错误
};

/** @enum luatos_message_id
 * @brief luatos的通用message id，用于luatos_message_t.param1
 * 
 */
enum LUATOS_MESSAGE_ID
{
    LUATOS_MESSAGE_NETWORK_CHANGE,              /// < 网络状态发生变化, param2为link type，param3为新的状态
    LUATOS_MESSAGE_LINK_NOTIFY,                 /// < 网络准备就绪, param2为link type，param3 1就绪，0未就绪
	LUATOS_MESSAGE_TIMER_FINISH,				/// < 定时器时间到，param2为timer_param
    LUATOS_MESSAGE_USER_START = 0x10000000,
    LUATOS_MESSAGE_VAT = 0xffffffff,
}

/** @struct luatos_message_t
 * @brief sdk发给luatos的消息
 * 
 */
typedef struct
{
    u32 param1;                                  /// < 如果是SDK发给luatos的虚拟AT，则为0xffffffff
    u32 param2;                                  /// < 如果是SDK发给luatos的虚拟AT，则为char *，AT数据首地址
    u32 param3;                                  /// < 如果是SDK发给luatos的虚拟AT，AT数据长度
    u32 param4;
}luatos_message_t;

#include "os_api.h"
#include "hw_api.h"
#include "nw_api.h"
#include "net_api.h"
#endif
#ifndef __USER_CONFIG_H__
#define __USER_CONFIG_H__

/*
* LUATOS_NO_STD_TYPE 没有对stdint相关的定义，打开后使用luatos定义的类型，如果关闭，必须加入对stdint相关的定义的头文件，比如stdint.h stddef.h
*/
#define LUATOS_NO_STD_TYPE
//include "stdint.h"
//include "stddef.h"
/*
* LUATOS_NO_NW_API 无网络link功能，打开后去除相关API
*/
//#define LUATOS_NO_NW_API
/*
* LUATOS_NO_NET_API 无TCP/IP功能，打开后去除相关API
*/
//#define LUATOS_NO_NET_API

#endif
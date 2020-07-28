#ifndef __API_CONFIG_H__
#define __API_CONFIG_H__
#include "user_config.h"

#if !defined LUATOS_NO_NW_API
#define LUATOS_USE_NW_API 1
#else
#define LUATOS_USE_NW_API 0
#endif

#if !defined LUATOS_NO_NET_API
#define LUATOS_USE_NET_API 1
#else
#define LUATOS_USE_NET_API 0
#endif

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

#include "os_api.h"
#include "hw_api.h"
#include "nw_api.h"
#include "net_api.h"
#endif
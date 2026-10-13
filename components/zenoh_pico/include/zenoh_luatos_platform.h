/* SPDX-License-Identifier: MIT */
#ifndef ZENOH_LUATOS_PLATFORM_H
#define ZENOH_LUATOS_PLATFORM_H
#include <stdint.h>
#include <stddef.h>
#if Z_FEATURE_MULTI_THREAD != 0
#error "LuatOS port requires the single-owner executor"
#endif
/* 单调时钟单位微秒；socket 上下文只在所属工作任务中访问。 */
typedef uint64_t z_clock_t;
typedef uint64_t z_time_t;
typedef struct { void *context; } _z_sys_net_socket_t;
typedef struct { char host[256]; uint16_t port; } _z_sys_net_endpoint_t;
#endif

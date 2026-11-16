/* SPDX-License-Identifier: MIT
 * 版权和许可声明见 LICENSE。
 */
#ifndef LUAT_DHCPS_H
#define LUAT_DHCPS_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define LUAT_DHCPS_REPLY_SIZE 300
#define LUAT_DHCPS_REQUEST_MAX 1500
#define LUAT_DHCPS_DNS_MAX 2

typedef struct {
    uint32_t server_ip;
    uint32_t netmask;
    uint32_t pool_start;       /* 两端均为零：使用子网内所有可用地址。 */
    uint32_t pool_end;         /* 包含此端点；始终跳过 server_ip。 */
    unsigned client_count;
    uint32_t lease_seconds;
    uint32_t router;           /* 为零时省略选项 3（默认仅提供本地局域网）。 */
    uint32_t dns[LUAT_DHCPS_DNS_MAX]; /* 省略值为零的条目。 */
} luat_dhcps_config_t;

typedef struct {
    uint8_t mac[6];
    uint32_t ip;
    uint64_t expires;
} luat_dhcps_lease_t;

typedef struct {
    luat_dhcps_config_t config;
    luat_dhcps_lease_t *leases;
} luat_dhcps_t;

/** 填充仅提供本地局域网的配置，租期为 3600 秒。地址使用
 * 主机序整数（192.168.4.1 = 0xc0a80401），而非 in_addr 值。 */
void luat_dhcps_config_default(luat_dhcps_config_t *config, uint32_t ip,
                              uint32_t mask, unsigned clients);

/** 使用调用方拥有的租约存储初始化未运行的服务器。成功返回 0；
 * 配置或容量无效时返回 -1，并保持状态不变。
 * 配置会被复制；租约存储必须由该服务器独占，且生命周期覆盖服务器。 */
int luat_dhcps_init(luat_dhcps_t *server, const luat_dhcps_config_t *config,
                    luat_dhcps_lease_t *leases, size_t capacity);

/** 清除租约和配置。对已零初始化或已初始化的服务器可安全重复调用。
 * 调用方负责串行执行同一实例上的所有操作。 */
void luat_dhcps_deinit(luat_dhcps_t *server);

/** 处理一个 DHCP 负载。now 为单调时间，单位为秒。返回 300 字节或
 * 零（忽略或无需响应）。输入和输出不可重叠。输出缓冲区不足时，
 * 会在任何租约状态变化前拒绝处理。不进行内存分配或 I/O。 */
size_t luat_dhcps_reply(luat_dhcps_t *server, const uint8_t *input, size_t length,
                       uint8_t *output, size_t capacity, uint64_t now);

#ifdef __cplusplus
}
#endif
#endif

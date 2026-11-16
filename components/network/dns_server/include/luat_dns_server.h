/* SPDX-License-Identifier: MIT
 * Copyright (c) 2019-2026 openLuat & AirM2M
 */
#ifndef LUAT_DNS_SERVER_H
#define LUAT_DNS_SERVER_H
#include <stddef.h>
#include <stdint.h>
#include "lwip/ip_addr.h"

#ifdef __cplusplus
extern "C" {
#endif

struct netif;
struct luat_dns_server_lwip_port;
typedef struct luat_dns_server luat_dns_server_t;

typedef struct {
    struct netif *netif;
    ip_addr_t servers[2]; /* 仅支持 IPv4；第二个服务器地址可为 ANY（不重试）。 */
    uint16_t port;        /* 为 0 时使用端口 53。 */
} luat_dns_server_upstream_t;

/** 在 tcpip_thread 上调用。上游就绪时返回 0，否则返回负值。
 * 填入最新快照；后端不会保留返回的 netif 指针。
 * 回调不得重入 start/stop，也不得改变网络接口的生命周期。
 */
typedef int (*luat_dns_server_select_fn)(void *arg, luat_dns_server_upstream_t *out);
/** 提供密码学安全的随机字节；返回 0 表示成功，负值表示失败。 */
typedef int (*luat_dns_server_random_fn)(void *arg, uint8_t *bytes, size_t length);

typedef struct {
    struct netif *lan;
    luat_dns_server_select_fn select_upstream;
    void *upstream_arg;
    luat_dns_server_random_fn random;
    void *random_arg;
    const struct luat_dns_server_lwip_port *port;
    uint16_t listen_port; /* 为 0 时使用 53 */
    uint16_t udp_slots;   /* 为 0 时使用 16；最大 128 */
    uint16_t tcp_slots;   /* 为 0 时使用 4；最大 64 */
    uint16_t max_packet;  /* 为 0 时使用 4096；最小 17；UDP 查询和响应的长度上限 */
    uint32_t retry_ms;    /* 为 0 时使用 2000；使用第二个服务器重试一次 */
    uint32_t tcp_idle_ms; /* 为 0 时使用 15000 */
} luat_dns_server_config_t;

/** 专用的 lwIP IPv4 后端，并非原生套接字服务。
 * 所有 API 调用和回调都必须在 tcpip_thread 上执行，且不得处于原始输入/错误
 * 回调或 SDK 的 PCB/netif 链表遍历过程中。应先将命令投递到该线程。
 * 启动时复制 config 和移植层钩子。LAN 和回调参数以借用方式持有，直到停止：
 * 必须先停止服务，再移除或释放 LAN netif 或回调参数。
 * 返回 0 或负值的 lwIP 错误码。出错时 *out 为 NULL。
 */
int luat_dns_server_start(const luat_dns_server_config_t *config, luat_dns_server_t **out);
/** 解除所有 PCB 的关联，取消定时器，丢弃排队的数据并清空 *server。
 * 已投递但尚未处理完的任务仅保留停用的内部存储，直到队列排空；
 * 本调用返回后不会再使用外部指针或回调。重启时使用新句柄调用 start。
 * 传入 NULL 或值为 NULL 的句柄均安全。
 */
void luat_dns_server_stop(luat_dns_server_t **server);
/** 检查两个监听器是否均有效。遵循与 start/stop 相同的核心线程上下文约束。 */
int luat_dns_server_running(const luat_dns_server_t *server);

#ifdef __cplusplus
}
#endif
#endif

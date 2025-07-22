#ifndef LUAT_NETDRV_EVENT_H
#define LUAT_NETDRV_EVENT_H

#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"

// 事件, 用户可订阅
enum {
    LUAT_NETDRV_EVENT_TCP = 0x10, // TCP连接事件
    LUAT_NETDRV_EVENT_UDP = 0x20, // UDP连接事件
    LUAT_NETDRV_EVENT_DNS = 0x30, // DNS解析事件
    LUAT_NETDRV_EVENT_LINK = 0x40, // 网卡连接状态变化事件
};

// TCP连接事件标志
#define NETDRV_EVENT_TCP_FLAG_CREATE (1 << 0) // TCP连接创建
#define NETDRV_EVENT_TCP_FLAG_CLOSE (1 << 1) // TCP连接关闭
#define NETDRV_EVENT_TCP_FLAG_CONNECT (1 << 2) // TCP连接成功
#define NETDRV_EVENT_TCP_FLAG_DISCONNECT (1 << 3) // TCP连接断开
#define NETDRV_EVENT_TCP_FLAG_ERROR (1 << 4) // TCP的其他错误

typedef struct netdrv_tcp_evt {
    uint8_t id; // 网络适配器ID
    uint8_t flags; // 事件标志, 标识
    uint16_t re; // 保留字段, 目前未使用
    ip_addr_t local_ip; // 本地IP地址
    ip_addr_t remote_ip; // 远程IP地址
    uint16_t local_port; // 本地端口
    uint16_t remote_port; // 远程端口
    void* userdata; // 用户数据, 可用于回调时传递额外信息
}netdrv_tcp_evt_t;

typedef void (*luat_netdrv_tcp_evt_cb)(netdrv_tcp_evt_t* evt, void* userdata);


typedef struct netdrv_tcpevt_reg {
    uint8_t id; // 网络适配器ID
    uint8_t flags; // 事件标志, 标识
    luat_netdrv_tcp_evt_cb cb; // TCP事件回调函数
    void* userdata; // 用户数据, 可用于回调时传递额外信息
}netdrv_tcpevt_reg_t;

void luat_netdrv_fire_tcp_event(netdrv_tcp_evt_t* evt);

void luat_netdrv_register_tcp_event_cb(uint8_t id, uint8_t flags, luat_netdrv_tcp_evt_cb cb, void* userdata);

#endif

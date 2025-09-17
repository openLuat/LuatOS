#ifndef LUAT_NETDRV_EVENT_H
#define LUAT_NETDRV_EVENT_H

#include "lwip/pbuf.h"
#include "lwip/ip_addr.h"
#include "luat_ulwip.h"

// 事件, 用户可订阅
enum {
    LUAT_NETDRV_EVENT_TCP = 0x10, // TCP连接事件
    LUAT_NETDRV_EVENT_UDP = 0x20, // UDP连接事件
    LUAT_NETDRV_EVENT_DNS = 0x30, // DNS解析事件
    LUAT_NETDRV_EVENT_LINK = 0x40, // 网卡连接状态变化事件
};


typedef struct netdrv_tcp_evt {
    uint8_t id; // 网络适配器ID
    uint8_t flags; // 事件标志, 标识
    uint8_t proto; // 协议类型, 1=TCP, 2=UDP, 3=HTTP, 4=MQTT, 5=WEBSOCKET, 6=FTP
    uint8_t re; // 保留字段, 目前未使用
    ip_addr_t local_ip; // 本地IP地址
    ip_addr_t remote_ip; // 远程IP地址
    ip_addr_t online_ip; // 连接上的IP地址, DNS事件无效
    uint16_t local_port; // 本地端口
    uint16_t remote_port; // 远程端口
    char domain_name[256]; // 解析的域名, DNS事件有效
    void* userdata; // 用户数据, 可用于回调时传递额外信息
}netdrv_tcp_evt_t;

typedef void (*luat_netdrv_tcp_evt_cb)(netdrv_tcp_evt_t* evt, void* userdata);


typedef struct netdrv_tcpevt_reg {
    uint8_t id; // 网络适配器ID
    uint8_t flags; // 事件标志, 标识
    luat_netdrv_tcp_evt_cb cb; // TCP事件回调函数
    void* userdata; // 用户数据, 可用于回调时传递额外信息
}netdrv_tcpevt_reg_t;

void luat_netdrv_register_socket_event_cb(uint8_t id, uint32_t flags, luat_netdrv_tcp_evt_cb cb, void* userdata);

void luat_netdrv_fire_socket_event_netctrl(uint32_t event_id, network_ctrl_t* ctrl, uint8_t proto);

void luat_netdrv_send_ip_event(luat_netdrv_t* drv, uint8_t ready);

void luat_netdrv_set_link_updown(luat_netdrv_t* drv, uint8_t updown);

#endif

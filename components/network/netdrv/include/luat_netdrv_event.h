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


// 通道宏 (ch = channel, 统一表示包在协议栈中的环节)
// 同一通道既可作 send_raw 的 target, 也可作 pkg_input 的 src / pkg_output 的 dst / fire_pkg_event 的 layer
#define LUAT_NETDRV_CH_HW       0x10  // 物理硬件 (RX 自 HW = FROM_HW; TX 至 HW = TO_HW)
#define LUAT_NETDRV_CH_LWIP     0x20  // LWIP 协议栈 (TX 至 LWIP = TO_LWIP; 未来 FROM_LWIP)
#define LUAT_NETDRV_CH_NAPT     0x30  // NAPT 层 (TX 至 NAPT = TO_NAPT; 未来 FROM_NAPT)

// 用户层 API 用的 event 类型常量 (netdrv.on 第二参数 / reg_netdrv[] 的 EVT_* 常量值)
// 与上面的 enum { TCP/UDP/DNS/LINK } 是不同的概念: 这里指"用户订阅哪种事件类型",
// enum 指"具体哪一种 socket 状态" (内部事件细分), 不混用.
#define LUAT_NETDRV_EVT_OFF      0     // 关闭 socket 事件 (deregister, 仅 EVT_SOCKET 路径使用)
#define LUAT_NETDRV_EVT_SOCKET   1     // 旧 socket 连接状态事件 (已细分到 TCP/UDP/DNS/LINK)
#define LUAT_NETDRV_EVT_PKG      2     // 数据包事件 (HW/LWIP/NAPT 各通道通用, 通过 opts.layer 选通道)

// 数据包事件结构 + 回调类型
typedef struct luat_netdrv_pkg_evt {
    uint8_t  id;
    uint8_t  event;
    uint8_t* buff;
    uint16_t len;
} luat_netdrv_pkg_evt_t;

typedef void (*luat_netdrv_pkg_evt_cb)(luat_netdrv_pkg_evt_t* evt, void* userdata);


// Socket 事件注册表项 (TCP/UDP/DNS/LINK 等 socket 状态事件)
// 与 pkg 事件完全独立,各自走自己的数组 (避免一个 id 同时订阅两种事件时互相污染字段)
typedef struct netdrv_socket_evt_reg {
    uint8_t id;             // 网络适配器ID
    uint8_t flags;          // 事件标志 bitmask, 标识订阅的子事件 (TCP/UDP/DNS/LINK)
    luat_netdrv_tcp_evt_cb cb; // TCP事件回调函数 (NULL = 未订阅)
    void* socket_userdata;  // socket 事件的用户数据
} netdrv_socket_evt_reg_t;

// PKG 事件注册表项 (HW/LWIP/NAPT 各通道数据包事件)
// 独立于 socket 事件表, 字段专属 PKG 语义.
// 字段顺序对齐 netdrv_socket_evt_reg_t: id -> 订阅配置 -> cb -> userdata.
typedef struct netdrv_pkg_evt_reg {
    uint8_t id;             // 网络适配器ID
    uint8_t pkg_layers;     // 订阅的 layer bitmask (LUAT_NETDRV_CH_HW/LWIP/NAPT), 0 = 未指定
    luat_netdrv_pkg_evt_cb cb; // 数据包事件回调函数 (NULL = 未订阅)
    void* pkg_userdata;     // 数据包事件的用户数据
} netdrv_pkg_evt_reg_t;

void luat_netdrv_register_socket_event_cb(uint8_t id, uint32_t flags, luat_netdrv_tcp_evt_cb cb, void* userdata);

void luat_netdrv_fire_socket_event_netctrl(uint32_t event_id, network_ctrl_t* ctrl, uint8_t proto);

void luat_netdrv_send_ip_event(luat_netdrv_t* drv, uint8_t ready);

void luat_netdrv_set_link_updown(luat_netdrv_t* drv, uint8_t updown);

// 三个公开函数声明
void luat_netdrv_register_pkg_event_cb(uint8_t id, luat_netdrv_pkg_evt_cb cb, void* userdata);
int  luat_netdrv_has_pkg_cb(uint8_t id);
void luat_netdrv_fire_pkg_event(uint8_t id, uint8_t event, uint8_t* buff, uint16_t len);

// 设置数据包事件订阅的 layer bitmask
// (与 register_pkg_event_cb 配对使用, register 时默认 layer=LUAT_NETDRV_CH_HW)
void luat_netdrv_set_pkg_layer(uint8_t id, uint8_t layer_mask);

#endif

/**
 * @file net_api.h
 * @author lisiqi (alienwalker@sina.com)
 * @brief TCP/IP相关API，采用回调函数方式，需要完善主机应用
 * @version 0.1
 * @date 2020-07-29
 * 
 * @copyright Copyright (c) 2020
 * 
 */
#ifndef __NET_API_H__
#define __NET_API_h__
#include "api_config.h"

typedef int SOCKET;

enum IP_ADDR_TYPE {
    /** IPv4 */
    IPADDR_TYPE_V4 =   0U,
    /** IPv6 */
    IPADDR_TYPE_V6 =   6U,
    /** IPv4+IPv6 ("dual-stack") */
    IPADDR_TYPE_ANY = 46U,
    /** 不使用 */
    IPADDR_TYPE_NONE = 255U,
};

struct ip4_addr {
    u32 addr;
};
typedef struct ip4_addr ip4_addr_t;

struct ip6_addr {
    u32 addr[4];
    u8  zone;
};
typedef struct ip6_addr ip6_addr_t;

typedef struct ip_addr {
    union {
        ip6_addr_t ip6;
        ip4_addr_t ip4;
    } u_addr;
    /** @ref lwip_ip_addr_type */
    u8 type;
} ip_addr_t;

typedef struct net_callback_fun {
    LUATOS_STATUS (*connect_cb)(SOCKET socket_id, int result);      /// < tcp连接结果
    LUATOS_STATUS (*send_cb)(SOCKET socket_id, int result);         /// < tcp发送结果
    LUATOS_STATUS (*recv_cb)(SOCKET socket_id, u32 result);         /// < tcp接收到数据
    LUATOS_STATUS (*close_cb)(SOCKET socket_id, int result);        /// < tcp客户端断开连接
    LUATOS_STATUS (*error_cb)(SOCKET socket_id);                    /// < tcp链接异常
};



/**
 * @brief TCP/IP 在luatos中的适配相关初始化工作，真正的初始化工作应该在启动luatos前就完成了
 * 
 * @param funs 需要注册的回调函数
 */
void luatos_net_init(net_callback_fun funs);

/**
 * @brief 获取当前用的DNS服务器
 * 
 * @param [OUT]dns_ip DNS服务器IP地址，注意如果实际有的服务器比希望获取的少，则多余地址填IPADDR_TYPE_NONE
 * @param ip_num 期望获取的DNS服务器数量
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_net_get_dns_server(ip_addr_t *dns_ip, u8 ip_num);

/**
 * @brief 设置DNS服务器
 * 
 * @param dns_ip DNS服务器IP地址
 * @param ip_num DNS服务器数量
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_net_set_dns_server(ip_addr_t *dns_ip, u8 ip_num);

/**
 * @brief 获取主机IP，注意有些SDK可以直接用域名连接，则本API可以直接返回成功
 * 
 * @param url 主机域名或者IP
 * @param [out]ip 主机IP 
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_net_gethostbyname(const char *url, ip_addr_t *ip);

/**
 * @brief 创建一个socket
 * 
 * @param type   使用的link类型
 *              @arg @ref LUATOS_NW_TYPE_WIFI WIFI连接
 *              @arg @ref LUATOS_NW_TYPE_GPRS 蜂窝网络连接
 *              @arg @ref LUATOS_NW_TYPE_ETH  以太网网络连接
 *              @arg @ref LUATOS_NW_TYPE_ALL  任意一种网络连接
 * @param is_udp 是否UDP 1是，0否
 * @param is_tls 是否加密 1是，0否
 * @param server_crt 服务器证书
 * @param client_crt 客户端证书 
 * @param client_key 客户端证书密码，如果没有客户端证书，那么是DTLS的KEY
 * @param key_len 密码或者key长度
 * @return SOCKET 
 *              @arg @ref >= 0 socket id
 *              @arg @ref < 0 LUATOS_STATUS
 */
SOCKET luatos_net_create_socket(u32 type, u8 is_udp, u8 is_tls, 
        void *server_crt, void *client_crt, void *client_key, u32 key_len);

/**
 * @brief 非阻塞启动一个socket connect
 * 
 * @param socket_id socket id
 * @param url 主机域名
 * @param ip 主机IP，与主机域名必须有一个
 * @param port 主机端口
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_net_connect(SOCKET socket_id, const char *url, ip_addr_t *ip, u16 port);

/**
 * @brief 非阻塞发送数据
 * 
 * @param socket_id socket id
 * @param data 发送的数据首地址
 * @param len 发送长度
 * @param flags 发送附加标识，一般用于NBIOT
 * @param need_wait_ack 对于TCP，是否在所有数据包都ack后回调，以最后一次设置为准，1是，0否
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_net_send(SOCKET socket_id, const void *data, u32 len, u32 flags, u8 need_wait_ack);

/**
 * @brief 非阻塞读取数据
 * 
 * @param socket_id socket id
 * @param [OUT]buf 数据缓冲区
 * @param buf_len 数据缓冲区长度
 * @param read_len 实际读取的长度
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_net_recv(SOCKET socket_id, void *buf, u32 buf_len, u32 *read_len);

/**
 * @brief 非阻塞关闭一个socket连接，注意为了应用层统一处理，即使已经关闭了，也要再回调一次close_cb
 * 
 * @param socket_id socket id
 * @return LUATOS_STATUS 
 */
LUATOS_STATUS luatos_net_close(SOCKET socket_id);
#endif


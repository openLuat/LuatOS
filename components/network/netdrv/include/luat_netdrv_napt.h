#ifndef LUAT_NETDRV_NAPT_H
#define LUAT_NETDRV_NAPT_H

#include "lwip/pbuf.h"

// #define IP_NAPT_TIMEOUT_MS_TCP (30*60*1000)
#define IP_NAPT_TIMEOUT_MS_TCP_DISCON (20*1000)

typedef struct luat_netdrv_napt_icmp
{
    uint8_t  is_vaild;
    uint8_t adapter_id;
    uint16_t inet_id;
    uint16_t wnet_id;
    uint32_t inet_ip;
    uint32_t wnet_ip;
    uint8_t  inet_mac[6];
    uint64_t tm_ms; // 最后通信时间
}luat_netdrv_napt_icmp_t;

typedef struct luat_netdrv_napt_tcpudp
{
    uint8_t  is_vaild;
    uint8_t adapter_id;
    uint32_t inet_ip;
    uint16_t inet_port;
    uint32_t wnet_ip;
    uint16_t wnet_port;
    uint16_t wnet_local_port;
    uint8_t  inet_mac[6];
    uint64_t tm_ms; // 最后通信时间

    // TCP状态记录
    unsigned int fin1 : 1;
    unsigned int fin2 : 1;
    unsigned int finack1 : 1;
    unsigned int finack2 : 1;
    unsigned int synack : 1;
    unsigned int rst : 1;
}luat_netdrv_napt_tcpudp_t;

typedef struct napt_ctx
{
    luat_netdrv_t* net;
    uint8_t* buff;
    size_t len;
    struct eth_hdr* eth;
    struct ip_hdr* iphdr;
    int is_wnet;
}napt_ctx_t;

struct luat_netdrv_napt_llist;
typedef struct luat_netdrv_napt_llist
{
    struct luat_netdrv_napt_llist* next;
    luat_netdrv_napt_tcpudp_t item;
}luat_netdrv_napt_llist_t;

typedef struct luat_netdrv_napt_ctx{
    size_t clean_tm;
    size_t item_max;
    size_t item_last;
    // uint32_t port_used[1024];
    luat_netdrv_napt_tcpudp_t items[2048];
}luat_netdrv_napt_ctx_t;

int luat_napt_icmp_handle(napt_ctx_t* ctx);
int luat_napt_tcp_handle(napt_ctx_t* ctx);
int luat_napt_udp_handle(napt_ctx_t* ctx);

int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len);

int luat_netdrv_napt_pkg_input_pbuf(int id, struct pbuf* p);

// 维护影响关系
int luat_netdrv_napt_tcp_wan2lan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping);
int luat_netdrv_napt_tcp_lan2wan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping);

#endif

#ifndef LUAT_NETDRV_NAPT_H
#define LUAT_NETDRV_NAPT_H

#include "lwip/pbuf.h"

// 返回值定义（对齐LWIP期望：0=交给LWIP继续，非0=已消费）
#define NAPT_RET_SKIP         0    // 跳过处理，让LWIP继续（0）
#define NAPT_RET_OK           1    // 已处理并转发（1）
#define NAPT_RET_NO_MAPPING  -1    // 未找到映射关系
#define NAPT_RET_NO_MEMORY   -2    // 内存不足
#define NAPT_RET_LOCK_FAIL   -3    // 加锁失败
#define NAPT_RET_INVALID_CTX -4    // NAPT上下文无效

// 哈希表大小（用于加速查找）
// 根据压力测试结果优化：适应高并发场景，负载因子0.5-0.6
#ifndef NAPT_HASH_TABLE_SIZE
#if defined(TYPE_EC718HM)
#define NAPT_HASH_TABLE_SIZE 16384  // 8K映射，负载因子0.5 (~131KB，两表共计)
#elif defined(TYPE_EC718PM)
#define NAPT_HASH_TABLE_SIZE 8192   // 4K映射，负载因子0.5 (~65KB)
#else
#define NAPT_HASH_TABLE_SIZE 4096   // 2K映射，负载因子0.5 (~33KB)
#endif
#endif
#define NAPT_HASH_INVALID_INDEX 0xFFFF
#define NAPT_HASH_MAX_PROBE 96      // 提高到96，应对更高的冲突率

// #define IP_NAPT_TIMEOUT_MS_TCP (30*60*1000)
#define IP_NAPT_TIMEOUT_MS_TCP_DISCON (20*1000)
#ifndef NAPT_TCP_MAP_ITEM_MAX
#if defined(TYPE_EC718HM)
#define NAPT_TCP_MAP_ITEM_MAX (8*1024)
#elif defined(TYPE_EC718PM)
#define NAPT_TCP_MAP_ITEM_MAX (4*1024)
#else
#define NAPT_TCP_MAP_ITEM_MAX (2*1024)
#endif
#endif

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
    luat_netdrv_t* drv_gw;
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

// 哈希表项，用于加速查找（纯线性探测，无链表）
typedef struct {
    uint16_t item_index;  // 映射项在items数组中的索引，NAPT_HASH_INVALID_INDEX表示空槽
} napt_hash_entry_t;

typedef struct luat_netdrv_napt_ctx{
    uint32_t ip_tp;
    size_t clean_tm;
    size_t item_max;
    size_t item_last;
    luat_netdrv_napt_tcpudp_t items[NAPT_TCP_MAP_ITEM_MAX];
    luat_rtos_mutex_t lock;
    uint32_t *port_used;
    // 哈希表用于加速查找（WAN->LAN方向）
    napt_hash_entry_t *hash_table_wan2lan;  // 按(wnet_ip, wnet_port, wnet_local_port)索引
    // 哈希表用于加速查找（LAN->WAN方向）
    napt_hash_entry_t *hash_table_lan2wan;  // 按(inet_ip, inet_port, wnet_ip, wnet_port)索引
}luat_netdrv_napt_ctx_t;

int luat_napt_icmp_handle(napt_ctx_t* ctx);
int luat_napt_tcp_handle(napt_ctx_t* ctx);
int luat_napt_udp_handle(napt_ctx_t* ctx);

void luat_netdrv_napt_tcp_cleanup(void);
void luat_netdrv_napt_udp_cleanup(void);

int luat_netdrv_napt_pkg_input(int id, uint8_t* buff, size_t len);

int luat_netdrv_napt_pkg_input_pbuf(int id, struct pbuf* p);

// 维护影响关系
int luat_netdrv_napt_tcp_wan2lan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping, luat_netdrv_napt_ctx_t *napt_ctx);
int luat_netdrv_napt_tcp_lan2wan(napt_ctx_t* ctx, luat_netdrv_napt_tcpudp_t* mapping, luat_netdrv_napt_ctx_t *napt_ctx);

void luat_netdrv_napt_enable(int adapter_id);
void luat_netdrv_napt_disable(void);

#endif

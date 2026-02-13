#ifndef LUAT_NETDRV_NAPT_H
#define LUAT_NETDRV_NAPT_H

#include "lwip/pbuf.h"
#include "lwip/def.h"
#include "lwip/ip.h"
#include "lwip/etharp.h"
#include "luat_netdrv.h"
#include <string.h>

// NAPT公共类型别名
#ifndef NAPT_TYPE_ALIASES
#define NAPT_TYPE_ALIASES
#define u32 uint32_t
#define u16 uint16_t
#define u8  uint8_t
#endif

#define NAPT_ETH_HDR_LEN sizeof(struct ethhdr)

// NAPT公共增量校验和更新函数
static inline uint16_t napt_chksum_replace_u16(uint16_t sum_net, uint16_t old_net, uint16_t new_net)
{
    uint32_t acc = (~lwip_ntohs(sum_net) & 0xFFFFU) + (~lwip_ntohs(old_net) & 0xFFFFU) + lwip_ntohs(new_net);
    acc = (acc >> 16) + (acc & 0xFFFFU);
    acc += (acc >> 16);
    return lwip_htons((uint16_t)(~acc));
}

static inline uint16_t napt_chksum_replace_u32(uint16_t sum_net, uint32_t old_net, uint32_t new_net)
{
    const uint16_t *old16 = (const uint16_t *)&old_net;
    const uint16_t *new16 = (const uint16_t *)&new_net;
    sum_net = napt_chksum_replace_u16(sum_net, old16[0], new16[0]);
    sum_net = napt_chksum_replace_u16(sum_net, old16[1], new16[1]);
    return sum_net;
}

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
#define NAPT_HASH_TABLE_SIZE 16384  // 8K映射，单ctx双表约64KB，TCP+UDP约128KB
#elif defined(TYPE_EC718PM)
#define NAPT_HASH_TABLE_SIZE 8192   // 4K映射，单ctx双表约32KB，TCP+UDP约64KB
#else
#define NAPT_HASH_TABLE_SIZE 16384  // 默认提高到16K，满足“增加约128KB内存”目标
#endif
#endif
#define NAPT_HASH_INVALID_INDEX 0xFFFF
#define NAPT_HASH_MAX_PROBE 256     // 提高到256，缓解线性探测冲突深度

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

// NAPT公共输出路由函数: WAN→LAN 方向
static inline int napt_output_to_lan(napt_ctx_t* ctx,
                                     luat_netdrv_napt_tcpudp_t* mapping,
                                     struct ip_hdr* ip_hdr,
                                     uint8_t* buff)
{
    if (ctx->eth) {
        memcpy(ctx->eth->src.addr, ctx->net->netif->hwaddr, 6);
        memcpy(ctx->eth->dest.addr, mapping->inet_mac, 6);
    }
    luat_netdrv_t* dst = luat_netdrv_get(mapping->adapter_id);
    if (dst == NULL || !dst->dataout) {
        return 1;
    }
    if (ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
        dst->dataout(dst, dst->userdata, ctx->eth, ctx->len);
    }
    else if (!ctx->eth && dst->netif->flags & NETIF_FLAG_ETHARP) {
        memcpy(buff, mapping->inet_mac, 6);
        memcpy(buff + 6, dst->netif->hwaddr, 6);
        memcpy(buff + 12, "\x08\x00", 2);
        memcpy(buff + 14, ip_hdr, ctx->len);
        dst->dataout(dst, dst->userdata, buff, ctx->len + 14);
    }
    else {
        dst->dataout(dst, dst->userdata, ip_hdr, ctx->len);
    }
    return 1;
}

// NAPT公共输出路由函数: LAN→WAN 方向
static inline int napt_output_to_wan(napt_ctx_t* ctx,
                                     luat_netdrv_t* gw,
                                     struct ip_hdr* ip_hdr)
{
    if (!gw || !gw->dataout || !gw->netif) {
        return 1;
    }
    if (gw->netif->flags & NETIF_FLAG_ETHARP) {
        if (ctx->eth) {
            memcpy(ctx->eth->dest.addr, gw->gw_mac, 6);
            gw->dataout(gw, gw->userdata, ctx->eth, ctx->len);
        }
        else {
            return 0; // 网关netdrv是ETH,源网卡不是ETH, 当前不支持
        }
    }
    else {
        if (ctx->eth) {
            gw->dataout(gw, gw->userdata, ip_hdr, ctx->len - 14);
        }
        else {
            gw->dataout(gw, gw->userdata, ip_hdr, ctx->len);
        }
    }
    return 1;
}

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

// 初始化NAPT上下文（如有需要）
int luat_netdrv_napt_init_contexts(void);

void luat_netdrv_napt_enable(int adapter_id);
void luat_netdrv_napt_disable(void);

#endif

#ifndef __NET_LWIP_H__
#define __NET_LWIP_H__

#include "luat_base.h"
#include "dns_def.h"
#include "luat_network_adapter.h"
#include "dhcp_def.h"

struct netif;

/*
 * netdrv IPv6 功能开关(与 luat_netdrv.h 保持同一份语义):
 *   - 未定义 : 关闭
 *   - 已定义 : 启用(惯例写 1, 判据只看是否定义)
 * 本文件可能不经由 luat_netdrv.h 被包含, 因此这里不再自行兜底定义;
 * 开启该能力的唯一位置是 BSP 的 luat_conf_bsp.h.
 */

#ifdef LWIP_NUM_SOCKETS
#if LWIP_NUM_SOCKETS > 16
#define MAX_SOCK_NUM 16
#else
#define MAX_SOCK_NUM LWIP_NUM_SOCKETS
#endif
#else
#define MAX_SOCK_NUM 8
#endif

typedef struct
{
	llist_head node;
	uint64_t tag;	//考虑到socket复用的问题，必须有tag来做比对
	luat_ip_addr_t ip;
	uint8_t *data;
	uint32_t read_pos;
	uint16_t len;
	uint16_t port;
	uint8_t is_sending;
	uint8_t is_need_ack;
}socket_data_t;

typedef struct
{
	uint64_t socket_tag;
	dns_client_t *dns_client[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	socket_ctrl_t socket[MAX_SOCK_NUM];
	ip_addr_t ec618_ipv6;
	struct netif *lwip_netif[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	CBFuncEx_t socket_cb;
	void *user_data;
	void *task_handle;
	uint32_t socket_busy;
	uint32_t socket_connect;
	uint8_t netif_network_ready[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	// DNS相关
	struct udp_pcb *dns_udp[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	HANDLE dns_timer[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	uint8_t next_socket_index;
	dhcp_client_info_t *dhcpc[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	// IPv6前缀长度, 按适配器记录, 0表示未设置(默认64); lwip的ip6_addr_t不保存前缀长度
	uint8_t ip6_prefix[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
}net_lwip2_ctrl_struct;


void net_lwip2_register_adapter(uint8_t adapter_index);
void net_lwip2_init(uint8_t adapter_index);
int net_lwip_check_all_ack(int socket_id);
void net_lwip2_set_netif(uint8_t adapter_index, struct netif *netif);
struct netif * net_lwip2_get_netif(uint8_t adapter_index);
/*
 * 如果是需要使用静态IP，则需要先设置好IP，再设置linkup
 * 如果之前设置了静态IP，现在想用动态IP，需要先删掉静态IP，再linkup
 * 一旦linkup，如果没有使用静态IP，就会启动DHCP
 * 不能用过DHCP获取IP的网卡，必须先设置静态IP！！！！！！，比如GPRS
 */
void net_lwip2_set_link_state(uint8_t adapter_index, uint8_t updown);

void net_lwip2_set_dhcp_client(uint8_t adapter_index, dhcp_client_info_t *dhcp_client);

/*
 * ==== IPv6 (2026.01 新增, 供 netdrv.ipv6 使用) ====
 *
 * 说明:
 *  - 这些函数只在 LWIP_IPV6 != 0 且有实现时才有意义; 未开启 LWIP_IPV6 的构建里,
 *    net_lwip2_ipv6_supported() 返回 0, 其余函数返回 -1, 调用方可据此降级.
 *  - 地址索引(slot)约定: slot 0 始终预留给链路本地地址(fe80::/10),
 *    手动/静态配置的全局地址优先使用第一个空闲的非 0 槽位.
 */

/** 当前构建是否支持 IPv6 */
uint8_t net_lwip2_ipv6_supported(void);

/** 读取指定适配器当前生效的 IPv6 地址信息(优先 PREFERRED, 退而取 VALID) */
int net_lwip2_ipv6_addr_info(uint8_t adapter_index, luat_ip_addr_t *addr, uint8_t *prefix);

/** 单独读取链路本地地址(槽 0), 与"全局优先"的读取区分开 */
int net_lwip2_ipv6_linklocal_addr_info(uint8_t adapter_index, luat_ip_addr_t *addr, uint8_t *prefix);

/** 为指定适配器生成链路本地地址(依据 netif->hwaddr, 幂等) */
int net_lwip2_ipv6_create_linklocal(uint8_t adapter_index);

/** 设置静态 IPv6 地址 + 前缀长度, 内部投递到 tcpip 线程执行 */
int net_lwip2_set_static_ip6_info(uint8_t adapter_index, luat_ip_addr_t *ipv6, uint8_t prefix_len);

/** 判断指定适配器是否有有效的(至少 VALID)IPv6 地址 */
int net_lwip2_ipv6_is_ready(uint8_t adapter_index);

/* ARP 1000ms 周期定时器及其所有公共 API 已被完全移除.
 * 历史实现见 commit b4de806e0. */

#endif

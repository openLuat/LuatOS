#ifndef __NET_LWIP_H__
#define __NET_LWIP_H__

#include "luat_base.h"
#include "dns_def.h"
#include "luat_network_adapter.h"
#include "dhcp_def.h"

struct netif;

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
	HANDLE arp_timer;
	/* ARP 1000ms 定时器低功耗按需启停 + 显式休眠路径状态 */
	uint8_t arp_timer_running;        /* 当前 1000ms 定时器是否在跑 (0/1) */
	uint8_t arp_timer_sleep_saved;    /* 进 sleep 前的 running 快照 */
	uint8_t arp_timer_in_sleep;       /* 已下发 sleep_prepare、尚未 wakeup_resume */
	uint8_t gw_mac_valid[NW_ADAPTER_INDEX_LWIP_NETIF_QTY]; /* 每个 adapter 的网关 MAC 解析状态 */
	dhcp_client_info_t *dhcpc[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
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

#ifdef LUAT_USE_NETDRV_LWIP_ARP
/* 进 sleep 前调用：强制停止 ARP 1000ms 定时器并保存运行态。
 * 定义 LUAT_NETDRV_ARP_TIMER_ALWAYS_ON 时为 no-op，上层 PM 代码可无差别调用。 */
void net_lwip2_arp_timer_sleep_prepare(void);

/* 唤醒后调用：按 saved 或当前 need 重新评估并恢复。
 * 定义 LUAT_NETDRV_ARP_TIMER_ALWAYS_ON 时为 no-op。 */
void net_lwip2_arp_timer_wakeup_resume(void);

/* 按需启停（供 ARP 解析回调使用，内部转事件投递）。
 * 定义 LUAT_NETDRV_ARP_TIMER_ALWAYS_ON 时为 no-op。 */
void net_lwip2_arp_timer_request_start(uint8_t adapter_index);
void net_lwip2_arp_timer_request_stop(uint8_t adapter_index);

/* 由 ARP 解析路径通知 adapter 层：网关 MAC 是否已解析。
 * 第一参数传入对应的 netif，由 adapter 层自行反查 adapter_index，避免依赖 netif->state 类型。
 * 定义 LUAT_NETDRV_ARP_TIMER_ALWAYS_ON 时为 no-op。 */
void net_lwip2_notify_gw_mac_state(struct netif *netif, uint8_t valid);
#endif

#endif

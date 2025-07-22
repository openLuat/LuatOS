#ifndef __NET_LWIP_H__
#define __NET_LWIP_H__

#include "luat_base.h"
#include "dns_def.h"
#include "luat_network_adapter.h"
#include "dhcp_def.h"

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

#endif

#ifndef __NET_LWIP_H__
#define __NET_LWIP_H__

#define MAX_SOCK_NUM 8
#include "luat_base.h"
#include "dns_def.h"
#include "luat_network_adapter.h"

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
	dns_client_t dns_client;
	socket_ctrl_t socket[MAX_SOCK_NUM];
	ip_addr_t ec618_ipv6;
	struct netif *lwip_netif[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	CBFuncEx_t socket_cb;
	void *user_data;
	void *task_handle;
	struct udp_pcb *dns_udp;
	uint32_t socket_busy;
	uint32_t socket_connect;
	HANDLE dns_timer;//dhcp_fine_tmr,dhcp6_tmr
	uint8_t dns_adapter_index;
	uint8_t netif_network_ready[NW_ADAPTER_INDEX_LWIP_NETIF_QTY];
	// uint8_t common_timer_active;
//	uint8_t fast_sleep_enable;
	uint8_t next_socket_index;
}net_lwip_ctrl_struct;


void net_lwip_register_adapter(uint8_t adapter_index);
void net_lwip_init(uint8_t adapter_index);
int net_lwip_check_all_ack(int socket_id);
void net_lwip_set_netif(uint8_t adapter_index, struct netif *netif);
struct netif * net_lwip_get_netif(uint8_t adapter_index);
// void net_lwip_input_packets(struct netif *netif, struct pbuf *p);
/*
 * 如果是需要使用静态IP，则需要先设置好IP，再设置linkup
 * 如果之前设置了静态IP，现在想用动态IP，需要先删掉静态IP，再linkup
 * 一旦linkup，如果没有使用静态IP，就会启动DHCP
 * 不能用过DHCP获取IP的网卡，必须先设置静态IP！！！！！！，比如GPRS
 */
void net_lwip_set_link_state(uint8_t adapter_index, uint8_t updown);

/*
 * GPRS网卡专用，user_data填adapter_index，不从network_adapter走
 */
int net_lwip_set_static_ip(ip_addr_t *ip, ip_addr_t *submask, ip_addr_t *gateway, ip_addr_t *ipv6, void *user_data);
#endif

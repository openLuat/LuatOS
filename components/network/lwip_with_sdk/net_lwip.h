#ifdef __USE_SDK_LWIP__
#ifndef __NET_LWIP_H__
#define __NET_LWIP_H__
#include "bsp_common.h"
enum
{
	EV_LWIP_EVENT_START = USER_EVENT_ID_START + 0x2000000,
	EV_LWIP_SOCKET_TX,
	EV_LWIP_NETIF_INPUT,
	EV_LWIP_RUN_USER_API,
//	EV_LWIP_TCP_TIMER,
//	EV_LWIP_COMMON_TIMER,
	EV_LWIP_SOCKET_RX_DONE,
	EV_LWIP_SOCKET_CREATE,
	EV_LWIP_SOCKET_CONNECT,
	EV_LWIP_SOCKET_DNS,
	EV_LWIP_SOCKET_DNS_IPV6,
	EV_LWIP_SOCKET_LISTEN,
	EV_LWIP_SOCKET_ACCPET,
	EV_LWIP_SOCKET_CLOSE,
	EV_LWIP_NETIF_LINK_STATE,
//	EV_LWIP_DHCP_TIMER,
//	EV_LWIP_FAST_TIMER,
	EV_LWIP_NETIF_SET_IP,
	EV_LWIP_NETIF_IPV6_BY_MAC,
};

void net_lwip_register_adapter(uint8_t adapter_index);
void net_lwip_init(void);
int net_lwip_check_all_ack(int socket_id);
void net_lwip_set_netif(uint8_t adapter_index, struct netif *netif, void *init, uint8_t is_default);
struct netif * net_lwip_get_netif(uint8_t adapter_index);
void net_lwip_input_packets(struct netif *netif, struct pbuf *p);
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

void net_lwip_set_rx_fast_ack(uint8_t adapter_index, uint8_t onoff);
//设置TCP接收窗口大小，影响接收速度，tcp_mss_num越大越快，但是同样会消耗更多ram
void net_lwip_set_tcp_rx_cache(uint8_t adapter_index, uint16_t tcp_mss_num);
#endif
#endif

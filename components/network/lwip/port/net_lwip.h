#ifndef __NET_LWIP_H__
#define __NET_LWIP_H__
void net_lwip_register_adapter(uint8_t adapter_index);
void net_lwip_init(void);
int net_lwip_check_all_ack(int socket_id);
void net_lwip_set_netif(uint8_t adapter_index, struct netif *netif, void *init, uint8_t is_default);
void net_lwip_set_network_state(uint8_t adapter_index, uint8_t onoff);
#endif

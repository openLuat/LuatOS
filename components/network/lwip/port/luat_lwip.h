#ifndef __LUAT_LWIP_H__
#define __LUAT_LWIP_H__
void luat_lwip_register_adapter(uint8_t adapter_index);
void luat_lwip_init(void);
int luat_lwip_check_all_ack(int socket_id);
void luat_lwip_set_netif(uint8_t netif_id, struct netif *netif, uint8_t is_wlan);
#endif

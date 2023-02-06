#ifndef __W5500_H__
#define __W5500_H__

#include <stdint.h>


#define _W5500_IO_BASE_              0x00000000
#define WIZCHIP_SREG_BLOCK(N)       (1+4*N) //< Socket N register block
#define Sn_PROTO(N)					(_W5500_IO_BASE_ + (0x0014 << 8) + (WIZCHIP_SREG_BLOCK(N) << 3))


///-------------------------------------------------------------------------------------------------
/// <summary>	IP PROTOCOL. </summary>
///
/// <remarks>	Tony Wang, 14:49 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define IPPROTO_IP                   0			/**< Dummy for IP */
#define IPPROTO_ICMP                 1			/**< Control message protocol */
#define IPPROTO_IGMP                 2			/**< Internet group management protocol */
#define IPPROTO_GGP                  3			/**< Gateway^2 (deprecated) */
#define IPPROTO_TCP                  6			/**< TCP */
#define IPPROTO_PUP                  12			/**< PUP */
#define IPPROTO_UDP                  17			/**< UDP */
#define IPPROTO_IDP                  22			/**< XNS idp */
#define IPPROTO_ND                   77			/**< UNOFFICIAL net disk protocol */
#define IPPROTO_RAW                  255		/**< Raw IP packet */

void w5500_set_static_ip(uint32_t ipv4, uint32_t submask, uint32_t gateway);
void w5500_set_mac(uint8_t mac[6]);
void w5500_get_mac(uint8_t mac[6]);
void w5500_set_param(uint16_t timeout, uint8_t retry, uint8_t auto_speed, uint8_t force_arp);
int w5500_reset(void);
void w5500_init(luat_spi_t* spi, uint8_t irq_pin, uint8_t rst_pin, uint8_t link_pin);
uint8_t w5500_device_ready(void);
void w5500_register_adapter(int index);

#endif

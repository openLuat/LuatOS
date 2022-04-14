#ifndef __W5500_H__
#define __W5500_H__

#include <stdint.h>



enum
{
	W5500_CMD_SOCKET_TX,
	W5500_CMD_SOCKET_CONNECT,
	W5500_CMD_SOCKET_CLOSE,
	W5500_CMD_SOCKET_CONFIG,
	W5500_CMD_SOCKET_LISTEN,
	W5500_CMD_SOCKET_ACCEPT,
	W5500_CMD_DNS,
	W5500_CMD_SET_IP,
	W5500_CMD_SET_MAC,
	W5500_CMD_SET_TO_PARAM,
	W5500_CMD_RE_INIT,
	W5500_CMD_REG_OP,	//直接操作寄存器
};



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

#endif

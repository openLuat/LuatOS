#ifndef __W5500_H__
#define __W5500_H__

#include <stdint.h>


/// <summary>
/// Mode Register address
/// W5500 SPI Frame consists of 16bits Offset Address in Address Phase,
/// 8bits Control Phase and N bytes Data Phase.
/// 0				   8                  16                 24                   ~
/// | ---------------- | ---------------- | ---------------- | ----------------------
/// |		16bit offset Address		  |	  Control Bits   |		Data Phase
/// 
/// The 8bits Control Phase is reconfigured with Block Select bits(BSB[4:0]),
/// Read / Write Access Mode bit(RWB) and SPI Operation Mode(OM[1:0]).
/// Block Select bits select a block as like common register, socket register, tx bufferand tx buffer.
/// Address value is defined as 16bit offset Address, BSB[4:0] and the three bits of zero - padding.(The RWB and OM[1:0] are '0 'padding)
/// Please, refer to W5500 datasheet for more detail about Memory Map.
/// </summary>

///-------------------------------------------------------------------------------------------------
/// <summary>	Number of sockets. </summary>
///
/// <remarks>	Tony Wang, 14:39 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define MAX_SOCK_NUM				8 

///-------------------------------------------------------------------------------------------------
/// <summary>	Mode Register address. </summary>
///
/// <remarks>	Tony Wang, 14:39 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define MR                          (0x000000)

///-------------------------------------------------------------------------------------------------
/// <summary>	Gateway IP Register address. </summary>
///
/// <remarks>	Tony Wang, 14:39 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define GAR0                        (0x000100)
#define GAR1                        (0x000200)
#define GAR2                        (0x000300)
#define GAR3                        (0x000400)

///-------------------------------------------------------------------------------------------------
/// <summary>	Subnet mask Register address. </summary>
///
/// <remarks>	Tony Wang, 14:39 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define SUBR0                       (0x000500)
#define SUBR1                       (0x000600)
#define SUBR2                       (0x000700)
#define SUBR3                       (0x000800)

///-------------------------------------------------------------------------------------------------
/// <summary>	Source MAC Register address. </summary>
///
/// <remarks>	Tony Wang, 14:40 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define SHAR0                       (0x000900)
#define SHAR1                       (0x000A00)
#define SHAR2                       (0x000B00)
#define SHAR3                       (0x000C00)
#define SHAR4                       (0x000D00)
#define SHAR5                       (0x000E00)

///-------------------------------------------------------------------------------------------------
/// <summary>	Source IP Register address. </summary>
///
/// <remarks>	Tony Wang, 14:40 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define SIPR0                       (0x000F00)
#define SIPR1                       (0x001000)
#define SIPR2                       (0x001100)
#define SIPR3                       (0x001200)

///-------------------------------------------------------------------------------------------------
/// <summary>	set Interrupt low level timer register address. </summary>
///
/// <remarks>	Tony Wang, 14:40 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define INTLEVEL0                   (0x001300)
#define INTLEVEL1                   (0x001400)

///-------------------------------------------------------------------------------------------------
/// <summary>	Interrupt Register. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define IR                          (0x001500)

///-------------------------------------------------------------------------------------------------
/// <summary>	Interrupt mask register. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define IMR                         (0x001600)

///-------------------------------------------------------------------------------------------------
/// <summary>	Socket Interrupt Register. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define SIR                         (0x001700)

///-------------------------------------------------------------------------------------------------
/// <summary>	Socket Interrupt Mask Register. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define SIMR                        (0x001800)

///-------------------------------------------------------------------------------------------------
/// <summary>	Timeout register address( 1 is 100us ) </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define RTR0                        (0x001900)
#define RTR1                        (0x001A00)

///-------------------------------------------------------------------------------------------------
/// <summary>	Retry count reigster. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define WIZ_RCR						(0x001B00)

///-------------------------------------------------------------------------------------------------
/// <summary>	PPP LCP Request Timer register  in PPPoE mode. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define PTIMER                      (0x001C00)

///-------------------------------------------------------------------------------------------------
/// <summary>	PPP LCP Magic number register  in PPPoE mode. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define PMAGIC                      (0x001D00)

///-------------------------------------------------------------------------------------------------
/// <summary>	PPP Destination MAC Register address. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define PDHAR0                      (0x001E00)
#define PDHAR1                      (0x001F00)
#define PDHAR2                      (0x002000)
#define PDHAR3                      (0x002100)
#define PDHAR4                      (0x002200)
#define PDHAR5                      (0x002300)

///-------------------------------------------------------------------------------------------------
/// <summary>	PPP Session Identification Register. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define PSID0                       (0x002400)
#define PSID1                       (0x002500)

///-------------------------------------------------------------------------------------------------
/// <summary>	PPP Maximum Segment Size(MSS) register. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define PMR0                        (0x002600)
#define PMR1                        (0x002700)

///-------------------------------------------------------------------------------------------------
/// <summary>	Unreachable IP register address in UDP mode. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define UIPR0                       (0x002800)
#define UIPR1                       (0x002900)
#define UIPR2                       (0x002A00)
#define UIPR3                       (0x002B00)

///-------------------------------------------------------------------------------------------------
/// <summary>	Unreachable Port register address in UDP mode. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define UPORT0                      (0x002C00)
#define UPORT1                      (0x002D00)

///-------------------------------------------------------------------------------------------------
/// <summary>	PHY Configuration Register. </summary>
///
/// <remarks>	Tony Wang, 14:41 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define PHYCFGR						(0x002E00)

///-------------------------------------------------------------------------------------------------
/// <summary>	chip version register address. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define VERSIONR                    (0x003900)   

///-------------------------------------------------------------------------------------------------
/// <summary>	socket Mode register. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_MR(ch)                       (0x000008 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	channel Sn_CR register. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_CR(ch)                       (0x000108 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	channel interrupt register. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_IR(ch)                       (0x000208 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	channel status register. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_SR(ch)                       (0x000308 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	source port register. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_PORT0(ch)                    (0x000408 + (ch<<5))
#define Sn_PORT1(ch)                    (0x000508 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Peer MAC register address. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_DHAR0(ch)                    (0x000608 + (ch<<5))
#define Sn_DHAR1(ch)                    (0x000708 + (ch<<5))
#define Sn_DHAR2(ch)                    (0x000808 + (ch<<5))
#define Sn_DHAR3(ch)                    (0x000908 + (ch<<5))
#define Sn_DHAR4(ch)                    (0x000A08 + (ch<<5))
#define Sn_DHAR5(ch)                    (0x000B08 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Peer IP register address. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_DIPR0(ch)                    (0x000C08 + (ch<<5))
#define Sn_DIPR1(ch)                    (0x000D08 + (ch<<5))
#define Sn_DIPR2(ch)                    (0x000E08 + (ch<<5))
#define Sn_DIPR3(ch)                    (0x000F08 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Peer port register address. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_DPORT0(ch)                   (0x001008 + (ch<<5))
#define Sn_DPORT1(ch)                   (0x001108 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Maximum Segment Size(Sn_MSSR0) register address. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_MSSR0(ch)                    (0x001208 + (ch<<5))
#define Sn_MSSR1(ch)                    (0x001308 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	IP Type of Service(TOS) Register. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_TOS(ch)                      (0x001508 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	IP Time to live(TTL) Register. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_TTL(ch)                      (0x001608 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Receive memory size reigster. </summary>
///
/// <remarks>	Tony Wang, 14:42 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_RXMEM_SIZE(ch)               (0x001E08 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Transmit memory size reigster. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_TXMEM_SIZE(ch)               (0x001F08 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Transmit free memory size register. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_TX_FSR0(ch)                  (0x002008 + (ch<<5))
#define Sn_TX_FSR1(ch)                  (0x002108 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Transmit memory read pointer register address. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_TX_RD0(ch)                   (0x002208 + (ch<<5))
#define Sn_TX_RD1(ch)                   (0x002308 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Transmit memory write pointer register address. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_TX_WR0(ch)                   (0x002408 + (ch<<5))
#define Sn_TX_WR1(ch)                   (0x002508 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Received data size register. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_RX_RSR0(ch)                  (0x002608 + (ch<<5))
#define Sn_RX_RSR1(ch)                  (0x002708 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Read point of Receive memory. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_RX_RD0(ch)                   (0x002808 + (ch<<5))
#define Sn_RX_RD1(ch)                   (0x002908 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Write point of Receive memory. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_RX_WR0(ch)                   (0x002A08 + (ch<<5))
#define Sn_RX_WR1(ch)                   (0x002B08 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	socket interrupt mask register. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_IMR(ch)                      (0x002C08 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	frag field value in IP header register. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_FRAG(ch)                     (0x002D08 + (ch<<5))

///-------------------------------------------------------------------------------------------------
/// <summary>	Keep Timer register. </summary>
///
/// <remarks>	Tony Wang, 14:43 19/3/21. </remarks>
///
/// <param name="ch">	The ch. </param>
///-------------------------------------------------------------------------------------------------

#define Sn_KPALVTR(ch)                  (0x002F08 + (ch<<5))

#define _W5500_IO_BASE_              0x00000000
#define WIZCHIP_SREG_BLOCK(N)       (1+4*N) //< Socket N register block
#define Sn_PROTO(N)					(_W5500_IO_BASE_ + (0x0014 << 8) + (WIZCHIP_SREG_BLOCK(N) << 3))

///-------------------------------------------------------------------------------------------------
/// <summary>	/* MODE register values. </summary>
///
/// <remarks>	Tony Wang, 14:47 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define MR_RST                       0x80		/**< reset */
#define MR_WOL                       0x20		/**< Wake on Lan */
#define MR_PB                        0x10		/**< ping block */
#define MR_PPPOE                     0x08		/**< enable pppoe */
#define MR_UDP_FARP                  0x02		/**< enbale FORCE ARP */

///-------------------------------------------------------------------------------------------------
/// <summary>	/* IR register values. </summary>
///
/// <remarks>	Tony Wang, 14:47 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define IR_CONFLICT                  0x80		/**< check ip confict */
#define IR_UNREACH                   0x40		/**< get the destination unreachable message in UDP sending */
#define IR_PPPoE                     0x20		/**< get the PPPoE close message */
#define IR_MAGIC                     0x10		/**< get the magic packet interrupt */

///-------------------------------------------------------------------------------------------------
/// <summary>	Sn_MR values. </summary>
///
/// <remarks>	Tony Wang, 14:47 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define Sn_MR_CLOSE                  0x00		/**< unused socket */
#define Sn_MR_TCP                    0x01		/**< TCP */
#define Sn_MR_UDP                    0x02		/**< UDP */
#define Sn_MR_IPRAW                  0x03		/**< IP LAYER RAW SOCK */
#define Sn_MR_MACRAW                 0x04		/**< MAC LAYER RAW SOCK */
#define Sn_MR_PPPOE                  0x05		/**< PPPoE */
#define Sn_MR_UCASTB                 0x10		/**< Unicast Block in UDP Multicating*/
#define Sn_MR_ND                     0x20		/**< No Delayed Ack(TCP) flag */
#define Sn_MR_MC                     0x20		/**< Multicast IGMP (UDP) flag */
#define Sn_MR_BCASTB                 0x40		/**< Broadcast blcok in UDP Multicating */
#define Sn_MR_MULTI                  0x80		/**< support UDP Multicating */

///-------------------------------------------------------------------------------------------------
/// <summary>	Sn_MR values on MACRAW MODE. </summary>
///
/// <remarks>	Tony Wang, 14:48 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define Sn_MR_MIP6N                  0x10		/**< IPv6 packet Block */
#define Sn_MR_MMB                    0x20		/**< IPv4 Multicasting Block */
//#define Sn_MR_BCASTB                 0x40     /**< Broadcast blcok */
#define Sn_MR_MFEN                   0x80		/**< support MAC filter enable */

///-------------------------------------------------------------------------------------------------
/// <summary>	Sn_CR values. </summary>
///
/// <remarks>	Tony Wang, 14:48 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define Sn_CR_OPEN                   0x01		/**< initialize or open socket */
#define Sn_CR_LISTEN                 0x02		/**< wait connection request in tcp mode(Server mode) */
#define Sn_CR_CONNECT                0x04		/**< send connection request in tcp mode(Client mode) */
#define Sn_CR_DISCON                 0x08		/**< send closing reqeuset in tcp mode */
#define Sn_CR_CLOSE                  0x10		/**< close socket */
#define Sn_CR_SEND                   0x20		/**< update txbuf pointer, send data */
#define Sn_CR_SEND_MAC               0x21		/**< send data with MAC address, so without ARP process */
#define Sn_CR_SEND_KEEP              0x22		/**<  send keep alive message */
#define Sn_CR_RECV                   0x40		/**< update rxbuf pointer, recv data */

#ifdef __DEF_IINCHIP_PPP__
#define Sn_CR_PCON                0x23      
#define Sn_CR_PDISCON             0x24      
#define Sn_CR_PCR                 0x25      
#define Sn_CR_PCN                 0x26     
#define Sn_CR_PCJ                 0x27     
#endif

///-------------------------------------------------------------------------------------------------
/// <summary>	Sn_IR values. </summary>
///
/// <remarks>	Tony Wang, 14:48 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#ifdef __DEF_IINCHIP_PPP__
#define Sn_IR_PRECV               0x80     
#define Sn_IR_PFAIL               0x40     
#define Sn_IR_PNEXT               0x20     
#endif

#define Sn_IR_SEND_OK                0x10		/**< complete sending */
#define Sn_IR_TIMEOUT                0x08		/**< assert timeout */
#define Sn_IR_RECV                   0x04		/**< receiving data */
#define Sn_IR_DISCON                 0x02		/**< closed socket */
#define Sn_IR_CON                    0x01		/**< established connection */

///-------------------------------------------------------------------------------------------------
/// <summary>	Sn_SR values. </summary>
///
/// <remarks>	Tony Wang, 14:49 19/3/21. </remarks>
///-------------------------------------------------------------------------------------------------

#define SOCK_CLOSED                  0x00		/**< closed */
#define SOCK_INIT                    0x13		/**< init state */
#define SOCK_LISTEN                  0x14		/**< listen state */
#define SOCK_SYNSENT                 0x15		/**< connection state */
#define SOCK_SYNRECV                 0x16		/**< connection state */
#define SOCK_ESTABLISHED             0x17		/**< success to connect */
#define SOCK_FIN_WAIT                0x18		/**< closing state */
#define SOCK_CLOSING                 0x1A		/**< closing state */
#define SOCK_TIME_WAIT               0x1B		/**< closing state */
#define SOCK_CLOSE_WAIT              0x1C		/**< closing state */
#define SOCK_LAST_ACK                0x1D		/**< closing state */
#define SOCK_UDP                     0x22		/**< udp socket */
#define SOCK_IPRAW                   0x32		/**< ip raw mode socket */
#define SOCK_MACRAW                  0x42		/**< mac raw mode socket */
#define SOCK_PPPOE                   0x5F		/**< pppoe socket */

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

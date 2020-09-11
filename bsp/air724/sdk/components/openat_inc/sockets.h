/* Copyright (C) 2016 RDA Technologies Limited and/or its affiliates("RDA").
* All rights reserved.
*
* This software is supplied "AS IS" without any warranties.
* RDA assumes no responsibility or liability for the use of the software,
* conveys no license or title under any patent, copyright, or mask work
* right to the product. RDA reserves the right to make changes in the
* software without notification.  RDA also make no representation or
* warranty that such application will be suitable for the specified use
* without further testing or modification.
*/
#ifndef __LWIP_SOCKETS_H__
#define __LWIP_SOCKETS_H__

#include "cfw.h"
#include "lwip/opt.h"
#include "lwip/sockets.h"
#include "lwip/errno.h"
#include "lwip/pbuf.h"
#include "lwip/inet.h"
#include "lwip/ip_addr.h"
#include "lwip/ip4_addr.h"
#include "lwip/dns.h"
#include "lwip/ip4.h"
#include "lwip/icmp.h"
#include "lwip/etharp.h"
#include "lwip/priv/tcpip_priv.h"
#include "lwip/netif.h"
#include "lwip/tcpip.h"
#include "lwip/opt.h"
#include "lwip/etharp.h"
#include "lwip/err.h"
#include "lwip/pbuf.h"
#include "lwip/memp.h"
#include "lwip/ip_addr.h"
#include "lwip/ethip6.h"

extern struct netif *netif_default;

#define CFW_TCPIP_SOCK_STREAM SOCK_STREAM
#define CFW_TCPIP_SOCK_DGRAM SOCK_DGRAM
#define CFW_TCPIP_SOCK_RAW SOCK_RAW

#define CFW_TCPIP_AF_UNSPEC AF_UNSPEC
#define CFW_TCPIP_AF_INET AF_INET
#define CFW_TCPIP_PF_INET PF_INET
#define CFW_TCPIP_PF_UNSPEC PF_UNSPEC

#define CFW_TCPIP_IPPROTO_IP IPPROTO_IP
#define CFW_TCPIP_IPPROTO_ICMP IPPROTO_ICMP
#define CFW_TCPIP_IPPROTO_TCP IPPROTO_TCP
#define CFW_TCPIP_IPPROTO_UDP IPPROTO_UDP

#define ERR_TCPIP_ENODATA ENODATA
#define ERR_TCPIP_EWOULDBLOCK EWOULDBLOCK
#define ERR_TCPIP_IF ERR_IF
#define ERR_TCPIP_MEM ERR_MEM
#define ERR_TCPIP_OK ERR_OK

#define CFW_ERR_TCPIP_CONN_TIMEOUT 13 /* connect time out       */
#define INVALID_SOCKET (SOCKET)(~0)
#define SOCKET_ERROR -1

#ifndef GPRS_MTU
#define GPRS_MTU 1500
#endif

#define UDP_FLAGS_RAI_0 0x00
#define UDP_FLAGS_RAI_1 0x01
#define UDP_FLAGS_RAI_2 0x02
#define UDP_FLAGS_EXCEPTIN_MSG 0x04

#ifndef __SOCKET__
typedef int SOCKET;
#define __SOCKET__
#endif

typedef struct in_addr in_addr;
typedef struct in6_addr in6_addr;

#define IPH_VHLTOS_SET(hdr, v, hl, tos) \
    do                                  \
    {                                   \
        IPH_VHL_SET(hdr, v, hl);        \
        IPH_TOS_SET(hdr, tos);          \
    } while (0)

typedef struct _CFW_TCPIP_SOCKET_ADDR
{
    uint8_t sin_len;
    uint8_t sin_family;
    uint16_t sin_port;
    in_addr sin_addr;
    int8_t sin_zero[8];
} CFW_TCPIP_SOCKET_ADDR;

typedef struct _CFW_TCPIP_SOCKET_ADDR6
{
    uint8_t sin6_len;
    uint8_t sin6_family;
    uint16_t sin6_port;
    uint32_t sin6_flowinfo;
    in6_addr sin6_addr;
    uint32_t sin6_scope_id;
} CFW_TCPIP_SOCKET_ADDR6;

typedef struct _CFW_WIFI_DATA
{
    uint16_t nDataLength;
    uint8_t srcMac[6];
    uint8_t destMac[6];
    uint8_t *pData;
} CFW_WIFI_DATA;

typedef struct _CFW_WIFI_NETIF
{
    uint8_t Mac[6];
    //  uint8_t gwMac[6];
    ip_addr_t ipaddr;
} CFW_WIFI_NETIF;

typedef struct
{
    uint8_t ref_count;
    uint16_t msg_len;
    bool use_dhcp;
    uint8_t ip_addr[4];
    uint8_t gateway[4];
    uint8_t netmask[4];
    uint8_t pri_dns_addr[4];
    uint8_t sec_dns_addr[4];
} ipaddr_change_req_struct;

typedef struct
{
    uint8_t ref_count;
    uint16_t msg_len;
    uint8_t cause;
    uint8_t ip_addr[4];
    uint8_t pri_dns_addr[4];
    uint8_t sec_dns_addr[4];
    uint8_t gateway[4];
    uint8_t netmask[4];
} ipaddr_update_ind_struct;

typedef enum
{
    CFW_SOCKET_NONE,
    CFW_SOCKET_CONNECTING,
    CFW_SOCKET_CONNECTED,
    CFW_SOCKET_BEARER_LOSING,
    CFW_SOCKET_CLOSING,
    CFW_SOCKET_COLSED,
} socket_status_t;

typedef struct
{
    char *cServer;           //ntp server name
    int iRetry;              //retry times if it fails
    bool bAutoUpdate;        //long time update or not
    int iSyncMode;           //sync time mode
    osiCallback_t fCallback; //call back function when finish or timedout
} CFW_SNTP_CONFIG;

typedef enum
{
    CFW_SNTP_PARAM_INVALID,
    CFW_SNTP_SYNCING,
    CFW_SNTP_READY
} sntp_status_t;

/*\+new\lijiaodi\2020.2.12\添加socket的app type\*/
typedef enum
{
	CFW_SOCKET_APP_NONE,
    CFW_SOCKET_APP_RDA,
    CFW_SOCKET_APP_OPENAT,
} socket_app_type_t;
	
typedef enum
{
	CFW_DNS_APP_NONE,
	CFW_DNS_APP_RDA,
	CFW_DNS_APP_OPENAT,
} dns_app_type_t;


/*\-new\lijiaodi\2020.2.12\添加socket的app type\*/

void CFW_SetPppSendFun(bool (*sendCallBack)(uint8_t *pData, uint16_t uDataSize, uint8_t nDLCI));
void CFW_SetGetSimCidFun(void (*get_simid_cid)(uint8_t *pSimId, uint8_t *pCid, uint8_t nDLCI));

uint32_t CFW_TcpipInetAddr(const char *cp);
int32_t CFW_TcpipAvailableBuffer(SOCKET nSocket);
uint32_t CFW_TcpipGetLastError(void);
SOCKET CFW_TcpipSocket(uint8_t nDomain, uint8_t nType, uint8_t nProtocol);
SOCKET CFW_TcpipSocketEX(uint8_t nDomain, uint8_t nType, uint8_t nProtocol, osiCallback_t func, uint32_t nUserParam);
void CFW_TcpipSocketSetParam(SOCKET nSocket, osiCallback_t func, uint32_t nUserParam);
uint32_t CFW_TcpipSocketConnect(SOCKET nSocket, CFW_TCPIP_SOCKET_ADDR *pName, uint8_t nNameLen);
int CFW_TcpipSocketSend(SOCKET nSocket, uint8_t *pData, uint16_t nDataSize, uint32_t nFlags);
uint32_t CFW_TcpipSocketRecv(SOCKET nSocket, uint8_t *pData, uint16_t nDataSize, uint32_t nFlags);
int CFW_TcpipSocketClose(SOCKET nSocket);
uint32_t CFW_TcpipSocketShutdownOutput(SOCKET nSocket, int how);
uint32_t CFW_TcpipSocketSendto(SOCKET nSocket, void *pData, uint16_t nDataSize, uint32_t nFlags, CFW_TCPIP_SOCKET_ADDR *to, int tolen);
uint32_t CFW_TcpipSocketRecvfrom(SOCKET nSocket, void *pMem, int nLen, uint32_t nFlags, CFW_TCPIP_SOCKET_ADDR *from, int *fromlen);
uint32_t CFW_TcpipSocketBind(SOCKET nSocket, CFW_TCPIP_SOCKET_ADDR *pName, uint8_t nNameLen);
uint32_t CFW_TcpipSocketListen(SOCKET nSocket, uint32_t backlog);
uint32_t CFW_TcpipSocketAccept(SOCKET nSocket, CFW_TCPIP_SOCKET_ADDR *addr, uint32_t *addrlen);
uint32_t CFW_TcpipSocketGetsockname(SOCKET nSocket, CFW_TCPIP_SOCKET_ADDR *pName, int *pNameLen);
uint32_t CFW_TcpipSocketGetpeername(SOCKET nSocket, CFW_TCPIP_SOCKET_ADDR *pName, int *pNameLen); //
uint32_t CFW_Gethostbyname(char *hostname, ip_addr_t *addr, uint8_t nCid, CFW_SIM_ID nSimID);
uint32_t CFW_GethostbynameEX(char *hostname, ip_addr_t *addr, uint8_t nCid, CFW_SIM_ID nSimID, osiCallback_t func, void *param);
uint32_t CFW_GetallhostbynameEX(char *hostname, ip_addr_t *addr, uint8_t nCid, CFW_SIM_ID nSimID, osiCallback_t func, void *param);
int CFW_TcpipSocketConnectEx(SOCKET nSocket, CFW_TCPIP_SOCKET_ADDR *pName, uint8_t nNameLen, CFW_SIM_ID nSimID);
int CFW_TcpipSocketGetsockopt(SOCKET nSocket, int level, int optname, void *optval, int *optlen);
int CFW_TcpipSocketSetsockopt(SOCKET nSocket, int level, int optname, const void *optval, int optlen);
uint16_t CFW_TcpipGetRecvAvailable(SOCKET nSocket);
int32_t CFW_TcpipSocketGetAckedSize(SOCKET nSocket);
int32_t CFW_TcpipSocketGetSentSize(SOCKET nSocket);
socket_status_t CFW_TcpipSocketGetStatus(SOCKET nSocket);
uint32_t CFW_TcpipSocketIoctl(SOCKET nSocket, int cmd, void *argp);

int32_t CFW_TcpipSocketGetMss(SOCKET nSocket);

CFW_SNTP_CONFIG *CFW_SntpInit();
sntp_status_t CFW_SntpStart(CFW_SNTP_CONFIG *sntpconfig);
void CFW_SntpStop(CFW_SNTP_CONFIG *sntpconfig);
#define UPLOAD 1
#define DOWNLOAD 2

#define LWIP_DATA 1
#define PPP_DATA 2
#define RNDIS_DATA 3
bool CFW_get_Netif_dataCount(uint16_t simID, uint16_t CID, uint16_t uType, uint16_t uDataType, uint32_t *loadsize);

#if LWIP_IPV4
#define IP4ADDR_PORT_TO_SOCKADDR(sin, ipaddr, port)       \
    do                                                    \
    {                                                     \
        (sin)->sin_len = sizeof(struct sockaddr_in);      \
        (sin)->sin_family = AF_INET;                      \
        (sin)->sin_port = lwip_htons((port));             \
        inet_addr_from_ip4addr(&(sin)->sin_addr, ipaddr); \
        memset((sin)->sin_zero, 0, SIN_ZERO_LEN);         \
    } while (0)
#define SOCKADDR4_TO_IP4ADDR_PORT(sin, ipaddr, port)                \
    do                                                              \
    {                                                               \
        inet_addr_to_ip4addr(ip_2_ip4(ipaddr), &((sin)->sin_addr)); \
        (port) = lwip_ntohs((sin)->sin_port);                       \
    } while (0)
#endif /* LWIP_IPV4 */

#if LWIP_IPV6
#define IP6ADDR_PORT_TO_SOCKADDR(sin6, ipaddr, port)         \
    do                                                       \
    {                                                        \
        (sin6)->sin6_len = sizeof(struct sockaddr_in6);      \
        (sin6)->sin6_family = AF_INET6;                      \
        (sin6)->sin6_port = lwip_htons((port));              \
        (sin6)->sin6_flowinfo = 0;                           \
        inet6_addr_from_ip6addr(&(sin6)->sin6_addr, ipaddr); \
        (sin6)->sin6_scope_id = ip6_addr_zone(ipaddr);       \
    } while (0)
#define SOCKADDR6_TO_IP6ADDR_PORT(sin6, ipaddr, port)                           \
    do                                                                          \
    {                                                                           \
        inet6_addr_to_ip6addr(ip_2_ip6(ipaddr), &((sin6)->sin6_addr));          \
        if (ip6_addr_has_scope(ip_2_ip6(ipaddr), IP6_UNKNOWN))                  \
        {                                                                       \
            ip6_addr_set_zone(ip_2_ip6(ipaddr), (u8_t)((sin6)->sin6_scope_id)); \
        }                                                                       \
        (port) = lwip_ntohs((sin6)->sin6_port);                                 \
    } while (0)
#endif /* LWIP_IPV6 */

#if LWIP_IPV4 && LWIP_IPV6
void sockaddr_to_ipaddr_port(const struct sockaddr *sockaddr, ip_addr_t *ipaddr, u16_t *port);

#define IS_SOCK_ADDR_LEN_VALID(namelen) (((namelen) == sizeof(struct sockaddr_in)) || \
                                         ((namelen) == sizeof(struct sockaddr_in6)))
#define IS_SOCK_ADDR_TYPE_VALID(name) (((name)->sa_family == AF_INET) || \
                                       ((name)->sa_family == AF_INET6))
#define SOCK_ADDR_TYPE_MATCH(name, sock)                                              \
    ((((name)->sa_family == AF_INET) && !(NETCONNTYPE_ISIPV6((sock)->conn->type))) || \
     (((name)->sa_family == AF_INET6) && (NETCONNTYPE_ISIPV6((sock)->conn->type))))
#define IPADDR_PORT_TO_SOCKADDR(sockaddr, ipaddr, port)                                                  \
    do                                                                                                   \
    {                                                                                                    \
        if (((ipaddr) && IP_IS_ANY_TYPE_VAL(*ipaddr)) || IP_IS_V6(ipaddr))                               \
        {                                                                                                \
            IP6ADDR_PORT_TO_SOCKADDR((struct sockaddr_in6 *)(void *)(sockaddr), ip_2_ip6(ipaddr), port); \
        }                                                                                                \
        else                                                                                             \
        {                                                                                                \
            IP4ADDR_PORT_TO_SOCKADDR((struct sockaddr_in *)(void *)(sockaddr), ip_2_ip4(ipaddr), port);  \
        }                                                                                                \
    } while (0)
#define SOCKADDR_TO_IPADDR_PORT(sockaddr, ipaddr, port) sockaddr_to_ipaddr_port(sockaddr, ipaddr, &(port))
#define DOMAIN_TO_NETCONN_TYPE(domain, type) (((domain) == AF_INET) ? (type) : (enum netconn_type)((type) | NETCONN_TYPE_IPV6))
#elif LWIP_IPV6 /* LWIP_IPV4 && LWIP_IPV6 */
#define IS_SOCK_ADDR_LEN_VALID(namelen) ((namelen) == sizeof(struct sockaddr_in6))
#define IS_SOCK_ADDR_TYPE_VALID(name) ((name)->sa_family == AF_INET6)
#define SOCK_ADDR_TYPE_MATCH(name, sock) 1
#define IPADDR_PORT_TO_SOCKADDR(sockaddr, ipaddr, port) \
    IP6ADDR_PORT_TO_SOCKADDR((struct sockaddr_in6 *)(void *)(sockaddr), ip_2_ip6(ipaddr), port)
#define SOCKADDR_TO_IPADDR_PORT(sockaddr, ipaddr, port) \
    SOCKADDR6_TO_IP6ADDR_PORT((const struct sockaddr_in6 *)(const void *)(sockaddr), ipaddr, port)
#define DOMAIN_TO_NETCONN_TYPE(domain, netconn_type) (netconn_type)
#else /*-> LWIP_IPV4: LWIP_IPV4 && LWIP_IPV6 */
#define IS_SOCK_ADDR_LEN_VALID(namelen) ((namelen) == sizeof(struct sockaddr_in))
#define IS_SOCK_ADDR_TYPE_VALID(name) ((name)->sa_family == AF_INET)
#define SOCK_ADDR_TYPE_MATCH(name, sock) 1
#define IPADDR_PORT_TO_SOCKADDR(sockaddr, ipaddr, port) \
    IP4ADDR_PORT_TO_SOCKADDR((struct sockaddr_in *)(void *)(sockaddr), ip_2_ip4(ipaddr), port)
#define SOCKADDR_TO_IPADDR_PORT(sockaddr, ipaddr, port) \
    SOCKADDR4_TO_IP4ADDR_PORT((const struct sockaddr_in *)(const void *)(sockaddr), ipaddr, port)
#define DOMAIN_TO_NETCONN_TYPE(domain, netconn_type) (netconn_type)
#endif /* LWIP_IPV6 */

#endif /* __LWIP_SOCKETS_H__ */

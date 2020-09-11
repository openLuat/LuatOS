/*********************************************************
  Copyright (C), AirM2M Tech. Co., Ltd.
  Author: lifei
  Description: AMOPENAT 寮?鏀惧钩鍙?
  Others:
  History: 
    Version锛?Date:       Author:   Modification:
    V0.1      2012.12.14  lifei     鍒涘缓鏂囦欢
*********************************************************/
#ifndef AM_OPENAT_SOCKET_H
#define AM_OPENAT_SOCKET_H

#include "am_openat_common.h"


#define OPENAT_SOCKET_F_SETFL 4
#define OPENAT_SOCKET_O_NONBLOCK  1 /* nonblocking I/O */

typedef enum
{
  OPENAT_SOCKET_SUCCESS = 0,
  OPENAT_SOCKET_ENOMEM,
  OPENAT_SOCKET_ENOBUFS,
  OPENAT_SOCKET_ETIMEOUT,
  OPENAT_SOCKET_ERTE,
  OPENAT_SOCKET_EINPROGRESS,
  OPENAT_SOCKET_EINVAL, 
  OPENAT_SOCKET_EWOULDBLOCK,
  OPENAT_SOCKET_EADDRINUSE,
  OPENAT_SOCKET_EALREADY,
  OPENAT_SOCKET_EISCONN,
  OPENAT_SOCKET_ENOTCONN,
  OPENAT_SOCKET_EIF,
  OPENAT_SOCKET_EABORT,
  OPENAT_SOCKET_ERST,
  OPENAT_SOCKET_ECLSD,
  OPENAT_SOCKET_EARG,
  OPENAT_SOCKET_EIO,
  OPENAT_SOCKET_SSL_EHANDESHAK,
  OPENAT_SOCKET_SSL_EINIT,
  OPENAT_SOCKET_SSL_EINVALID,
}openSocketErrno;

#define OPENAT_SOCKET_SO_ERROR     0x1007    /* get error status and clear */
#define OPENAT_SOCKET_SOL_SOCKET  0xfff    /* options for socket level */

#define OPENAT_SOCKET_MSG_DONTWAIT (0x08)
/*+\BUG\wj\2020.2.20\SSL连接中CIPRXGET无法得到完整数据，读协议栈剩余数据错误 */
#define OPEANT_SOCKET_FIONREAD_CMD  1074030207// FIONREAD
/*-\BUG\wj\2020.2.20\SSL连接中CIPRXGET无法得到完整数据，读协议栈剩余数据错误 */
#ifndef OPENAT_SOCKET_FD_SET
  #undef  OPENAT_SOCKET_FD_SETSIZE
  /* Make FD_SETSIZE match NUM_SOCKETS in socket.c */
  #define OPENAT_SOCKET_FD_SETSIZE    32
  #define OPENAT_SOCKET_FD_SET(n, p)  ((p)->fd_bits[(n)/8] |=  (1 << ((n) & 7)))
  #define OPENAT_SOCKET_FD_CLR(n, p)  ((p)->fd_bits[(n)/8] &= ~(1 << ((n) & 7)))
  #define OPENAT_SOCKET_FD_ISSET(n,p) ((p)->fd_bits[(n)/8] &   (1 << ((n) & 7)))
  #define OPENAT_SOCKET_FD_ZERO(p)    memset((void*)(p),0,sizeof(*(p)))

  typedef struct {
          unsigned char fd_bits [(OPENAT_SOCKET_FD_SETSIZE+7)/8];
        } openSocketFdSet;

#endif /* FD_SET */


struct openSocketTimeval 
{ 
	int tv_sec; 
	int tv_usec;
};


typedef enum
{
    SOC_SOCK_STREAM = 0,  /* stream socket, TCP */
    SOC_SOCK_DGRAM,       /* datagram socket, UDP */    
    SOC_SOCK_STREAM_SSL, /* TCP SSL*/
    SOC_SOCK_SMS,         /* SMS bearer */
    SOC_SOCK_RAW          /* raw socket */
} openSocketType;


/*+\bug_1768\rww\2020.5.7\cipping不成功*/
typedef enum
{
	SOC_IPPROTO_IP = 0,
	SOC_IPPROTO_ICMP
} openIPProtoType;
/*-\bug_1768\rww\2020.5.7\cipping不成功*/


struct openSocketAddrSin {
  UINT32 s_addr;
};

struct openSocketAddr
{
  UINT8 sin_len;
  UINT8 sin_family;
  UINT16 sin_port;
  struct openSocketAddrSin sin_addr;
  char sin_zero[8];
};
struct openSocketHostent {
    char  *h_name;      /* Official name of the host. */
    char **h_aliases;   /* A pointer to an array of pointers to alternative host names,
                           terminated by a null pointer. */
    int    h_addrtype;  /* Address type. */
    int    h_length;    /* The length, in bytes, of the address. */
    char **h_addr_list; /* A pointer to an array of pointers to network addresses (in
                           network byte order) for the host, terminated by a null pointer. */
};

typedef enum
{
    SOC_EVT_CONNECT,
    SOC_EVT_CLOSE,       
    SOC_EVT_READ,        
    SOC_EVT_WRITE,
    SOC_EVT_CLOSE_IND,
    SOC_EVT_SEND_ACK,
    SOC_EVT_HANDSHAKE,
} openSocketEvent;

/*-\NEW\zhuwangbin\2018.11.27\娣诲姞dns task浣跨敤openat dns鎺ュ彛*/
typedef enum
{
    SOC_DNS_REQ
} openDnsEvent;
/*+\NEW\zhuwangbin\2018.11.27\娣诲姞dns task浣跨敤openat dns鎺ュ彛*/

struct openSocketip_addr {
    UINT32 addr;
};

/*\+new\lijiaodi\2020.2.12\添加域名解析\*/
typedef void (*F_OPENAT_DNS_CB)(const char *name,struct openSocketip_addr *ipaddr, void* param);
/*\-new\lijiaodi\2020.2.12\添加域名解析\*/
typedef void (*F_OPENAT_PDP_CB)(BOOL result);
typedef void (*F_OPENAT_SOC_CB)(int s, openSocketEvent evt, int err, char* data, int len);


BOOL OPENAT_active_pdp(const char* apn, const char* usr, const char* pwd, F_OPENAT_PDP_CB cb);
BOOL OPENAT_deactivate_pdp(void);


INT32 OPENAT_socket_create(openSocketType type, F_OPENAT_SOC_CB cb);
/*+\bug_1768\rww\2020.5.7\cipping不成功*/
INT32 OPENAT_socket_create2(openSocketType type, openIPProtoType proto, F_OPENAT_SOC_CB cb);
/*-\bug_1768\rww\2020.5.7\cipping不成功*/
void OPENAT_Socket_set_cb(int fd, F_OPENAT_SOC_CB cb);


INT32 OPENAT_socket_connect(int fd, struct openSocketAddr* addr, UINT32 addrlen);
INT32 OPENAT_socket_send(int fd, const char* data, size_t len, int flag);

INT32 OPENAT_socket_sendto(int fd, const char* data, size_t len, int flag, struct openSocketAddr* addr, UINT32 addrlen);

INT32 OPENAT_socket_recv(int fd, const char* data, size_t len, int flag);
INT32 OPENAT_socket_recvfrom(int s, void *mem, size_t len, int flags,
      struct openSocketAddr* from, INT32 *fromlen);
void OPENAT_socket_recved(int s, UINT32 len);
INT32 OPENAT_socket_bind(int s, struct openSocketAddr* localaddr, uint8 addrlen);
INT32 OPENAT_socket_setsockopt(int s, int level, int optname, const void *optval, int optlen);

INT32 OPENAT_socket_ioctl(int s, long cmd, void *argp);

INT32 OPENAT_socket_close(int fd);

int OPENAT_socket_error(int s);

INT32 OPENAT_socket_select(int maxfdp1, openSocketFdSet *readset, openSocketFdSet *writeset, openSocketFdSet *exceptset,
                struct openSocketTimeval *timeout);
INT32 OPENAT_socket_getopt(int s, int level, int optname, void *optval, int *optlen);


struct openSocketHostent* OPENAT_socket_gethostbyname(char* name);
void OPENAT_socket_init(void);

UINT32 OPENAT_socket_iptn(const char* ip);


int OPENAT_ssl_create(F_OPENAT_SOC_CB cb);
int OPENAT_ssl_connect(int fd, struct openSocketAddr* addr, UINT32 addrlen);
int OPENAT_ssl_close(int fd);
int OPENAT_ssl_send(int s, const char* data, size_t size);
int OPENAT_ssl_recv(int s, const char* data, size_t size);
void OPENAT_ssl_recved(int s, int len);
int OPENAT_ssl_cret(int s, const char* hostName, const char* serverCaCert, const char* clientCaCert, const char* clientKey);

/*\+new\lijiaodi\2020.2.12\添加域名解析\*/
int OPENAT_socket_gethostbyname_ex(char *name,struct openSocketip_addr* ipaddr, F_OPENAT_DNS_CB dns_cb, void *param);
/*\-new\lijiaodi\2020.2.12\添加域名解析\*/
/*-\NEW\AMOPENAT-54\brezen\2013.7.18\娣诲姞CI鍜孌TE涔嬮棿AT杩囨护鎺ュ彛*/

#endif /* AM_OPENAT_VAT_H */


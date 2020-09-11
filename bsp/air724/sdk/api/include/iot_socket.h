#ifndef __IOT_SOCKET_H__
#define __IOT_SOCKET_H__

#include "am_openat.h"
#include <sys/_timeval.h>

#define OPENAT_INADDR_NONE (0xFFFFFFFF)

#define INVALID_SOCKET  (0xFFFFFFFFL)
#define SOCKET_ERROR    (0xFFFFFFFFL)

/* Flags we can use with send and recv. */
#define MSG_PEEK       0x01    /* Peeks at an incoming message */
#define MSG_WAITALL    0x02    /* Unimplemented: Requests that the function block until the full amount of data requested can be returned */
#define MSG_OOB        0x04    /* Unimplemented: Requests out-of-band data. The significance and semantics of out-of-band data are protocol-specific */
#define MSG_DONTWAIT   0x08    /* Nonblocking i/o for this operation only */
#define MSG_MORE       0x10    /* Sender will send more */
#define MSG_NOSIGNAL   0x20    /* Uninmplemented: Requests not to send the SIGPIPE signal if an attempt to send is made on a stream-oriented socket that is no longer connected. */


struct openat_sockaddr
{
  uint8   sa_len;			/* total length */
  uint8   sa_family;		/* address family */
  uint8   sa_data[14];
};

struct openat_ip_addr {
  uint32 addr;
};

struct openat_in_address{
  uint32 s_addr;
};

/* members are in network byte order */
struct openat_sockaddr_in {
  uint8 sin_len;
  uint8 sin_family;
  uint16 sin_port;
  struct openat_in_address sin_addr;
#define SIN_ZERO_LEN 8
  char sin_zero[SIN_ZERO_LEN];
};

typedef struct openat_ip_addr openat_ip_addr_t;

struct openat_hostent {
    char  *h_name;      /* Official name of the host. */
    char **h_aliases;   /* A pointer to an array of pointers to alternative host names,
                           terminated by a null pointer. */
    int    h_addrtype;  /* Address type. */
    int    h_length;    /* The length, in bytes, of the address. */
    char **h_addr_list; /* A pointer to an array of pointers to network addresses (in
                           network byte order) for the host, terminated by a null pointer. */
#define h_addr h_addr_list[0] /* for backward compatibility */
};

typedef uint32 openat_socklen_t;

struct openat_addrinfo {
    int               ai_flags;      /* Input flags. */
    int               ai_family;     /* Address family of socket. */
    int               ai_socktype;   /* Socket type. */
    int               ai_protocol;   /* Protocol of socket. */
    openat_socklen_t         ai_addrlen;    /* Length of socket address. */
    struct openat_sockaddr  *ai_addr;       /* Socket address of socket. */
    char             *ai_canonname;  /* Canonical name of service location. */
    struct openat_addrinfo  *ai_next;       /* Pointer to next in list. */
};

#ifndef FD_SET
#undef  FD_SETSIZE
#define MEMP_NUM_NETCONN 			8
#define LWIP_SOCKET_OFFSET              1
/* Make FD_SETSIZE match NUM_SOCKETS in socket.c */
#define FD_SETSIZE    MEMP_NUM_NETCONN
#define FDSETSAFESET(n, code) do { \
  if (((n) - LWIP_SOCKET_OFFSET < MEMP_NUM_NETCONN) && (((int)(n) - LWIP_SOCKET_OFFSET) >= 0)) { \
  code; }} while(0)
#define FDSETSAFEGET(n, code) (((n) - LWIP_SOCKET_OFFSET < MEMP_NUM_NETCONN) && (((int)(n) - LWIP_SOCKET_OFFSET) >= 0) ?\
  (code) : 0)
#define FD_SET(n, p)  FDSETSAFESET(n, (p)->fds_bits[((n)-LWIP_SOCKET_OFFSET)/8] |=  (1 << (((n)-LWIP_SOCKET_OFFSET) & 7)))
#define FD_CLR(n, p)  FDSETSAFESET(n, (p)->fds_bits[((n)-LWIP_SOCKET_OFFSET)/8] &= ~(1 << (((n)-LWIP_SOCKET_OFFSET) & 7)))
#define FD_ISSET(n,p) FDSETSAFEGET(n, (p)->fds_bits[((n)-LWIP_SOCKET_OFFSET)/8] &   (1 << (((n)-LWIP_SOCKET_OFFSET) & 7)))
#define FD_ZERO(p)    memset((void*)(p), 0, sizeof(*(p)))

typedef struct fd_set
{
  unsigned char fds_bits [(FD_SETSIZE+7)/8];
} fd_set;

#elif LWIP_SOCKET_OFFSET
#error LWIP_SOCKET_OFFSET does not work with external FD_SET!
#elif FD_SETSIZE < MEMP_NUM_NETCONN
#error "external FD_SETSIZE too small for number of sockets"
#endif /* FD_SET */
#if 0
struct timeval 
{ 
	long long tv_sec; 
	int tv_usec;
};
#endif

/** This is the aligned version of ip6_addr_t,
	used as local variable, on the stack, etc. */
struct ip6_addr {
  uint32 addr[4];
  uint8 zone;
};

/** IPv6 address */
typedef struct ip6_addr ip6_addr_t;

/** This is the aligned version of ip4_addr_t,
   used as local variable, on the stack, etc. */
struct ip4_addr {
  uint32 addr;
};

/** ip4_addr_t uses a struct for convenience only, so that the same defines can
 * operate both on ip4_addr_t as well as on ip4_addr_p_t. */
typedef struct ip4_addr ip4_addr_t;

#define sockaddr_in 			openat_sockaddr_in 
#define hostent 				openat_hostent
#define sockaddr 				openat_sockaddr
#define in_addr 				openat_in_address
#define socklen_t				openat_socklen_t
#define addrinfo				openat_addrinfo
#define OPENAT_FD_SET(n, p)  	FD_SET(n, p)
#define OPENAT_FD_CLR(n, p)  	FD_CLR(n, p)
#define OPENAT_FD_ISSET(n,p) 	FD_ISSET(n,p)
#define OPENAT_FD_ZERO(p)		FD_ZERO(p)
#define openat_fd_set			fd_set
#define openat_timeval 			timeval
#define OPENAT_AF_UNSPEC       0
#define OPENAT_AF_INET         2
#define OPENAT_AI_PASSIVE      0x01
#define OPENAT_AI_CANONNAME    0x02
#define OPENAT_AI_NUMERICHOST  0x04
#define OPENAT_AI_NUMERICSERV  0x08
#define OPENAT_AI_V4MAPPED     0x10
#define OPENAT_AI_ALL          0x20
#define OPENAT_AI_ADDRCONFIG   0x40

#define	PF_INET		OPENAT_AF_INET


#define OPENAT_AF_INET6        10
#define AF_INET         2
#define AF_INET6        10


/* Socket protocol types (TCP/UDP/RAW) */
#define OPENAT_SOCK_STREAM     1
#define OPENAT_SOCK_DGRAM      2
#define OPENAT_SOCK_RAW        3

#define SO_REUSEADDR   0x0004 
#define SO_KEEPALIVE   0x0008 
#define SO_BROADCAST   0x0020

#define  SOL_SOCKET  0xfff

#define SO_DEBUG        0x0001 /* Unimplemented: turn on debugging info recording */
#define SO_ACCEPTCONN   0x0002 /* socket has had listen() */
#define SO_DONTROUTE    0x0010 /* Unimplemented: just use interface addresses */
#define SO_USELOOPBACK  0x0040 /* Unimplemented: bypass hardware when possible */
#define SO_LINGER       0x0080 /* linger on close if data present */
#define SO_DONTLINGER   ((int)(~SO_LINGER))
#define SO_OOBINLINE    0x0100 /* Unimplemented: leave received OOB data in line */
#define SO_REUSEPORT    0x0200 /* Unimplemented: allow local address & port reuse */
#define SO_SNDBUF       0x1001 /* Unimplemented: send buffer size */
#define SO_RCVBUF       0x1002 /* receive buffer size */
#define SO_SNDLOWAT     0x1003 /* Unimplemented: send low-water mark */
#define SO_RCVLOWAT     0x1004 /* Unimplemented: receive low-water mark */
#define SO_SNDTIMEO     0x1005 /* send timeout */
#define SO_RCVTIMEO     0x1006 /* receive timeout */
#define SO_ERROR        0x1007 /* get error status and clear */
#define SO_TYPE         0x1008 /* get socket type */
#define SO_CONTIMEO     0x1009 /* Unimplemented: connect timeout */
#define SO_NO_CHECK     0x100a /* don't create UDP checksum */
#define SO_BINDTODEVICE 0x100b /* bind to device */

/*
 * Options for level IPPROTO_TCP
 */
#define OPENAT_TCP_NODELAY    0x01    /* don't delay send to coalesce packets */
#define OPENAT_TCP_KEEPALIVE  0x02    /* send KEEPALIVE probes when idle for pcb->keep_idle milliseconds */
#define OPENAT_TCP_KEEPIDLE   0x03    /* set pcb->keep_idle  - Same as TCP_KEEPALIVE, but use seconds for get/setsockopt */
#define OPENAT_TCP_KEEPINTVL  0x04    /* set pcb->keep_intvl - Use seconds for get/setsockopt */
#define OPENAT_TCP_KEEPCNT    0x05    /* set pcb->keep_cnt   - Use number of probes sent for get/setsockopt */
#define OPENAT_TCP_TIMEROUT   0x06    /* set pcb->keep_cnt   - Use number of probes sent for get/setsockopt */
#define OPENAT_TCP_MSS_VALUE  0x07    /* set pcb->mss   - Use number of probes only for get/setsockopt */
#define OPENAT_TCP_RTO_VALUE  0x08    /* set pcb->rto   - Use number of probes only for get/setsockopt */
#define OPENAT_TCP_TXB_UNACK  0x09    /* set (pcb->snd_lbb - pcb->lastack) - how much byte remaind in buffer for unacked */
#define OPENAT_TCP_TXB_REST   0x0A    /* set (pcb->snd_buf) - how much byte remaind in tx buffer can writen by app */
#define OPENAT_TCP_TXB_ACKED  0x0B    /* set (pcb->acked_sum) - the number of accumulation of acked */

#define  OPENAT_ERROK         0  /* err ok set, no err happen */
#define  OPENAT_EPERM         1  /* Operation not permitted */
#define  OPENAT_ENOENT        2  /* No such file or directory */
#define  OPENAT_ESRCH         3  /* No such process */
#define  OPENAT_EINTR         4  /* Interrupted system call */
#define  OPENAT_EIO           5  /* I/O error */
#define  OPENAT_ENXIO         6  /* No such device or address */
#define  OPENAT_E2BIG         7  /* Arg list too long */
#define  OPENAT_ENOEXEC       8  /* Exec format error */
#define  OPENAT_EBADF         9  /* Bad file number */
#define  OPENAT_ECHILD       10  /* No child processes */
#define  OPENAT_EAGAIN       11  /* Try again */
#define  OPENAT_ENOMEM       12  /* Out of memory */
#define  OPENAT_EACCES       13  /* Permission denied */
#define  OPENAT_EFAULT       14  /* Bad address */
#define  OPENAT_ENOTBLK      15  /* Block device required */
#define  OPENAT_EBUSY        16  /* Device or resource busy */
#define  OPENAT_EEXIST       17  /* File exists */
#define  OPENAT_EXDEV        18  /* Cross-device link */
#define  OPENAT_ENODEV       19  /* No such device */
#define  OPENAT_ENOTDIR      20  /* Not a directory */
#define  OPENAT_EISDIR       21  /* Is a directory */
#define  OPENAT_EINVAL       22  /* Invalid argument */
#define  OPENAT_ENFILE       23  /* File table overflow */
#define  OPENAT_EMFILE       24  /* Too many open files */
#define  OPENAT_ENOTTY       25  /* Not a typewriter */
#define  OPENAT_ETXTBSY      26  /* Text file busy */
#define  OPENAT_EFBIG        27  /* File too large */
#define  OPENAT_ENOSPC       28  /* No space left on device */
#define  OPENAT_ESPIPE       29  /* Illegal seek */
#define  OPENAT_EROFS        30  /* Read-only file system */
#define  OPENAT_EMLINK       31  /* Too many links */
#define  OPENAT_EPIPE        32  /* Broken pipe */
#define  OPENAT_LWIPEDOM     33  /* Math argument out of domain of func */
#define  OPENAT_LWIPERANGE   34  /* Math result not representable */
#define  OPENAT_EDEADLK      35  /* Resource deadlock would occur */
#define  OPENAT_ENAMETOOLONG 36  /* File name too long */
#define  OPENAT_ENOLCK       37  /* No record locks available */
#define  OPENAT_ENOSYS       38  /* Function not implemented */
#define  OPENAT_ENOTEMPTY    39  /* Directory not empty */
#define  OPENAT_ELOOP        40  /* Too many symbolic links encountered */
#define  OPENAT_EWOULDBLOCK  OPENAT_EAGAIN  /* Operation would block */
#define  OPENAT_ENOMSG       42  /* No message of desired type */
#define  OPENAT_EIDRM        43  /* Identifier removed */
#define  OPENAT_ECHRNG       44  /* Channel number out of range */
#define  OPENAT_EL2NSYNC     45  /* Level 2 not synchronized */
#define  OPENAT_EL3HLT       46  /* Level 3 halted */
#define  OPENAT_EL3RST       47  /* Level 3 reset */
#define  OPENAT_ELNRNG       48  /* Link number out of range */
#define  OPENAT_EUNATCH      49  /* Protocol driver not attached */
#define  OPENAT_ENOCSI       50  /* No CSI structure available */
#define  OPENAT_EL2HLT       51  /* Level 2 halted */
#define  OPENAT_EBADE        52  /* Invalid exchange */
#define  OPENAT_EBADR        53  /* Invalid request descriptor */
#define  OPENAT_EXFULL       54  /* Exchange full */
#define  OPENAT_ENOANO       55  /* No anode */
#define  OPENAT_EBADRQC      56  /* Invalid request code */
#define  OPENAT_EBADSLT      57  /* Invalid slot */

#define  OPENAT_EDEADLOCK    OPENAT_EDEADLK

#define  OPENAT_EBFONT       59  /* Bad font file format */
#define  OPENAT_ENOSTR       60  /* Device not a stream */
#define  OPENAT_ENODATA      61  /* No data available */
#define  OPENAT_ETIME        62  /* Timer expired */
#define  OPENAT_ENOSR        63  /* Out of streams resources */
#define  OPENAT_ENONET       64  /* Machine is not on the network */
#define  OPENAT_ENOPKG       65  /* Package not installed */
#define  OPENAT_EREMOTE      66  /* Object is remote */
#define  OPENAT_ENOLINK      67  /* Link has been severed */
#define  OPENAT_EADV         68  /* Advertise error */
#define  OPENAT_ESRMNT       69  /* Srmount error */
#define  OPENAT_ECOMM        70  /* Communication error on send */
#define  OPENAT_EPROTO       71  /* Protocol error */
#define  OPENAT_EMULTIHOP    72  /* Multihop attempted */
#define  OPENAT_EDOTDOT      73  /* RFS specific error */
#define  OPENAT_EBADMSG      74  /* Not a data message */
#define  OPENAT_EOVERFLOW    75  /* Value too large for defined data type */
#define  OPENAT_ENOTUNIQ     76  /* Name not unique on network */
#define  OPENAT_EBADFD       77  /* File descriptor in bad state */
#define  OPENAT_EREMCHG      78  /* Remote address changed */
#define  OPENAT_ELIBACC      79  /* Can not access a needed shared library */
#define  OPENAT_ELIBBAD      80  /* Accessing a corrupted shared library */
#define  OPENAT_ELIBSCN      81  /* .lib section in a.out corrupted */
#define  OPENAT_ELIBMAX      82  /* Attempting to link in too many shared libraries */
#define  OPENAT_ELIBEXEC     83  /* Cannot exec a shared library directly */
#define  OPENAT_LWIPEILSEQ   84  /* Illegal byte sequence */
#define  OPENAT_ERESTART     85  /* Interrupted system call should be restarted */
#define  OPENAT_ESTRPIPE     86  /* Streams pipe error */
#define  OPENAT_EUSERS       87  /* Too many users */
#define  OPENAT_ENOTSOCK     88  /* Socket operation on non-socket */
#define  OPENAT_EDESTADDRREQ 89  /* Destination address required */
#define  OPENAT_EMSGSIZE     90  /* Message too long */
#define  OPENAT_EPROTOTYPE   91  /* Protocol wrong type for socket */
#define  OPENAT_ENOPROTOOPT  92  /* Protocol not available */
#define  OPENAT_EPROTONOSUPPORT 93  /* Protocol not supported */
#define  OPENAT_ESOCKTNOSUPPORT 94  /* Socket type not supported */
#define  OPENAT_EOPNOTSUPP      95  /* Operation not supported on transport endpoint */
#define  OPENAT_EPFNOSUPPORT    96  /* Protocol family not supported */
#define  OPENAT_EAFNOSUPPORT    97  /* Address family not supported by protocol */
#define  OPENAT_EADDRINUSE      98  /* Address already in use */
#define  OPENAT_EADDRNOTAVAIL   99  /* Cannot assign requested address */
#define  OPENAT_ENETDOWN       100  /* Network is down */
#define  OPENAT_ENETUNREACH    101  /* Network is unreachable */
#define  OPENAT_ENETRESET      102  /* Network dropped connection because of reset */
#define  OPENAT_ECONNABORTED   103  /* Software caused connection abort */
#define  OPENAT_ECONNRESET     104  /* Connection reset by peer */
#define  OPENAT_ENOBUFS        105  /* No buffer space available */
#define  OPENAT_EISCONN        106  /* Transport endpoint is already connected */
#define  OPENAT_ENOTCONN       107  /* Transport endpoint is not connected */
#define  OPENAT_ESHUTDOWN      108  /* Cannot send after transport endpoint shutdown */
#define  OPENAT_ETOOMANYREFS   109  /* Too many references: cannot splice */
#define  OPENAT_ETIMEDOUT      110  /* Connection timed out */
#define  OPENAT_ECONNREFUSED   111  /* Connection refused */
#define  OPENAT_EHOSTDOWN      112  /* Host is down */
#define  OPENAT_EHOSTUNREACH   113  /* No route to host */
#define  OPENAT_EALREADY       114  /* Operation already in progress */
#define  OPENAT_EINPROGRESS    115  /* Operation now in progress */
#define  OPENAT_ESTALE         116  /* Stale NFS file handle */
#define  OPENAT_EUCLEAN        117  /* Structure needs cleaning */
#define  OPENAT_ENOTNAM        118  /* Not a XENIX named type file */
#define  OPENAT_ENAVAIL        119  /* No XENIX semaphores available */
#define  OPENAT_EISNAM         120  /* Is a named type file */
#define  OPENAT_EREMOTEIO      121  /* Remote I/O error */
#define  OPENAT_EDQUOT         122  /* Quota exceeded */

#define  OPENAT_ENOMEDIUM      123  /* No medium found */
#define  OPENAT_EMEDIUMTYPE    124  /* Wrong medium type */

char *ip6addr_ntoa_r(const ip6_addr_t *addr, char *buf, int buflen);
char*ip4addr_ntoa_r(const ip4_addr_t *addr, char *buf, int buflen);
int ip6addr_aton(const char *cp, ip6_addr_t *addr);
int ip4addr_aton(const char *cp, ip4_addr_t *addr);

/**
 * @defgroup iot_sdk_socket socket接口
 * @{
 */
/**@example socket/demo_socket.c
* socket接口示例
*/
/**创建socket
*@param		domain:		仅支持AF_INET (IPV4 网络协议)
@param		type:		支持SOCK_STREAM/SOCK_DGRAM，分别表示TCP、UDP连接
@param		protocol:   仅支持0


*@return	>=0: 	    socket描述符，用于后续操作
*           <0:         创建socket失败
*@note      创建的socket不用后需要用close将其关闭
**/

int socket(int domain, int type, int protocol);
/**获取域名对应的IP地址
*@param		name:		域名，例如:www.airm2m.com/www.baidu.com
*@return	struct hostent 结构体: 该结构体包含了一个DNS域名解析后的ip地址
*           NULL:  域名解析失败
**/                       
struct hostent* gethostbyname(const char *name);
/**关闭socket
*@param		fd:	调用socket接口返回的socket描述符
*@return	0:  表示成功
            -1  表示有错误
*           
**/                          
int close (int fd);
/**设置socket的属性
*@param		socketfd:	调用socket接口返回的socket描述符
@param      level: 支持SOL_SOCKET/IPPROTO_TCP
@param      optname:  SOL_SOCKET对应optname为 SO_DEBUG/SO_OOBINLINE/SO_SNDTIMEO/SO_RCVTIMEO/SO_RCVBUF/SO_SNDBUF
                      IPPROTO_TCP对应optname为 SO_TCP_SACKDISABLE/SO_TCP_NODELAY
@param      optval_p:
@param      optlen:
*@return	0:  表示成功
            <0  表示有错误
*
**/          

int setsockopt(int socketfd, 
                        int level, 
                        int optname,
                        void *optval_p, 
                        openat_socklen_t optlen);
/**获取socket的属性
*@param   socketfd: 调用socket接口返回的socket描述符
@param      level: 支持SOL_SOCKET/IPPROTO_TCP
@param      optname:  SOL_SOCKET对应optname为 SO_DEBUG/SO_OOBINLINE/SO_SNDTIMEO/SO_RCVTIMEO/SO_RCVBUF/SO_SNDBUF
                      IPPROTO_TCP对应optname为 SO_TCP_SACKDISABLE/SO_TCP_NODELAY
@param      optval_p:
@param      optlen_p:
*@return  0:  表示成功
            <0  表示有错误
*
**/          

int getsockopt(int socketfd, 
                        int level, 
                        int optname,
                        void *optval_p, 
                        openat_socklen_t* optlen_p);
/**设置socket的本地端口和ip地址，一般针对服务器代码需要设置
*@param		socketfd:	调用socket接口返回的socket描述符
@param      my_addr:   ip地址和端口，ip一般设置INADDR_ANY
@param      addrlen:  地址长度
*@return	0:  表示成功
            <0  表示有错误
*           
**/                         
int bind(int socketfd, 
                      const struct openat_sockaddr *my_addr, 
                      openat_socklen_t addrlen);
/**建立和服务器端的连接
*@param		socketfd:	调用socket接口返回的socket描述符
@param      addr:   指定服务器地址和端口
@param      addrlen:  sizeof(struct openat_sockaddr)
*@return	0:  表示成功
            <0  表示有错误
*           
**/                                      
int connect(int socketfd, const struct openat_sockaddr *addr, openat_socklen_t addrlen);
/**监听socket连接，一般用作服务器监听客户端的连接
*@param		socketfd:	调用socket接口返回的socket描述符
@param      backlog:   0
*@return	0:  表示成功
            <0  表示有错误
*           
**/                             
int listen(int socketfd, 
                       int backlog);
/**等待连接，一般用于listen之后等待客户端的连接
*@param		socketfd:	调用socket接口返回的socket描述符
@param      addr:   返回客户端ip地址和端口
@param      addrlen: 返回地址长度
*@return	0:  表示成功
            <0  表示有错误
*@note      函数会一直阻塞，知道有客户端连接           
**/                             
int accept(int socketfd, 
                        struct openat_sockaddr *addr, 
                        openat_socklen_t *addrlen);
/**接收数据
*@param		socketfd:	调用socket接口返回的socket描述符
@param      buf:   用于存放数据的缓存
@param      len:   buf的长度
@param      flags: 仅支持MSG_DONTWAIT/MSG_PEEK/MSG_OOB，可以通过或来指定多个标志，一般为0

*@return	>0:  接收到的数据长度
            =0:  对方已经断开连接
            <0:  读取错误
*@note      当flags没有设置MSG_DONTWAIT，该函数会阻塞，直到有数据或者读取超时
**/                                        
int recv(int socketfd, 
                      void *buf, 
                      size_t len,
                      int flags);
/**接收指定ip地址发送来的数据，一般用于UDP收取数据
*@param		sockfd:	调用socket接口返回的socket描述符
@param      buf:   用于存放数据的缓存
@param      len:   buf的长度
@param      flags: 仅支持0
@param      src_addr: ip地址和端口
@param      addrlen: sizeof(struct openat_sockaddr)

*@return	>0: 实际收到的数据长度
            =0:  对方已经断开连接
            <0:  读取错误
**/   

int recvfrom(int sockfd, void *buf, size_t len, int flags,
                    struct openat_sockaddr *src_addr, openat_socklen_t *addrlen);
/**发送数据
*@param		socketfd:	调用socket接口返回的socket描述符
@param      msg:   数据内容
@param      len:   数据长度
@param      flags: 仅支持MSG_DONTWAIT/MSG_OOB，可以通过或来指定多个标志，一般为0

*@return	>=0:  实际发送的长度
            <0: 发送错误
**/   

int send(int socketfd,
                      const void *msg,
                      size_t len,
                      int flags);
/**发送数据到指定ip地址，一般用于udp发送数据
*@param		socketfd:	调用socket接口返回的socket描述符
@param      buf:   数据内容
@param      len:   数据长度
@param      flags: 仅支持0
@param      to_p: 指定ip地址和端口号
@param      tolen: sizeof(struct openat_sockaddr)

*@return	>=0:  实际发送的长度
            <0:  发送错误
**/                        
int sendto(int socketfd,
                        const void *buf,
                        size_t len,
                        int flags,
                        const struct openat_sockaddr *to_p, 
                        openat_socklen_t tolen);
/**阻塞方式等待socket连接的状态
*@param		maxfdp1:	最大socketfd+1
@param      readset:   读取集合，可以为NULL
@param      writeset:  写集合，可以为NULL
@param      exceptset: 异常集合，可以为NULL
@param      timeout: 超时时间

*@return	0:   等待超时
            >0:  readset+writeset+exceptset的集合个数
            <0  -1
**/                 
int select(int maxfdp1, 
                        openat_fd_set *readset,
                        openat_fd_set *writeset,
                        openat_fd_set *exceptset,
                        struct openat_timeval *timeout);

/**获取socket的错误值
*@param		socketfd:	调用socket接口返回的socket描述符
*@return	[EBADF 到 ENO_RECOVERY]
**/                                       
int socket_errno(int socketfd);

/**设备驱动程序中设备控制接口
*@param		socketfd:	调用socket接口返回的socket描述符
@param      cmd:   	指令，如某一个命令对应驱动层的某一个功能
@param      argp:   可变参数，跟命令有关，传递进入驱动层的参数或者是接收数据的缓存
*@return	>=0:  实际发送的长度
            <0:  发送错误
**/
int	ioctl(int socketfd, long cmd, void *argp);

/**获取一个描述符的名字
*@param		socketfd:	调用socket接口返回的socket描述符
@param      name:   	描述符的名字
@param      namelen:   	描述符的名字长度
*@return	0:  表示成功
            <0  表示有错误
**/
int getsockname (int socketfd, struct openat_sockaddr *name, openat_socklen_t *namelen);

/**主机名到地址解析
*@param		nodename:	一个主机名或者地址串
@param      servname:   服务名可以是十进制的端口号，也可以是已定义的服务名称
@param      hints:   	可以是一个空指针，也可以是一个指向某个openat_addrinfo结构体的指针
@param      res: 		通过res指针参数返回一个指向openat_addrinfo结构体链表的指针

*@return	>=0:  实际发送的长度
            <0:  发送错误
*@note      仅仅支持IPv4，且不允许调用者指定所需地址类型的任何信息，
			返回的结构只包含了用于存储IPv4地址的空间
**/
int getaddrinfo(const char *nodename,
       const char *servname,
       const struct openat_addrinfo *hints,
       struct openat_addrinfo **res);

/**存储空间通过调用freeaddrinfo 返还给系统
*@param		ai:	指向由getaddrinfo返回的第一个openat_addrinfo结构
*
**/
void freeaddrinfo(struct openat_addrinfo *ai);

/**将IP地址由“点分十进制”转换“二进制整数”
*@param		af: 地址簇
*@param		src: 源地址
*@param		dst: 接收转换后的数据
*@param		size: 缓存区dst的大小
*@return	>0: 成功
            <=0: 失败
**/ 
#define inet_ntop(af,src,dst,size) \
    (((af) == AF_INET6) ? ip6addr_ntoa_r((const ip6_addr_t*)(src),(dst),(size)) \
     : (((af) == AF_INET) ? ip4addr_ntoa_r((const ip4_addr_t*)(src),(dst),(size)) : NULL))

/**将IP地址由“二进制整数”转换“点分十进制”
*@param 	af: 地址簇
*@param 	src: 源地址
*@param 	dst: 接收转换后的数据
*@return	>0: 成功
			<=0: 失败
**/ 
#define inet_pton(af,src,dst) \
    (((af) == AF_INET6) ? ip6addr_aton((src),(ip6_addr_t*)(dst)) \
     : (((af) == AF_INET) ? ip4addr_aton((src),(ip4_addr_t*)(dst)) : 0))


/**本地字节顺序转化为网络字节顺序(16bits)
*@param		n: 本地字节书序数据
*@return	网络字节顺序数据
**/                 
#define htons(n) 				((n & 0xff) << 8) | ((n & 0xff00) >> 8)
/**本地字节顺序转化为网络字节顺序(32bits)
*@param		n: 本地字节书序数据
*@return	网络字节顺序数据
**/           
#define htonl(n) 				((n & 0xff) << 24) |\
                                    ((n & 0xff00) << 8) |\
                                ((n & 0xff0000UL) >> 8) |\
                                    ((n & 0xff000000UL) >> 24)
/**网络字节顺序转化为本地字节顺序(16bits)
*@param		n: 网络字节顺序
*@return	本地字节顺序
**/                                           
#define ntohs(n) 				htons(n)
/**网络字节顺序转化为本地字节顺序(32bits)
*@param		n: 网络字节顺序
*@return	本地字节顺序
**/
#define ntohl(n) 				htonl(n)

/**将ip地址字符串转为数值，转化后的数值为网络字节顺序
*@param		cp: ip地址字符串，例如"192.168.1.1"
*@param		addr: struct in_addr 返回的ip地址数值
*@return    1: 成功
            0: 失败
**/ 
#define inet_aton(cp, addr)   ipaddr_aton(cp, (openat_ip_addr_t*)addr)

/**将ip地址数值(网络字节顺序)，转化为ip地址字符串
*@param		addr: struct in_addr ip地址数值
*@return	ip地址字符串
**/ 
#define inet_ntoa(addr)       ipaddr_ntoa((openat_ip_addr_t*)&(addr))

/**
 * Check whether "cp" is a valid ascii representation
 * of an Internet address and convert to a binary address.
 * Returns 1 if the address is valid, 0 if not.
 * This replaces inet_addr, the return value from which
 * cannot distinguish between failure and a local broadcast address.
 *
 * @param cp IP address in ascii represenation (e.g. "127.0.0.1")
 * @param addr pointer to which to save the ip address in network order
 * @return 1 if cp could be converted to addr, 0 on failure
 */
int
ipaddr_aton(const char *cp, openat_ip_addr_t *addr);

/**
 * Ascii internet address interpretation routine.
 * The value returned is in network order.
 *
 * @param cp IP address in ascii represenation (e.g. "127.0.0.1")
 * @return ip address in network order
 */
UINT32
ipaddr_addr(const char *cp);

/**
 * Same as ipaddr_ntoa, but reentrant since a user-supplied buffer is used.
 *
 * @param addr ip address in network order to convert
 * @param buf target buffer where the string is stored
 * @param buflen length of buf
 * @return either pointer to buf which now holds the ASCII
 *         representation of addr or NULL if buf was too small
 */
char *ipaddr_ntoa_r(const openat_ip_addr_t *addr, char *buf, int buflen);

/**
 * Convert numeric IP address into decimal dotted ASCII representation.
 * returns ptr to static buffer; not reentrant!
 *
 * @param addr ip address in network order to convert
 * @return pointer to a global static (!) buffer that holds the ASCII
 *         represenation of addr
 */
char *
ipaddr_ntoa(const openat_ip_addr_t *addr);

/** @}*/

#endif


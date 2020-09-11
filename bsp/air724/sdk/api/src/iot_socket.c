#include "iot_socket.h"
#include "errno.h"
extern UINT32 CFW_TcpipGetLastError(void);
int lwip_accept(int s, struct sockaddr *addr, socklen_t *addrlen);
int lwip_bind(int s, const struct sockaddr *name, socklen_t namelen);
int lwip_getsockopt (int s, int level, int optname, void *optval, socklen_t *optlen);
int lwip_setsockopt (int s, int level, int optname, const void *optval, socklen_t optlen);
 int lwip_close(int s);
int lwip_connect(int s, const struct sockaddr *name, socklen_t namelen);
int lwip_listen(int s, int backlog);
ssize_t lwip_recv(int s, void *mem, size_t len, int flags);
ssize_t lwip_recvfrom(int s, void *mem, size_t len, int flags,
      struct sockaddr *from, socklen_t *fromlen);
ssize_t lwip_send(int s, const void *dataptr, size_t size, int flags);
ssize_t lwip_sendto(int s, const void *dataptr, size_t size, int flags,
    const struct sockaddr *to, socklen_t tolen);
int lwip_socket(int domain, int type, int protocol);
int lwip_select(int maxfdp1, fd_set *readset, fd_set *writeset, fd_set *exceptset,
                struct timeval *timeout);
struct hostent *lwip_gethostbyname(const char *name);
int lwip_ioctl(int s, long cmd, void *argp);
int lwip_getsockname (int s, struct sockaddr *name, socklen_t *namelen);
int lwip_getaddrinfo(const char *nodename,
       const char *servname,
       const struct addrinfo *hints,
       struct addrinfo **res);
void lwip_freeaddrinfo(struct addrinfo *ai);



/**创建socket
*@param		domain:		仅支持AF_INET (IPV4 网络协议)
@param		type:		支持SOCK_STREAM/SOCK_DGRAM，分别表示TCP、UDP连接
@param		protocol:   仅支持0


*@return	>=0: 	    socket描述符，用于后续操作
*           <0:         创建socket失败
*@note      创建的socket不用后需要用close将其关闭
**/

int socket(int domain, int type, int protocol)
{
    return lwip_socket(domain, type, protocol);
}
/**获取域名对应的IP地址
*@param		name:		域名，例如:www.airm2m.com/www.baidu.com
*@return	struct hostent 结构体: 该结构体包含了一个DNS域名解析后的ip地址
*           NULL:  域名解析失败
**/                       
struct hostent* gethostbyname(const char *name)
{
    return lwip_gethostbyname(name);
}
/**关闭socket
*@param		fd:	调用socket接口返回的socket描述符
*@return	0:  表示成功
            -1  表示有错误
*           
**/                          
int close (int fd)
{
    return lwip_close(fd);
}
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
                        openat_socklen_t optlen)
{
    return lwip_setsockopt(socketfd, level, optname, optval_p, optlen);
}                 

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
                        openat_socklen_t* optlen_p)
{
    return lwip_getsockopt(socketfd, level, optname, optval_p, optlen_p);
}       
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
                      openat_socklen_t addrlen)
{
    return lwip_bind(socketfd, my_addr, addrlen);
}                      
/**建立和服务器端的连接
*@param		socketfd:	调用socket接口返回的socket描述符
@param      addr:   指定服务器地址和端口
@param      addrlen:  sizeof(struct openat_sockaddr)
*@return	0:  表示成功
            <0  表示有错误
*           
**/                                      
int connect(int socketfd, const struct openat_sockaddr *addr, openat_socklen_t addrlen)
{
    return lwip_connect(socketfd, addr, addrlen);
}
/**监听socket连接，一般用作服务器监听客户端的连接
*@param		socketfd:	调用socket接口返回的socket描述符
@param      backlog:   0
*@return	0:  表示成功
            <0  表示有错误
*           
**/                             
int listen(int socketfd, 
                       int backlog)

{
    return lwip_listen(socketfd, backlog);
}
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
                        openat_socklen_t *addrlen)
{
    return lwip_accept(socketfd, addr, addrlen);
}
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
                      int flags)
{
    return lwip_recv(socketfd, buf, len, flags);
}                      
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
                    struct openat_sockaddr *src_addr, openat_socklen_t *addrlen)
{
    return lwip_recvfrom(sockfd, buf, len, flags, src_addr, addrlen);
}
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
                      int flags)
{
    return lwip_send(socketfd, msg, len, flags);
}                      
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
                        openat_socklen_t tolen)
{
    return lwip_sendto(socketfd, buf, len, flags, to_p, tolen);
}
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
                        struct openat_timeval *timeout)
{
    return lwip_select(maxfdp1, readset, writeset, exceptset, timeout);
}
/**获取socket的错误值
*@param		socketfd:	调用socket接口返回的socket描述符
*@return	[EBADF 到 ENO_RECOVERY]
**/                                       
int socket_errno(int socketfd)
{
    return (int)CFW_TcpipGetLastError();
}

/**设备驱动程序中设备控制接口
*@param		socketfd:	调用socket接口返回的socket描述符
@param      cmd:   	指令，如某一个命令对应驱动层的某一个功能
@param      argp:   可变参数，跟命令有关，传递进入驱动层的参数或者是接收数据的缓存
*@return	>=0:  实际发送的长度
            <0:  发送错误
**/
int	ioctl(int socketfd, long cmd, void *argp)
{
	return lwip_ioctl(socketfd, cmd, argp);
}

/**获取一个描述符的名字
*@param		socketfd:	调用socket接口返回的socket描述符
@param      name:   	描述符的名字
@param      namelen:   	描述符的名字长度
*@return	0:  表示成功
            <0  表示有错误
**/
int getsockname (int socketfd, struct openat_sockaddr *name, openat_socklen_t *namelen)
{
	return lwip_getsockname(socketfd,name,namelen);
}

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
       struct openat_addrinfo **res)
{
	return lwip_getaddrinfo(nodename, servname, hints, res);
}

/**存储空间通过调用freeaddrinfo 返还给系统
*@param		ai:	指向由getaddrinfo返回的第一个openat_addrinfo结构
*
**/
void freeaddrinfo(struct openat_addrinfo *ai)
{
	lwip_freeaddrinfo(ai);
}

/******************************
*function: setNetifDns
*input:
*       CHAR* dns1, the value string, like 8.8.8.8
*       CHAR* dns2, the value string, like 8.8.8.8
*output:
*       0, if success full
*       -1, if failed
********************************/

int setNetifDns(CHAR *dns1, CHAR *dns2)
{
	//return IVTBL(setNetifDns)(dns1, dns2);
	return -1;
}

/******************************
*function: getNetifDns
*input:
*       CHAR* dns1, the value string, like 8.8.8.8
*       CHAR* dns2, the value string, like 8.8.8.8
*output:
*       0, if success full
*       -1, if failed
********************************/

int getNetifDns(CHAR *dns1, CHAR *dns2)
{
	//return IVTBL(getNetifDns)(dns1, dns2);
	return -1;
}


/* Here for now until needed in other places in lwIP */
#ifndef isprint
#define in_range(c, lo, up)  ((UINT8)c >= lo && (UINT8)c <= up)
#define isprint(c)           in_range(c, 0x20, 0x7f)
#define isdigit(c)           in_range(c, '0', '9')
#define isxdigit(c)          (isdigit(c) || in_range(c, 'a', 'f') || in_range(c, 'A', 'F'))
#define islower(c)           in_range(c, 'a', 'z')
#define isspace(c)           (c == ' ' || c == '\f' || c == '\n' || c == '\r' || c == '\t' || c == '\v')
#endif



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
ipaddr_aton(const char *cp, openat_ip_addr_t *addr)
{
  UINT32 val;
  UINT8 base;
  char c;
  UINT32 parts[4];
  UINT32 *pp = parts;

  c = *cp;
  for (;;) {
    /*
     * Collect number up to ``.''.
     * Values are specified as for C:
     * 0x=hex, 0=octal, 1-9=decimal.
     */
    if (!isdigit(c))
      return (0);
    val = 0;
    base = 10;
    if (c == '0') {
      c = *++cp;
      if (c == 'x' || c == 'X') {
        base = 16;
        c = *++cp;
      } else
        base = 8;
    }
    for (;;) {
      if (isdigit(c)) {
        val = (val * base) + (int)(c - '0');
        c = *++cp;
      } else if (base == 16 && isxdigit(c)) {
        val = (val << 4) | (int)(c + 10 - (islower(c) ? 'a' : 'A'));
        c = *++cp;
      } else
        break;
    }
    if (c == '.') {
      /*
       * Internet format:
       *  a.b.c.d
       *  a.b.c   (with c treated as 16 bits)
       *  a.b (with b treated as 24 bits)
       */
      if (pp >= parts + 3) {
        return (0);
      }
      *pp++ = val;
      c = *++cp;
    } else
      break;
  }
  /*
   * Check for trailing characters.
   */
  if (c != '\0' && !isspace(c)) {
    return (0);
  }
  /*
   * Concoct the address according to
   * the number of parts specified.
   */
  switch (pp - parts + 1) {

  case 0:
    return (0);       /* initial nondigit */

  case 1:             /* a -- 32 bits */
    break;

  case 2:             /* a.b -- 8.24 bits */
    if (val > 0xffffffUL) {
      return (0);
    }
    val |= parts[0] << 24;
    break;

  case 3:             /* a.b.c -- 8.8.16 bits */
    if (val > 0xffff) {
      return (0);
    }
    val |= (parts[0] << 24) | (parts[1] << 16);
    break;

  case 4:             /* a.b.c.d -- 8.8.8.8 bits */
    if (val > 0xff) {
      return (0);
    }
    val |= (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8);
    break;
  default:
    return 0;
    break;
  }
  if (addr) {
    addr->addr = htonl(val);
  }
  return (1);
}

/**
 * Ascii internet address interpretation routine.
 * The value returned is in network order.
 *
 * @param cp IP address in ascii represenation (e.g. "127.0.0.1")
 * @return ip address in network order
 */
UINT32
ipaddr_addr(const char *cp)
{
  openat_ip_addr_t val;

  if (ipaddr_aton(cp, &val)) {
    return val.addr;
  }
  return (OPENAT_INADDR_NONE);
}

/**
 * Same as ipaddr_ntoa, but reentrant since a user-supplied buffer is used.
 *
 * @param addr ip address in network order to convert
 * @param buf target buffer where the string is stored
 * @param buflen length of buf
 * @return either pointer to buf which now holds the ASCII
 *         representation of addr or NULL if buf was too small
 */
char *ipaddr_ntoa_r(const openat_ip_addr_t *addr, char *buf, int buflen)
{
  UINT32 s_addr;
  char inv[3];
  char *rp;
  UINT8 *ap;
  UINT8 rem;
  UINT8 n;
  UINT8 i;
  int len = 0;

  s_addr = addr->addr;

  rp = buf;
  ap = (UINT8 *)&s_addr;
  for(n = 0; n < 4; n++) {
    i = 0;
    do {
      rem = *ap % (UINT8)10;
      *ap /= (UINT8)10;
      inv[i++] = '0' + rem;
    } while(*ap);
    while(i--) {
      if (len++ >= buflen) {
        return NULL;
      }
      *rp++ = inv[i];
    }
    if (len++ >= buflen) {
      return NULL;
    }
    *rp++ = '.';
    ap++;
  }
  *--rp = 0;
  return buf;
}

/**
 * Convert numeric IP address into decimal dotted ASCII representation.
 * returns ptr to static buffer; not reentrant!
 *
 * @param addr ip address in network order to convert
 * @return pointer to a global static (!) buffer that holds the ASCII
 *         represenation of addr
 */
char *
ipaddr_ntoa(const openat_ip_addr_t *addr)
{
  static char str[16];
  return ipaddr_ntoa_r(addr, str, 16);
}




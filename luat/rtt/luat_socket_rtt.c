
#include "luat_socket.h"
#include "luat_msgbus.h"

#include "rtthread.h"

#ifdef SAL_USING_POSIX

#include <sys/socket.h> 
#include <netdb.h>

#define SAL_TLS_HOST    "site0.cn"
#define SAL_TLS_PORT    80
#define SAL_TLS_BUFSZ   1024

#define DBG_TAG           "luat.socket"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>

#ifdef PKG_NETUTILS_NTP
#include "ntp.h"
static int socket_ntp_handler(lua_State *L, void* ptr) {
    lua_getglobal(L, "sys_pub");
    if (!lua_isnil(L, -1)) {
        lua_pushstring(L, "NTP_UPDATE");
        lua_call(L, 1, 0);
    }
    // 给rtos.recv方法返回个空数据
    lua_pushinteger(L, 0);
    return 1;
}
static void ntp_thread(void* params) {
    time_t cur_time = ntp_sync_to_rtc((const char*)params);
    rtos_msg_t msg;
    msg.handler = socket_ntp_handler;
    msg.ptr = NULL;
    luat_msgbus_put(&msg, 1);
    LOG_D("ntp sync complete");
}

int luat_socket_ntp_sync(const char* hostname) {
    LOG_D("ntp sync : %s", hostname);
    rt_thread_t t = rt_thread_create("ntpdate", ntp_thread, (void*)hostname, 1536, 26, 2);
    if (t) {
        if (rt_thread_startup(t)) {
            return 2;
        }
        else {
            return 0;
        }
    }
    else {
        return 1;
    }
    return 1;
}
#else
int l_socket_ntp_sync(const char* hostname) {
    return -1;
}
#endif
int luat_socket_tsend(const char* hostname, int port, void* buff, int len)
{
    int ret, i;
    // char *recv_data;
    struct hostent *host;
    int sock = -1, bytes_received;
    struct sockaddr_in server_addr;

    // 强制GC一次先
    //lua_gc(L, LUA_GCCOLLECT, 0);

    /* 通过函数入口参数url获得host地址（如果是域名，会做域名解析） */
    host = gethostbyname(hostname);

    /* 创建一个socket，类型是SOCKET_STREAM，TCP 协议, TLS 类型 */
    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0)
    {
        rt_kprintf("Socket error\n");
        goto __exit;
    }

    /* 初始化预连接的服务端地址 */
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(port);
    server_addr.sin_addr = *((struct in_addr *)host->h_addr);
    rt_memset(&(server_addr.sin_zero), 0, sizeof(server_addr.sin_zero));

    if (connect(sock, (struct sockaddr *)&server_addr, sizeof(struct sockaddr)) < 0)
    {
        rt_kprintf("Connect fail!\n");
        goto __exit;
    }

    /* 发送数据到 socket 连接 */
    ret = send(sock, buff, len, 0);
    if (ret <= 0)
    {
        rt_kprintf("send error,close the socket.\n");
        goto __exit;
    }

__exit:
    // if (recv_data)
    //     rt_free(recv_data);

    if (sock >= 0)
        closesocket(sock);
    return 0;
}

#include <arpa/inet.h>         /* 包含 ip_addr_t 等地址相关的头文件 */
#include <netdev.h>            /* 包含全部的 netdev 相关操作接口函数 */

int luat_socket_is_ready(void) {
    struct netdev *net = RT_NULL;
    net = netdev_get_first_by_flags(NETDEV_FLAG_INTERNET_UP);
    if (net == RT_NULL)
        return 0;
    return 1;
}

uint32_t luat_socket_selfip(void) {
    struct netdev *net = netdev_get_first_by_flags(NETDEV_FLAG_INTERNET_UP);
    if (net == RT_NULL)
        return 0;
    return net->ip_addr.addr;
}

#endif

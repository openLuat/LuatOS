
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

#include <rtthread.h>

#ifdef SAL_USING_POSIX

#include <sys/socket.h> 
#include <netdb.h>

#define SAL_TLS_HOST    "site0.cn"
#define SAL_TLS_PORT    80
#define SAL_TLS_BUFSZ   1024

//static const char *send_data = "GET /download/rt-thread.txt HTTP/1.1\r\n"
//    "Host: www.rt-thread.org\r\n"
//    "User-Agent: rtthread/4.0.1 rtt\r\n\r\n";

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
}
static int socket_ntp_sync(lua_State *L) {
    const char* hostname = luaL_optstring(L, 1, "ntp1.aliyun.com");
    rt_thread_t t = rt_thread_create("ntpdate", ntp_thread, (void*)hostname, 256, 25, 10);
    if (t) {
        if (rt_thread_startup(t)) {
            lua_pushinteger(L, 2);
        }
        else {
            lua_pushinteger(L, 0);
        }
    }
    else {
        lua_pushinteger(L, 1);
    }
    return 1;
}
#endif

static int sal_tls_test(lua_State *L)
{
    int ret, i;
    // char *recv_data;
    struct hostent *host;
    int sock = -1, bytes_received;
    struct sockaddr_in server_addr;

    // 强制GC一次先
    lua_gc(L, LUA_GCCOLLECT, 0);

    /* 通过函数入口参数url获得host地址（如果是域名，会做域名解析） */
    host = gethostbyname(luaL_checkstring(L, 1));

    // recv_data = rt_calloc(1, SAL_TLS_BUFSZ);
    // if (recv_data == RT_NULL)
    // {
    //     rt_kprintf("No memory\n");
    //     return;
    // }

    /* 创建一个socket，类型是SOCKET_STREAM，TCP 协议, TLS 类型 */
    if ((sock = socket(AF_INET, SOCK_STREAM, 0)) < 0)
    {
        rt_kprintf("Socket error\n");
        goto __exit;
    }

    /* 初始化预连接的服务端地址 */
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(luaL_checkinteger(L, 2));
    server_addr.sin_addr = *((struct in_addr *)host->h_addr);
    rt_memset(&(server_addr.sin_zero), 0, sizeof(server_addr.sin_zero));

    if (connect(sock, (struct sockaddr *)&server_addr, sizeof(struct sockaddr)) < 0)
    {
        rt_kprintf("Connect fail!\n");
        goto __exit;
    }

    /* 发送数据到 socket 连接 */
    const char *send_data = luaL_checkstring(L, 3);
    ret = send(sock, send_data, rt_strlen(send_data), 0);
    if (ret <= 0)
    {
        rt_kprintf("send error,close the socket.\n");
        goto __exit;
    }

    /* 接收并打印响应的数据，使用加密数据传输 */
    // bytes_received = recv(sock, recv_data, SAL_TLS_BUFSZ  - 1, 1000);
    // if (bytes_received <= 0)
    // {
    //     rt_kprintf("received error,close the socket.\n");
    //     goto __exit;
    // }

    // rt_kprintf("recv data:\n");
    // for (i = 0; i < bytes_received; i++)
    // {
    //     rt_kprintf("%c", recv_data[i]);
    // }

__exit:
    // if (recv_data)
    //     rt_free(recv_data);

    if (sock >= 0)
        closesocket(sock);
}


#include "rotable.h"
static const rotable_Reg reg_socket[] =
{
    { "tsend" ,  sal_tls_test , 0},
    #ifdef PKG_NETUTILS_NTP
    { "ntpSync", socket_ntp_sync, 0},
    #endif
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_socket( lua_State *L ) {
    rotable_newlib(L, reg_socket);
    return 1;
}

#endif
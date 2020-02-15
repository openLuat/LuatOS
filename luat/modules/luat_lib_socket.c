
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

#define DBG_TAG           "luat.socket"
#define DBG_LVL           DBG_INFO
#include <rtdbg.h>


#define LUAT_NETC_HANDLE "NETC*"

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
static int socket_ntp_sync(lua_State *L) {
    const char* hostname = luaL_optstring(L, 1, "ntp1.aliyun.com");
    LOG_D("ntp sync : %s", hostname);
    rt_thread_t t = rt_thread_create("ntpdate", ntp_thread, (void*)hostname, 1536, 26, 2);
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

#include "netclient.h"

static int luat_lib_socket_new(lua_State* L, int netc_type);
static int luat_lib_socket_ent_handler(rt_netc_ent_t ent) {
    LOG_I("netc event type=%d", ent.event);
    switch (ent.event)
    {
    case NETC_EVENT_CONNECT_OK:
        LOG_I("netc connect ok");
        break;
    case NETC_EVENT_CONNECT_FAIL:
        LOG_I("netc connect fail");
        break;
    case NETC_EVENT_CLOSE:
        LOG_I("netc remote closed");
        break;
    case NETC_EVENT_REVC:
        LOG_I("netc data revc");
        break;
    case NETC_EVENT_ERROR:
        LOG_I("netc errro happen");
        break;
    
    default:
        break;
    }
}
//----------------------------------------------------------------
// 新建socket对象
static int luat_lib_socket_tcp(lua_State* L) {
    return luat_lib_socket_new(L, NETC_TYPE_TCP);
}
static int luat_lib_socket_udp(lua_State* L) {
    return luat_lib_socket_new(L, NETC_TYPE_UDP);
}
//-----------------------------------------------------------------
static int luat_lib_socket_new(lua_State* L, int netc_type) {
    rt_netclient_t* thiz;
    rt_size_t len;

    // 强制GC一次
    LOG_D("force execute FULL GC");
    lua_gc(L, LUA_GCCOLLECT, 0);

    // 生成netc结构体
    LOG_D("init netclient ...");
    thiz = (rt_netclient_t*)lua_newuserdata(L, sizeof(rt_netclient_t));
    if (thiz == RT_NULL)
    {
        LOG_W("netclient, fail to create!!!!memory full?!");
        return RT_NULL;
    }
    else {
        LOG_I("netclient, create successd");
    }

    thiz->sock_fd = -1;
    thiz->pipe_read_fd = -1;
    thiz->pipe_write_fd = -1;
    rt_memset(thiz->pipe_name, 0, sizeof(thiz->pipe_name));
    thiz->rx = luat_lib_socket_ent_handler;
    thiz->type = netc_type;

    //rt_memset(thiz->hostname, 0, sizeof(thiz->hostname));
    thiz->hostname[0] = '_';
    thiz->hostname[1] = 0;
    thiz->port = 0;
    thiz->closed = 0;

    luaL_setmetatable(L, LUAT_NETC_HANDLE);

    return 1;
}

static int luat_lib_socket_connect(lua_State* L) {
    rt_netclient_t* thiz;
    size_t len;
    char* hostname;
    uint32_t port;
    rt_base_t re;
    LOG_I("luat_lib_socket_connect ...");
    if (lua_gettop(L) < 3) {
        LOG_W("socket.connect require 3 args! top=%d", lua_gettop(L));
        //lua_error("socket.connect require 3 args!");
        return 0;
    }
    if (!lua_isuserdata(L, 1)) {
        LOG_W("socket.connect require socket object!");
        return 0;
    }
    thiz = (rt_netclient_t*)lua_touserdata(L, 1);
    if (thiz == RT_NULL) {
        LOG_W("rt_netclient_t is NULL!!");
        return 0;
    }
    hostname = luaL_checklstring(L, 2, &len);
    if (len >= 32) {
        LOG_W("hostname is too long!!!");
        lua_pushinteger(L, 1);
        return 1;
    }
    rt_memcpy(thiz->hostname, hostname, len);
    thiz->hostname[len] = 0x00;
    thiz->port = luaL_checkinteger(L, 3);
    thiz->rx = luat_lib_socket_ent_handler;
    LOG_W("host=%s port=%d type=%s", thiz->hostname, thiz->port, thiz->type == NETC_TYPE_TCP ? "TCP" : "UDP");
    re = rt_netclient_start(thiz);
    lua_pushinteger(L, re);
    return 1;
}

static int luat_lib_socket_close(lua_State* L) {
    rt_netclient_t* thiz;
    if (!lua_isuserdata(L, 1)) {
        lua_error("socket.connect require socket object!");
        return 0;
    }
    thiz = (rt_netclient_t*)lua_touserdata(L, 1);
    if (thiz == RT_NULL) {
        return 0;
    }
    if (thiz->sock_fd == -1) {
        LOG_W("socket is closed, host=%s port=%ld", thiz->hostname, thiz->port);
    }
    rt_netclient_close(thiz);
    return 0;
}

static int luat_lib_socket_send(lua_State *L) {
    rt_netclient_t* thiz;
    size_t len;
    char* data;
    if (!lua_isuserdata(L, 1)) {
        lua_error("socket.connect require socket object!");
        return 0;
    }
    thiz = (rt_netclient_t*)lua_touserdata(L, 1);
    data = luaL_checklstring(L, 2, &len);
    if (len > 0) {
        rt_netclient_send(thiz, (void*)data, len);
    }
    return 0;
}

//---------------------------------------------
#define tonetc(L)	((rt_netclient_t *)luaL_checkudata(L, 1, LUAT_NETC_HANDLE))


static int netc_connect(lua_State *L) {
    return 0;
}

static int netc_close(lua_State *L) {
    rt_netclient_t *netc = tonetc(L);
    if (netc->closed == 0) {
        rt_netclient_close(netc);
    }
    return 0;
}

static int netc_send(lua_State *L) {
    size_t len;
    char* data;
    rt_netclient_t *netc;
    netc = tonetc(L);
    data = luaL_checklstring(L, 1, &len);
    if (len > 0) {
        rt_netclient_send(netc, (void*)data, len);
    }
    return 0;
}

static int netc_gc(lua_State *L) {
    rt_netclient_t *netc = tonetc(L);
    rt_netclient_close(netc);
    return 0;
}

static int netc_tostring(lua_State *L) {
    rt_netclient_t *netc = tonetc(L);
    lua_pushfstring(L, "netc(%s,%d,%s) %s", netc->hostname, netc->port, 
                                            netc->type == NETC_TYPE_TCP ? "TCP" : "UDP", 
                                            netc->closed ? "Closed" : "Not-Closed");
    return 1;
}

static const luaL_Reg lib_netc[] = {
    {"connect",     netc_connect},
    {"close",       netc_close},
    {"send",        netc_connect},
    //{"on",          netc_connect},
    {"__gc",        netc_gc},
    {"__tostring",  netc_tostring},
    {NULL, NULL}
};


static void createmeta (lua_State *L) {
  luaL_newmetatable(L, LUAT_NETC_HANDLE);  /* create metatable for file handles */
  lua_pushvalue(L, -1);  /* push metatable */
  lua_setfield(L, -2, "__index");  /* metatable.__index = metatable */
  luaL_setfuncs(L, lib_netc, 0);  /* add file methods to new metatable */
  lua_pop(L, 1);  /* pop new metatable */
}


#include "rotable.h"
static const rotable_Reg reg_socket[] =
{
    { "tcp", luat_lib_socket_tcp, 0},
    { "udp", luat_lib_socket_udp, 0},
    { "connect", luat_lib_socket_connect, 0},
    { "close", luat_lib_socket_close, 0},
    { "send", luat_lib_socket_send, 0},



    { "tsend" ,  sal_tls_test , 0},
    #ifdef PKG_NETUTILS_NTP
    { "ntpSync", socket_ntp_sync, 0},
    #endif
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_socket( lua_State *L ) {
    rotable_newlib(L, reg_socket);
    createmeta(L);
    return 1;
}

#endif
/*
@module  socket
@summary socket操作库
@version 1.0
@data    2020.03.30
*/
#include "luat_base.h"
#include "luat_log.h"
#include "luat_timer.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"


#define LUAT_NETC_HANDLE "NETC*"

/*
ntp时间同步
@function    socket.ntpSync(server)
@string ntp服务器域名,默认值ntp1.aliyun.com
@return int 启动成功返回0, 失败返回1或者2
--  如果读取失败,会返回nil
socket.ntpSync()
sys.subscribe("NTP_UPDATE", function(re)
    log.info("ntp", "result", re)
end)
*/
static int socket_ntp_sync(lua_State *L) {
    const char* hostname = luaL_optstring(L, 1, "ntp1.aliyun.com");
    int re = luat_socket_ntp_sync(hostname);
    lua_pushinteger(L, re);
    return 1;
}

/*
直接向地址发送一段数据
@function    socket.tsend(host, port, data)
@string 服务器域名或者ip
@int    服务器端口号
@string 待发送的数据
@return nil 无返回值
--  如果读取失败,会返回nil
socket.tsend("www.baidu.com", 80, "GET / HTTP/1.0\r\n\r\n")
*/
static int sal_tls_test(lua_State *L)
{
    size_t len;
    const char* buff = luaL_checklstring(L, 3, &len);
    luat_socket_tsend(luaL_checkstring(L, 1), luaL_checkinteger(L, 2), buff, len);
    return 0;
}

/*
网络是否就绪
@function    socket.isReady()
@return boolean 已联网返回true,否则返回false
*/
static int l_socket_is_ready(lua_State *L) {
    lua_pushboolean(L, luat_socket_is_ready());
    return 1;
}

/*
获取自身ip,通常是内网ip
@function    socket.ip()
@return string 已联网返回ip地址,否则返回nil
*/
static int l_socket_selfip(lua_State *L) {
    uint32_t ip = luat_socket_selfip();
    if (ip == 0) {
        return 0;
    }
    lua_pushfstring(L, "%d.%d.%d.%d", (ip >> 0) & 0xFF, (ip >> 8) & 0xFF, (ip >> 16) & 0xFF, (ip >> 24) & 0xFF);
    return 1;
}


#include "netclient.h"

static int luat_lib_netc_msg_handler(lua_State* L, void* ptr) {
    netc_ent_t* ent = (netc_ent_t*)ptr;
    if (ent->event == NETC_EVENT_END) {
        lua_getglobal(L, "sys_pub");
        if (lua_isfunction(L, -1)) {
            lua_pushfstring(L, "NETC_END_%d", ent->netc_id);
            lua_call(L, 1, 0);
        }
        goto exit;
    }
    luat_log_debug("luat.socket", "luat_lib_netc_msg_handler event=%ld lua_ref=%ld", ent->event, ent->lua_ref);
    if (lua_rawgeti(L, LUA_REGISTRYINDEX, ent->lua_ref) != LUA_TFUNCTION) {
        //LOG_W("netc[%ld] callback isn't a function", ent->netc_id);
        goto exit;
    };
    lua_pushinteger(L, ent->netc_id);
    switch (ent->event)
    {
    case NETC_EVENT_CONNECT_OK:
        lua_pushinteger(L, 1);
        lua_call(L, 2, 0);
        break;
    case NETC_EVENT_CONNECT_FAIL:
        lua_pushinteger(L, 0);
        lua_call(L, 2, 0);
        break;
    //case NETC_EVENT_CLOSE:
    //    lua_call(L, 1, 0);
    //    break;
    case NETC_EVENT_RECV:
        lua_pushlstring(L, ent->buff, ent->len);
        //lua_pushliteral(L, "");
        lua_call(L, 2, 0);
        break;
    case NETC_EVENT_ERROR:
        lua_call(L, 1, 0);
        break;
    default:
        break;
    }
exit:
    if (ent->buff) {
        luat_heap_free((void*)ent->buff);
    }
    luat_heap_free((void*)ent);
    return 0;
}

static int luat_lib_socket_new(lua_State* L, int netc_type);
static int luat_lib_socket_ent_handler(netc_ent_t* ent) {
    if (ent->event != NETC_EVENT_END && ent->lua_ref == 0) {
        if (ent->buff) {
            luat_heap_free((void*)ent->buff);
        }
        luat_heap_free((void*)ent);
        return 0;
    }
    rtos_msg_t msg;
    msg.handler = luat_lib_netc_msg_handler;
    msg.ptr = ent;
    luat_msgbus_put(&msg, 1);
    return 0;
}
//----------------------------------------------------------------
/*
新建一个tcp socket
@function    socket.tcp()
@return object socket对象,如果创建失败会返回nil
--  如果读取失败,会返回nil
local so = socket.tcp()
if so then
    so:host("www.baidu.com")
    so:port(80)
    so:on("connect", function(id, re)
        if re == 1 then
            so:send("GET / HTTP/1.0\r\n\r\n")
        end
    end)
    so:on("recv", function(id, data)
        log.info("netc", id, data)
    end)
    if so:start() == 1 then
        sys.waitUntil("NETC_END_" .. so:id())
    end
    so:close()
    so:clean()
end
*/
static int luat_lib_socket_tcp(lua_State* L) {
    return luat_lib_socket_new(L, NETC_TYPE_TCP);
}
/*
新建一个udp socket
@function    socket.udp()
@return nil 暂不支持
*/
static int luat_lib_socket_udp(lua_State* L) {
    return luat_lib_socket_new(L, NETC_TYPE_UDP);
}
//-----------------------------------------------------------------
static int luat_lib_socket_new(lua_State* L, int netc_type) {
    netclient_t* thiz;
    size_t len;

    // 强制GC一次
    //LOG_D("force execute FULL GC");
    //lua_gc(L, LUA_GCCOLLECT, 0);

    // 生成netc结构体
    //LOG_D("init netclient ...");
    thiz = (netclient_t*)lua_newuserdata(L, sizeof(netclient_t));
    if (thiz == NULL)
    {
        //LOG_W("netclient, fail to create!!!!memory full?!");
        return 0;
    }

    memset(thiz, 0, sizeof(netclient_t));

    thiz->sock_fd = -1;
    thiz->pipe_read_fd = -1;
    thiz->pipe_write_fd = -1;
    thiz->rx = luat_lib_socket_ent_handler;
    thiz->type = netc_type;

    //rt_memset(thiz->hostname, 0, sizeof(thiz->hostname));
    thiz->hostname[0] = '_';
    thiz->id = netc_next_no();

    luaL_setmetatable(L, LUAT_NETC_HANDLE);

    //LOG_I("netc[%ld] create successd", thiz->id);
    return 1;
}

// static int luat_lib_socket_connect(lua_State* L) {
//     netclient_t* thiz;
//     size_t len;
//     char* hostname;
//     uint32_t port;
//     rt_base_t re;
//     //LOG_I("luat_lib_socket_connect ...");
//     if (lua_gettop(L) < 3) {
//         LOG_W("socket.connect require 3 args! top=%d", lua_gettop(L));
//         //lua_error("socket.connect require 3 args!");
//         return 0;
//     }
//     if (!lua_isuserdata(L, 1)) {
//         LOG_W("socket.connect require socket object!");
//         return 0;
//     }
//     thiz = (netclient_t*)lua_touserdata(L, 1);
//     if (thiz == RT_NULL) {
//         LOG_W("netclient_t is NULL!!");
//         return 0;
//     }
//     hostname = luaL_checklstring(L, 2, &len);
//     if (len >= 32) {
//         LOG_W("hostname is too long!!!");
//         lua_pushinteger(L, 1);
//         return 1;
//     }
//     rt_memcpy(thiz->hostname, hostname, len);
//     thiz->hostname[len] = 0x00;
//     thiz->port = luaL_checkinteger(L, 3);
//     thiz->rx = luat_lib_socket_ent_handler;
//     LOG_W("host=%s port=%d type=%s", thiz->hostname, thiz->port, thiz->type == NETC_TYPE_TCP ? "TCP" : "UDP");
//     re = netclient_start(thiz);
//     lua_pushinteger(L, re);
//     return 1;
// }

// static int luat_lib_socket_close(lua_State* L) {
//     netclient_t* thiz;
//     if (!lua_isuserdata(L, 1)) {
//         lua_error("socket.connect require socket object!");
//         return 0;
//     }
//     thiz = (netclient_t*)lua_touserdata(L, 1);
//     if (thiz == RT_NULL) {
//         return 0;
//     }
//     if (thiz->sock_fd == -1) {
//         LOG_W("socket is closed, host=%s port=%ld", thiz->hostname, thiz->port);
//     }
//     netclient_close(thiz);
//     return 0;
// }

// static int luat_lib_socket_send(lua_State *L) {
//     netclient_t* thiz;
//     size_t len;
//     char* data;
//     if (!lua_isuserdata(L, 1)) {
//         lua_error(L, "socket.connect require socket object!");
//         return 0;
//     }
//     thiz = (netclient_t*)lua_touserdata(L, 1);
//     data = luaL_checklstring(L, 2, &len);
//     if (len > 0) {
//         netclient_send(thiz, (void*)data, len);
//     }
//     return 0;
// }

//---------------------------------------------
#define tonetc(L)	((netclient_t *)luaL_checkudata(L, 1, LUAT_NETC_HANDLE))

/*
启动socket线程
@function    so:start(host, port)
@string 服务器域名或ip,如果已经使用so:host和so:port配置,就不需要传参数了
@port 服务器端口,如果已经使用so:host和so:port配置,就不需要传参数了
@return int 成功返回1,失败返回0
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_connect(lua_State *L) {
    netclient_t* thiz;
    size_t len;
    uint32_t port;
    int re;
    thiz = tonetc(L);
    if (lua_gettop(L) < 2) {
        if (thiz->hostname[1] != 0x00 && thiz->port > 0) {
            // ok
        }
        else {
            //LOG_W("sock:connect require 2 args! top=%d", lua_gettop(L));
            lua_pushinteger(L, 2);
            return 1;
        }
    }
    else {
        const char* hostname = luaL_checklstring(L, 2, &len);
        if (len >= 32) {
            //LOG_E("netc[%ld] hostname is too long >= 32", thiz->id);
            lua_pushinteger(L, 1);
            return 1;
        }
        memcpy(thiz->hostname, hostname, len);
        thiz->hostname[len] = 0x00;
        thiz->port = luaL_optinteger(L, 3, 80);
    }
    thiz->rx = luat_lib_socket_ent_handler;
    //LOG_I("netc[%ld] host=%s port=%d type=%s", thiz->id, thiz->hostname, thiz->port, thiz->type == NETC_TYPE_TCP ? "TCP" : "UDP");
    re = netclient_start(thiz);
    lua_pushinteger(L, re);
    return 1;
}

/*
关闭socket对象
@function    so:close()
@return nil 总会成功
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_close(lua_State *L) {
    netclient_t *netc = tonetc(L);
    if (netc->closed == 0) {
        netclient_close(netc);
    }
    return 0;
}

/*
通过socket对象发送数据
@function    so:send(data)
@string 待发送数据
@return boolean 发送成功返回true,否则返回false
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_send(lua_State *L) {
    size_t len = 0;
    
    netclient_t *netc;
    netc = tonetc(L);
    const char* data = luaL_checklstring(L, 2, &len);
    if (len > 0) {
        int32_t re = netclient_send(netc, (void*)data, len);
        lua_pushboolean(L, re == len ? 1 : 0);
    }
    else {
        lua_pushboolean(L, 0);
    }
    return 1;
}

static int netc_gc(lua_State *L) {
    netclient_t *netc = tonetc(L);
    luat_log_info("netc", "netc[%ld] __gc trigger", netc->id);
    netclient_close(netc);
    if (netc->cb_error) {
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_error);
    }
    if (netc->cb_recv) {
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_recv);
    }
    if (netc->cb_close) {
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_close);
    }
    if (netc->cb_connect) {
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_connect);
    }
    return 0;
}


static int netc_tostring(lua_State *L) {
    netclient_t *netc = tonetc(L);
    lua_pushfstring(L, "netc[%d] %s,%d,%s %s", netc->id,
                                            netc->hostname, netc->port, 
                                            netc->type == NETC_TYPE_TCP ? "TCP" : "UDP", 
                                            netc->closed ? "Closed" : "Not-Closed");
    return 1;
}

/*
获取socket对象的id
@function    so:id()
@return int 对象id,自增量,全局唯一
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_id(lua_State *L) {
    netclient_t *netc = tonetc(L);
    lua_pushinteger(L, netc->id);
    return 1;
}

/*
设置服务器域名或ip
@function    so:host(host)
@string 服务器域名或ip
@return nil 无返回值
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_host(lua_State *L) {
    netclient_t *netc = tonetc(L);
    if (lua_gettop(L) > 1 && lua_isstring(L, 2)) {
        size_t len;
        const char* hostname = luaL_checklstring(L, 2, &len);
        if (len >= 32) {
            //LOG_E("netc[%ld] hostname is too long!!!", netc->id);
            lua_pushinteger(L, 1);
            return 1;
        }
        memcpy(netc->hostname, hostname, len);
        netc->hostname[len] = 0x00;
        //LOG_I("netc[%ld] host=%s", netc->id, netc->hostname);
    }
    lua_pushstring(L, netc->hostname);
    return 1;
}

/*
设置服务器端口
@function    so:port(port)
@int 服务器端口
@return nil 无返回值
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_port(lua_State *L) {
    netclient_t *netc = tonetc(L);
    if (lua_gettop(L) > 1 && lua_isinteger(L, 2)) {
        netc->port = lua_tointeger(L, 2);
        //LOG_I("netc[%ld] port=%d", netc->id, netc->port);
    }
    lua_pushinteger(L, netc->port);
    return 1;
}

/*
清理socket关联的资源,socket对象在废弃前必须调用
@function    so:clean(0)
@return nil 无返回值
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_clean(lua_State *L) {
    netclient_t *netc = tonetc(L);
    if (!netc->closed) {
        netc_close(L);
    }
    if (netc->cb_error) {
        //LOG_D("netc[%ld] unref 0x%08X", netc->id, netc->cb_error);
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_error);
        netc->cb_error = 0;
    }
    if (netc->cb_recv) {
        //LOG_D("netc[%ld] unref 0x%08X", netc->id, netc->cb_recv);
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_recv);
        netc->cb_recv = 0;
    }
    if (netc->cb_close) {
        //LOG_D("netc[%ld] unref 0x%08X", netc->id, netc->cb_close);
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_close);
        netc->cb_close = 0;
    }
    if (netc->cb_connect) {
        //LOG_D("netc[%ld] unref 0x%08X", netc->id, netc->cb_connect);
        luaL_unref(L, LUA_REGISTRYINDEX, netc->cb_connect);
        netc->cb_connect = 0;
    }
    return 0;
}

/*
设置socket的事件回调
@function    so:port(event, func)
@string 事件名称
@function 回调方法
@return nil 无返回值
-- 参考socket.tcp的说明, 并查阅demo
*/
static int netc_on(lua_State *L) {
    netclient_t *netc = tonetc(L);
    if (lua_gettop(L) < 3) {
        return 0;
    }
    if (lua_isstring(L, 2)) {
        if (lua_isfunction(L, 3)) {
            const char* ent = lua_tostring(L, 2);
            lua_pushvalue(L, 3);
            if (strcmp("recv", ent) == 0) {
                netc->cb_recv = luaL_ref(L, LUA_REGISTRYINDEX);
            }
            else if (strcmp("close", ent) == 0) {
                netc->cb_close = luaL_ref(L, LUA_REGISTRYINDEX);
            }
            else if (strcmp("connect", ent) == 0) {
                netc->cb_connect = luaL_ref(L, LUA_REGISTRYINDEX);
            }
            //else if (strcmp("any", ent) == 0) {
            //    netc->cb_any = luaL_ref(L, LUA_REGISTRYINDEX);
            //}
            else if (strcmp("error", ent) == 0) {
                netc->cb_error = luaL_ref(L, LUA_REGISTRYINDEX);
            }
            else {
                //LOG_I("netc[%ld] unkown event type=%s", netc->id, ent);
            }
        }
    }
    return 0;
}

static int netc_closed(lua_State *L) {
    netclient_t *netc = tonetc(L);
    lua_pushinteger(L, netc->closed);
    return 1;
}

static const luaL_Reg lib_netc[] = {
    {"id",          netc_id},
    {"host",        netc_host},
    {"port",        netc_port},
    {"connect",     netc_connect},
    {"start",       netc_connect},
    {"close",       netc_close},
    {"closed",      netc_closed},
    {"send",        netc_send},
    {"clean",       netc_clean},
    {"on",          netc_on},
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
    // { "connect", luat_lib_socket_connect, 0},
    // { "close", luat_lib_socket_close, 0},
    // { "send", luat_lib_socket_send, 0},



    { "tsend" ,  sal_tls_test , 0},
    { "ntpSync", socket_ntp_sync, 0}, // TODO 改成平台无关的UDP实现?
    { "isReady", l_socket_is_ready, 0},
    { "ip", l_socket_selfip, 0},
	{ NULL, NULL , 0}
};

LUAMOD_API int luaopen_socket( lua_State *L ) {
    rotable_newlib(L, reg_socket);
    createmeta(L);
    return 1;
}


#include "luat_base.h"
#include "luat_malloc.h"
#include "luat_msgbus.h"

#define LUAT_LOG_TAG "lwip.tcp"
#include "luat_log.h"

#include "lwip/tcp.h"

// 用于存储回调信息的数据结构, 通过tcp_arg传给tcp_pcb*
typedef struct luat_lwip_tcp {
    int conn_cb;
    int recv_cb;
    int sent_cb;
    int err_cb;
    int poll_cb;
    int accept_cb;
} luat_lwip_tcp_t;

// 几个回调代理函数
static int l_lwip_cb_handler(lua_State* L, void* ptr) {
    rtos_msg_t* msg = (rtos_msg_t*)lua_topointer(L, -1);
    lua_geti(L, LUA_REGISTRYINDEX, msg->arg1);
    if (lua_isfunction(L, -1)) {
        lua_pushinteger(L, msg->arg2);
        lua_call(L, 1, 0);
    }
    return 0;
}

static err_t luat_lwip_tcp_connected_fn(void *arg, struct tcp_pcb *tpcb, err_t err) {
    if (((luat_lwip_tcp_t*)arg)->conn_cb == 0) {
        LLOGI("miss connection callback function");
        return ERR_OK;
    }
    rtos_msg_t msg = {0};
    msg.handler = l_lwip_cb_handler;
    msg.ptr = NULL;
    msg.arg1 = ((luat_lwip_tcp_t*)arg)->conn_cb;
    msg.arg2 = err;
    luat_msgbus_put(&msg, 0);
    return ERR_OK;
};

static err_t luat_lwip_tcp_sent_fn(void *arg, struct tcp_pcb *tpcb, u16_t len) {
    if (((luat_lwip_tcp_t*)arg)->sent_cb == 0) {
        LLOGI("miss sent callback function");
        return ERR_OK;
    }
    rtos_msg_t msg = {0};
    msg.handler = l_lwip_cb_handler;
    msg.ptr = NULL;
    msg.arg1 = ((luat_lwip_tcp_t*)arg)->sent_cb;
    msg.arg2 = len;
    luat_msgbus_put(&msg, 0);
    return ERR_OK;
};

static err_t luat_lwip_tcp_recv_fn(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err) {
    if (((luat_lwip_tcp_t*)arg)->recv_cb == 0) {
        LLOGI("miss recv callback function");
        return ERR_OK;
    }
    rtos_msg_t msg = {0};
    msg.handler = l_lwip_cb_handler;
    msg.ptr = p;
    msg.arg1 = ((luat_lwip_tcp_t*)arg)->recv_cb;
    msg.arg2 = err;
    luat_msgbus_put(&msg, 0);
    return ERR_OK;
};

static err_t luat_lwip_tcp_err_fn(void *arg, err_t err) {
    if (((luat_lwip_tcp_t*)arg)->err_cb == 0) {
        LLOGI("miss err callback function");
        return ERR_OK;
    }
    rtos_msg_t msg = {0};
    msg.handler = l_lwip_cb_handler;
    msg.ptr = NULL;
    msg.arg1 = ((luat_lwip_tcp_t*)arg)->err_cb;
    msg.arg2 = err;
    luat_msgbus_put(&msg, 0);
    return ERR_OK;
};

static err_t luat_lwip_tcp_poll_fn(void *arg, struct tcp_pcb *tpcb) {
    if (((luat_lwip_tcp_t*)arg)->poll_cb == 0) {
        LLOGI("miss connection callback function");
        return ERR_OK;
    }
    rtos_msg_t msg = {0};
    msg.handler = l_lwip_cb_handler;
    msg.ptr = tpcb;
    msg.arg1 = ((luat_lwip_tcp_t*)arg)->poll_cb;
    msg.arg2 = ERR_OK;
    luat_msgbus_put(&msg, 0);
    return ERR_OK;
};

static err_t luat_lwip_tcp_accept_fn(void *arg, struct tcp_pcb *newpcb, err_t err) {
    if (((luat_lwip_tcp_t*)arg)->poll_cb == 0) {
        LLOGI("miss connection callback function");
        return ERR_OK;
    }
    rtos_msg_t msg = {0};
    msg.handler = l_lwip_cb_handler;
    msg.ptr = newpcb;
    msg.arg1 = ((luat_lwip_tcp_t*)arg)->poll_cb;
    msg.arg2 = err;
    luat_msgbus_put(&msg, 0);
    return ERR_OK;
};

//----------------------------------------------------------------

/*
新建一个TCP控制结构
@api lwip.tcp_new()
@return userdata tcp结构体,如果内存不足会返回nil
@usage
local tcp_site0 = lwip.tcp_new()
if tcp_site0 then
    lwip.tcp_arg(tcp_site0, {
        "conn"= function(ret)
            lwip.tcp_write(tcp_site0, "hi")
            lwip.tcp_output(tcp_site0)
        end,
        "err" = function(err) 
            log.info("lwip", "tcp closed", err)
            sys.publish("TCP_CLOSED")
        end,
        "sent" = function(err)
            log.info("lwip", "data sent", err)
        end,
        "recv" = function(err)
            if err = lwip.ERR_OK then
                local data = lwip.tcp_read(tcp_site0)
                if data then
                    log.info("lwip", "recv", data:toHex())
                end
            end
        end
        while sys.waitUtil("TCP_CLOSED", 30000) do
            
        end
    })
end
*/
int l_lwip_tcp_new(lua_State* L) {
    struct tcp_pcb * pcb = tcp_new();
    if (pcb == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "tcp_new err");
        return 2;
    }
    lua_pushlightuserdata(L, pcb);
    return 1;
}

int l_lwip_tcp_new_ip6(lua_State* L) {
    struct tcp_pcb * pcb = tcp_new_ip6();
    if (pcb == NULL) {
        lua_pushnil(L);
        lua_pushliteral(L, "tcp_new err");
        return 2;
    }
    lua_pushlightuserdata(L, pcb);
    return 1;
}

int l_lwip_tcp_arg(lua_State* L) {
    struct tcp_pcb * pcb = lua_touserdata(L, 1);
    luat_lwip_tcp_t* ltcp = luat_heap_malloc(sizeof(luat_lwip_tcp_t));
    if (ltcp == NULL) {
        tcp_close(pcb);
        lua_pushnil(L);
        lua_pushliteral(L, "sys is out of memory");
        return 2;
    }
    memset(ltcp, 0, sizeof(luat_lwip_tcp_t));
    if (lua_istable(L, 2)) {

        lua_pushliteral(L, "conn");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1))
            ltcp->conn_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        else
            lua_pop(L, 1);

        lua_pushliteral(L, "err");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1))
            ltcp->err_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        else 
            lua_pop(L, 1);

        lua_pushliteral(L, "sent");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1))
            ltcp->sent_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        else 
            lua_pop(L, 1);

        lua_pushliteral(L, "recv");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1))
            ltcp->recv_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        else
            lua_pop(L, 1);

        lua_pushliteral(L, "poll");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1))
            ltcp->poll_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        else 
            lua_pop(L, 1);

        lua_pushliteral(L, "accept");
        lua_gettable(L, 2);
        if (lua_isfunction(L, -1))
            ltcp->accept_cb = luaL_ref(L, LUA_REGISTRYINDEX);
        else
            lua_pop(L, 1);
    }

    tcp_arg(pcb, ltcp);
    tcp_err(pcb, luat_lwip_tcp_err_fn);
    tcp_sent(pcb, luat_lwip_tcp_sent_fn);
    tcp_recv(pcb, luat_lwip_tcp_recv_fn);
    //tcp_poll(pcb, luat_lwip_tcp_poll_fn);
    tcp_accept(pcb, luat_lwip_tcp_accept_fn);

    lua_pushlightuserdata(L, pcb);
    return 1;
}

int l_lwip_tcp_connect(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    size_t len = 0;
    const char* ip = luaL_checklstring(L, 2, &len);
    uint16_t port = luaL_checkinteger(L, 3);
    ip_addr_t ipaddr = {0};
    if (ipaddr_aton(ip, &ipaddr) == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "bad ip");
        return 2;
    }
    err_t err = tcp_connect(pcb, &ipaddr, port, luat_lwip_tcp_connected_fn);
    lua_pushboolean(L, err == ERR_OK ? 1 : 0);
    return 1;
}

int l_lwip_tcp_bind(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    size_t len = 0;
    const char* ip = luaL_checklstring(L, 2, &len);
    uint16_t port = luaL_checkinteger(L, 3);
    ip_addr_t ipaddr = {0};
    if (ipaddr_aton(ip, &ipaddr) == 0) {
        lua_pushnil(L);
        lua_pushliteral(L, "bad ip");
        return 2;
    }
    err_t err = tcp_bind(pcb, &ipaddr, port);
    lua_pushboolean(L, err == ERR_OK ? 1 : 0);
    return 1;
}

int l_lwip_tcp_write(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    size_t len = 0;
    const char* data = luaL_checklstring(L, 2, &len);
    uint8_t apiflags = luaL_optinteger(L, 3, 1);
    err_t err = tcp_write(pcb, data, len, apiflags);
    lua_pushboolean(L, err == ERR_OK ? 1 : 0);
    return 1;
}

int l_lwip_tcp_output(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    err_t err = tcp_output(pcb);
    lua_pushboolean(L, err == ERR_OK ? 1 : 0);
    return 1;
}

// int l_lwip_tcp_sent(lua_State* L) {
//     struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
//     err_t err = tcp_sent(pcb, luat_lwip_tcp_sent_fn);
//     lua_pushboolean(L, err == ERR_OK ? 1 : 0);
//     return 1;
// }

// int l_lwip_tcp_recv(lua_State* L) {
//     struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
//     err_t err = tcp_recv(pcb, luat_lwip_tcp_recv_fn);
//     lua_pushboolean(L, err == ERR_OK ? 1 : 0);
//     return 1;
// }

int l_lwip_tcp_recved(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    size_t len = luaL_checkinteger(L, 2);
    tcp_recved(pcb, len);
    return 0;
}

int l_lwip_tcp_close(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    err_t err = tcp_close(pcb);
    lua_pushboolean(L, err == ERR_OK ? 1 : 0);
    return 1;
}

int l_lwip_tcp_abort(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    tcp_abort(pcb);
    lua_pushboolean(L, 1);
    return 1;
}

int l_lwip_tcp_shutdown(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    int rx = luaL_checkinteger(L, 2);
    int tx = luaL_checkinteger(L, 3);
    err_t err = tcp_shutdown(pcb, rx, tx);
    lua_pushboolean(L, err == ERR_OK ? 1 : 0);
    return 1;
}

int l_lwip_tcp_listen(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    int backlog = luaL_optinteger(L, 2, TCP_DEFAULT_LISTEN_BACKLOG);
    struct tcp_pcb *  srv_pcb = tcp_listen_with_backlog(pcb, backlog);
    lua_pushlightuserdata(L, srv_pcb);
    return 1;
}

int l_lwip_tcp_accepted(lua_State* L) {
    struct tcp_pcb * pcb = (struct tcp_pcb*)lua_touserdata(L, 1);
    tcp_accepted(pcb);
    return 0;
}

/*
@module  httpsrv
@summary http服务端
@version 1.0
@date    2022.010.15
@demo wlan
@tag LUAT_USE_HTTPSRV
*/

#include "luat_base.h"
#include "luat_rtos.h"
#include "luat_httpsrv.h"
#include "luat_network_adapter.h"
#include "luat_netdrv.h"
#include "lwip/netif.h"
#include "lwip/ip_addr.h"

#define LUAT_LOG_TAG "httpsrv"
#include "luat_log.h"

#define LUAT_HTTPSRV_COUNT 16

// 服务槽位, 空槽为NULL
// ctx生命周期: start成功时挂载到本数组, stop时摘除, ctx内存由lwip线程(srv_stop_cb)释放
static luat_httpsrv_ctx_t* srvs[LUAT_HTTPSRV_COUNT];

/*
启动并监听一个http端口
@api httpsrv.start(port, func, adapter)
@int 端口号
@function 回调函数
@int 网络适配器编号, 默认是平台自带的网络协议栈, 传socket.LWIP_ANY表示绑定全部网卡(0.0.0.0)
@return bool 成功返回true, 否则返回false
@usage

-- 监听80端口
httpsrv.start(80, function(client, method, uri, headers, body)
    -- method 是字符串, 例如 GET POST PUT DELETE
    -- uri 也是字符串 例如 / /api/abc
    -- headers table类型
    -- body 字符串
    log.info("httpsrv", method, uri, json.encode(headers), body)
    if uri == "/led/1" then
        LEDA(1)
        return 200, {}, "ok"
    elseif uri == "/led/0" then
        LEDA(0)
        return 200, {}, "ok"
    end
    -- 返回值的约定 code, headers, body
    -- 若没有返回值, 则默认 404, {} ,""
    return 404, {}, "Not Found" .. uri
end)
-- 绑定全部网卡, 任意网卡(STA/AP/蜂窝/以太网)上的客户端均可访问
httpsrv.start(80, on_request, socket.LWIP_ANY)
-- 关于静态文件
-- 情况1: / , 映射为 /index.html
-- 情况2: /abc.html , 先查找 /abc.html, 不存在的话查找 /abc.html.gz
-- 若gz存在, 会自动以压缩文件进行响应, 绝大部分浏览器支持.
-- 当前默认查找 /luadb/xxx 下的文件,暂不可配置
*/
static int l_httpsrv_start(lua_State *L) {
    char buff[64] = {0};
    int port = luaL_checkinteger(L, 1);
    if (!lua_isfunction(L, 2)) {
        LLOGW("httpsrv need callback function!!!");
        return 0;
    }
    uint8_t adapter_index = luaL_optinteger(L, 3, network_register_get_default());
    luat_netdrv_t* drv = NULL;
    if (adapter_index != NW_ADAPTER_INDEX_LWIP_ANY) {
        drv = luat_netdrv_get(adapter_index);
        if (drv == NULL || drv->netif == NULL) {
            LLOGW("该网络还没准备好 %d", adapter_index);
            return 0;
        }
    }
    // 冲突检查: 端口相同且(adapter相同 或 任一方绑定全部网卡)视为冲突
    for (size_t i = 0; i < LUAT_HTTPSRV_COUNT; i++)
    {
        if (srvs[i] != NULL && srvs[i]->port == port) {
            if (srvs[i]->adapter_id == adapter_index
                || srvs[i]->adapter_id == NW_ADAPTER_INDEX_LWIP_ANY
                || adapter_index == NW_ADAPTER_INDEX_LWIP_ANY) {
                LLOGW("httpsrv port %d already in use", port);
                return 0;
            }
        }
    }
    // 找一个空槽位
    int index = -1;
    for (size_t i = 0; i < LUAT_HTTPSRV_COUNT; i++)
    {
        if (srvs[i] == NULL) {
            index = i;
            break;
        }
    }
    if (index < 0) {
        LLOGW("httpsrv no free slot, max %d", LUAT_HTTPSRV_COUNT);
        return 0;
    }

    luat_httpsrv_ctx_t* ctx = luat_httpsrv_malloc(port, adapter_index);
    if (ctx == NULL) {
        return 0;
    }
    ctx->netif = drv ? drv->netif : NULL;
    lua_pushvalue(L, 2);
    ctx->lua_ref_id = luaL_ref(L, LUA_REGISTRYINDEX);
    // 同步等待lwip线程完成bind/listen, 避免bind失败但Lua侧假成功
    if (luat_rtos_semaphore_create(&ctx->start_sem, 0)) {
        LLOGE("create start_sem failed");
        luaL_unref(L, LUA_REGISTRYINDEX, ctx->lua_ref_id);
        ctx->lua_ref_id = LUA_NOREF;
        luat_httpsrv_free(ctx);
        return 0;
    }
    int ret = luat_httpsrv_start(ctx);
    if (ret == 0) {
        if (luat_rtos_semaphore_take(ctx->start_sem, 3000) == 0) {
            // start_cb已执行完毕, 结果有效
            ret = ctx->start_ret;
        }
        else {
            // tcpip线程3秒未响应, 系统级故障, ctx与sem只能泄漏, 不能释放(避免use-after-free)
            LLOGE("wait httpsrv start result timeout, tcpip thread dead?");
            return 0;
        }
    }
    luat_rtos_semaphore_delete(ctx->start_sem);
    ctx->start_sem = NULL;
    if (ret == 0) {
        if (ctx->netif) {
            ipaddr_ntoa_r(&ctx->netif->ip_addr, buff, 32);
        }
        else {
            memcpy(buff, "0.0.0.0", 8);
        }
        LLOGI("http listen at %s:%d", buff, ctx->port);
        srvs[index] = ctx;
    }
    else {
        LLOGW("httpsrv start failed, bind/listen ret %d", ret);
        luaL_unref(L, LUA_REGISTRYINDEX, ctx->lua_ref_id);
        ctx->lua_ref_id = LUA_NOREF;
        luat_httpsrv_free(ctx);
    }
    lua_pushboolean(L, ret == 0 ? 1 : 0);
    return 1;
}

/*
停止http服务
@api httpsrv.stop(port，no_used, adapter)
@int 端口号
@nil 固定写nil
@int 网络适配器编号, 默认是平台自带的网络协议栈, 停止绑定全部网卡的服务需传socket.LWIP_ANY
@return bool 成功返回true, 否则返回false
@usage
httpsrv.stop(SERVER_PORT,nil,socket.LWIP_AP)
httpsrv.stop(SERVER_PORT,nil,socket.LWIP_ANY) -- 停止绑全部网卡的服务
*/
static int l_httpsrv_stop(lua_State *L) {
    int port = luaL_checkinteger(L, 1);
    uint8_t adapter_index = luaL_optinteger(L, 3, network_register_get_default());
    for (size_t i = 0; i < LUAT_HTTPSRV_COUNT; i++)
    {
        if (srvs[i] != NULL && srvs[i]->port == port && srvs[i]->adapter_id == adapter_index) {
            luat_httpsrv_ctx_t* ctx = srvs[i];
            srvs[i] = NULL;
            if (ctx->lua_ref_id != LUA_NOREF) {
                luaL_unref(L, LUA_REGISTRYINDEX, ctx->lua_ref_id);
                ctx->lua_ref_id = LUA_NOREF;
            }
            luat_httpsrv_stop(ctx);
            lua_pushboolean(L, 1);
            return 1;
        }
    }
    lua_pushboolean(L, 0);
    return 1;
}

/*
设置httpsrv的调试开关
@api httpsrv.debug(on)
@bool 是否打开调试信息输出
@return bool 当前调试状态，true为打开，false为关闭
@usage
-- 打开调试信息
httpsrv.debug(true)
-- 关闭调试信息
httpsrv.debug(false)
*/
extern int g_httpsrv_debug;
static int l_httpsrv_debug(lua_State *L) {
    if (lua_isboolean(L, 1)) {
        g_httpsrv_debug = lua_toboolean(L, 1) ? 1 : 0;
    }
    lua_pushboolean(L, g_httpsrv_debug ? 1 : 0);
    return 1;
}

#include "rotable2.h"
static const rotable_Reg_t reg_httpsrv[] =
{
    {"start",        ROREG_FUNC(l_httpsrv_start) },
    {"stop",         ROREG_FUNC(l_httpsrv_stop) },
    {"debug",        ROREG_FUNC(l_httpsrv_debug)},
	{ NULL,          ROREG_INT(0) }
};

LUAMOD_API int luaopen_httpsrv( lua_State *L ) {
    luat_newlib2(L, reg_httpsrv);
    return 1;
}

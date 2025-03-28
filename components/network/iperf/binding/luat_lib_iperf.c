/*
@module  iperf
@summary 吞吐量测试
@catalog 网络API
@version 1.0
@date    2025.02.14
@tag LUAT_USE_IPERF
@usage
-- 本库仅部分模组固件已添加
-- 当前仅支持server模式, client模式未添加
*/

#include "luat_base.h"
#include "luat_lwiperf.h"
#include "luat_network_adapter.h"
#include "luat_netdrv.h"
#include "lwip/ip.h"

#define LUAT_LOG_TAG "iperf"
#include "luat_log.h"

static void* iperf_session;

static int start_gogogo(int adpater_id, int is_server) {

    if (adpater_id < 0 || adpater_id >= NW_ADAPTER_INDEX_LWIP_NETIF_QTY) {
        // 必须明确指定合法的索引号
        LLOGE("非法的网络适配器索引号 %d", adpater_id);
        return 0;
    }
    // 首先, 通过netdrv获取对应的网络设备的netif
    luat_netdrv_t* drv = luat_netdrv_get(adpater_id);
    if (drv == NULL || drv->netif == NULL) {
        LLOGE("非法的网络适配器索引号 %d", adpater_id);
        return 0;
    }
    if (!netif_is_up(drv->netif) || !netif_is_link_up(drv->netif) || ip_addr_isany(&drv->netif->ip_addr)) {
        LLOGE("该网络还没就绪, 无法启动");
        return 0;
    }
    if (is_server) {
        char buff[64] = {0};
        ipaddr_ntoa_r(&drv->netif->ip_addr, buff, sizeof(buff));
        iperf_session = luat_lwiperf_start_tcp_server(&drv->netif->ip_addr, 5001, NULL, NULL);
        LLOGD("iperf listen %s:5001", buff);
    }
    else {
        //iperf_session = luat_lwiperf_start_tcp_server(&drv->netif->ip_addr, 5000, NULL, NULL);
        return 0;
    }
    return iperf_session != NULL;
}

/*
启动server模式
@api iperf.server(id)
@int 网络适配器的id, 必须填, 例如 socket.LWIP_ETH0
@return boolean 成功返回true, 失败返回false
@usage
-- 启动server模式, 监听5001端口
if iperf then
    log.info("启动iperf服务器端")
    iperf.server(socket.LWIP_ETH)
end
*/
static int l_iperf_server(lua_State *L) {
    if (iperf_session != NULL) {
        LLOGE("已经启动了server或者client,要先关掉才能启动新的");
        return 0;
    }
    int adpater_id = luaL_checkinteger(L, 1);
    if (start_gogogo(adpater_id, 1)) {
        lua_pushboolean(L, 1);
        return 1;
    }
    return 0;
}

static int l_iperf_client(lua_State *L) {
    return 0;
}

/*
关闭iperf
@api iperf.abort()
@return boolean 成功返回true, 失败返回false
@usage
-- 关闭已经启动的server或者client
*/
static int l_iperf_abort(lua_State *L) {
    if (iperf_session == NULL) {
        return 0;
    }
    luat_lwiperf_abort(iperf_session);
    lua_pushboolean(L, 1);
    return 1;
}


#include "rotable2.h"
static const rotable_Reg_t reg_iperf[] =
{
    { "server" ,           ROREG_FUNC(l_iperf_server)},
    { "client" ,           ROREG_FUNC(l_iperf_client)},
    { "abort" ,            ROREG_FUNC(l_iperf_abort)},
	{ NULL,               ROREG_INT(0)}
};

LUAMOD_API int luaopen_iperf( lua_State *L ) {
    luat_newlib2(L, reg_iperf);
    return 1;
}

